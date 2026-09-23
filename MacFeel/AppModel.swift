import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var capabilities = Capabilities()

    // MARK: Lid angle

    var lidEnabled = true {
        didSet {
            persist(lidEnabled, as: DefaultsKey.lid)
            lidEnabled ? startLid() : stopLid()
        }
    }
    private(set) var lidAngle: Double?
    private(set) var lidError: SensorError?

    // MARK: Ambient light

    var lightEnabled = true {
        didSet {
            persist(lightEnabled, as: DefaultsKey.light)
            lightEnabled ? startLight() : stopLight()
        }
    }
    private(set) var lux: Double?
    private(set) var lightError: SensorError?

    // MARK: Slap

    var slapEnabled = true {
        didSet {
            persist(slapEnabled, as: DefaultsKey.slap)
            if !slapEnabled { lastSlapForce = nil }
            syncMotion()
        }
    }
    var sensitivity: Double = 0.5 {
        didSet {
            UserDefaults.standard.set(sensitivity, forKey: DefaultsKey.sensitivity)
            detector.sensitivity = sensitivity
        }
    }
    /// Off by default so nothing makes noise unasked. Haptics still fire.
    var soundEnabled = false {
        didSet {
            persist(soundEnabled, as: DefaultsKey.sound)
            if soundEnabled, let pack = currentPack { board.preview(pack) }
        }
    }
    /// Resolved against what was downloaded, so a pack dropped from the CDN
    /// falls back to one that plays.
    var soundPack: String {
        get {
            packs.contains { $0.id == storedPack } ? storedPack : packs.first?.id ?? storedPack
        }
        set {
            storedPack = newValue
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.soundPack)
            if soundEnabled, let pack = currentPack { board.preview(pack) }
        }
    }
    var packs: [SoundPack] { library.packs }
    var packsLoading: Bool { library.isLoading }
    private(set) var slapCount = 0
    private(set) var lastSlapForce: Double?
    private(set) var motionError: SensorError?
    private(set) var inputMonitoring = InputMonitoring.status

    // MARK: Level

    var levelEnabled = true {
        didSet {
            persist(levelEnabled, as: DefaultsKey.level)
            syncMotion()
        }
    }
    private(set) var tilt: TiltEstimator.Tilt?

    // MARK: Scale

    var scaleEnabled = true {
        didSet {
            persist(scaleEnabled, as: DefaultsKey.scale)
            scaleEnabled ? startScale() : stopScale()
        }
    }
    private(set) var grams: Double = 0
    private(set) var contactCount = 0
    private(set) var scaleError: SensorError?
    /// Subtracted from every reading, so the finger holding contact doesn't count
    /// toward the object's weight. This is a tare like any scale has, not a
    /// calibration. The framework already reports grams.
    private(set) var zeroOffset: Double = 0

    var netGrams: Double { max(0, grams - zeroOffset) }

    /// Every sensor reports far faster than a number is readable, and every raw
    /// value dithers a little even when nothing is happening. All of them are
    /// collected continuously and published together on one slow tick as
    /// medians, which steadies the figures and drops single-sample spikes.
    private var readoutTask: Task<Void, Never>?
    private var angleWindow = MedianWindow()
    private var luxWindow = MedianWindow()
    private var gramsWindow = MedianWindow()
    private var latestContactCount = 0
    private var lastFrameAt: TimeInterval = 0

    private let lid = LidAngleSensor()
    private let light = AmbientLightSensor()
    private let accelerometer = MotionSensor()
    private let trackpad = TrackpadForceSensor()
    private let detector = ImpactDetector()
    private var tiltEstimator = TiltEstimator()
    private var isMotionRunning = false
    private let board = SoundBoard()
    private let library = PackLibrary()
    private var storedPack = ""

    private var currentPack: SoundPack? { packs.first { $0.id == soundPack } }

    private enum DefaultsKey {
        static let lid = "LidEnabled"
        static let slap = "SlapEnabled"
        static let scale = "ScaleEnabled"
        static let light = "LightEnabled"
        static let level = "LevelEnabled"
        static let sound = "SoundEnabled"
        static let soundPack = "SoundPack"
        static let sensitivity = "Sensitivity"
    }

    init() {
        capabilities = Capabilities.probe()

        // Registered rather than read with a nil check, so a fresh install comes
        // up with everything on while a switch the user turned off stays off.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            DefaultsKey.lid: true,
            DefaultsKey.slap: true,
            DefaultsKey.scale: true,
            DefaultsKey.light: true,
            DefaultsKey.level: true,
            DefaultsKey.sensitivity: 0.5,
        ])

        _sensitivity = defaults.double(forKey: DefaultsKey.sensitivity)
        detector.sensitivity = sensitivity

        storedPack = defaults.string(forKey: DefaultsKey.soundPack) ?? ""
        _soundEnabled = defaults.bool(forKey: DefaultsKey.sound)

        _lidEnabled = defaults.bool(forKey: DefaultsKey.lid)
        _slapEnabled = defaults.bool(forKey: DefaultsKey.slap)
        _scaleEnabled = defaults.bool(forKey: DefaultsKey.scale)
        _lightEnabled = defaults.bool(forKey: DefaultsKey.light)
        _levelEnabled = defaults.bool(forKey: DefaultsKey.level)

        // Restored through the backing store on purpose. @Observable rewrites
        // these into computed properties, so a plain assignment here would run
        // the observers and let launch persist, re-open and play a preview
        // clip before anything is set up. Starting is done by hand instead.
        if lidEnabled { startLid() }
        if scaleEnabled { startScale() }
        if lightEnabled { startLight() }
        syncMotion()
        startReadoutLoop()
        library.sync()
    }

    /// Runs for the life of the app. Each publish is a no-op for a sensor that
    /// is switched off, so there is nothing to start and stop alongside them.
    private func startReadoutLoop() {
        readoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Readouts.interval)
                guard let self else { return }
                publishLidAngle()
                publishTilt()
                publishScale()
                publishLight()
            }
        }
    }

    private func persist(_ value: Bool, as key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: Lid

    private func startLid() {
        guard capabilities.lidAngle else { return }
        lidError = nil
        do {
            try lid.start { [weak self] angle in
                self?.angleWindow.append(angle)
            }
            // start() already seeded the angle; don't make it wait a tick.
            publishLidAngle()
        } catch let error as SensorError {
            lidError = error
        } catch {
            lidError = .openFailed(kIOReturnError)
        }
    }

    private func stopLid() {
        lid.stop()
        angleWindow.reset()
        lidAngle = nil
    }

    private func publishLidAngle() {
        guard lidEnabled, let median = angleWindow.drain() else { return }
        lidAngle = median
    }

    private func startLight() {
        guard capabilities.ambientLight else { return }
        lightError = nil
        do {
            try light.start { [weak self] lux in
                self?.luxWindow.append(lux)
            }
        } catch let error as SensorError {
            lightError = error
        } catch {
            lightError = .openFailed(kIOReturnError)
        }
    }

    private func stopLight() {
        light.stop()
        luxWindow.reset()
        lux = nil
    }

    private func publishLight() {
        guard lightEnabled, let median = luxWindow.drain() else { return }
        lux = median
    }

    // MARK: Slap

    /// Slap and the level read the same accelerometer, so the device is opened
    /// once for whichever of them is on and closed only when both are off.
    private func syncMotion() {
        (slapEnabled || levelEnabled) ? startMotion() : stopMotion()
    }

    /// Asks for Input Monitoring before opening the device. On a fresh install
    /// this lands at first launch, because both switches ship on.
    private func startMotion() {
        guard capabilities.motion, !isMotionRunning else { return }
        motionError = nil
        detector.reset()
        tiltEstimator.reset()

        if InputMonitoring.status != .granted {
            InputMonitoring.request()
            inputMonitoring = InputMonitoring.status
        }

        do {
            try accelerometer.start { [weak self] sample in
                guard let self else { return }
                if slapEnabled, let impact = detector.process(sample) { register(impact) }
                if levelEnabled { tiltEstimator.append(sample) }
            }
            isMotionRunning = true
        } catch let error as SensorError {
            failMotion(with: error)
        } catch {
            failMotion(with: .openFailed(kIOReturnError))
        }
    }

    /// The switches stay on. Turning them off here would recurse back through
    /// syncMotion, and it would persist a sensor failure as a preference the
    /// user never set: grant the permission afterwards and both panels would
    /// still come up off. The panels show the error instead.
    private func failMotion(with error: SensorError) {
        motionError = error
    }

    private func publishTilt() {
        guard levelEnabled, let reading = tiltEstimator.drain() else { return }
        tilt = reading
    }

    private func stopMotion() {
        accelerometer.stop()
        isMotionRunning = false
        tiltEstimator.reset()
        tilt = nil
        lastSlapForce = nil
    }

    private func register(_ impact: ImpactDetector.Impact) {
        slapCount += 1
        lastSlapForce = impact.force
        Haptics.tap(.generic)
        if soundEnabled, let pack = currentPack { board.play(pack, force: impact.force) }
    }

    // MARK: Scale

    private func startScale() {
        scaleError = nil
        do {
            try trackpad.start { [weak self] frame in
                guard let self else { return }
                latestContactCount = frame.contactCount
                lastFrameAt = ProcessInfo.processInfo.systemUptime
                gramsWindow.append(frame.grams)
            }
        } catch let error as SensorError {
            scaleError = error
        } catch {
            scaleError = .openFailed(kIOReturnError)
        }
    }

    private func stopScale() {
        trackpad.stop()
        gramsWindow.reset()
        latestContactCount = 0
        grams = 0
        contactCount = 0
        zeroOffset = 0
        lastFrameAt = 0
    }

    private func publishScale() {
        guard scaleEnabled else { return }
        contactCount = latestContactCount

        if let median = gramsWindow.drain() {
            grams = median
            return
        }

        // No frames at all this window. The framework goes quiet once nothing is
        // touching, so after a short grace period treat silence as an empty pad
        // instead of holding the last number on screen indefinitely.
        if ProcessInfo.processInfo.systemUptime - lastFrameAt > 0.4 {
            grams = 0
            contactCount = 0
        }
    }

    func tare() {
        zeroOffset = grams
    }

    /// Called every time the panel opens. Coming back from System Settings with
    /// the box newly ticked should just start working, without making the user
    /// flip the switch off and on again to notice.
    func panelWillOpen() {
        let previous = inputMonitoring
        inputMonitoring = InputMonitoring.status

        if previous != .granted, inputMonitoring == .granted {
            syncMotion()
        }

        library.refresh()
    }
}
