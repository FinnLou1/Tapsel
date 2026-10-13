import AppKit

/// What the pet is currently standing on.
enum PetSupport: Equatable {
    case floor
    case ledge(CGWindowID)
    case wall(WallSide)
    case airborne
}

enum WallSide: Equatable {
    case left
    case right
}

/// The pet's "brain": owns its stats, decides what it's doing, and moves it around
/// the screen - including standing on other apps' windows, jumping between them and
/// climbing the screen edges.
///
/// Knows nothing about views: it reports a pixel frame plus a screen-space anchor
/// (the point where the pet's feet touch its surface); `PetWindowController` applies
/// that to the window.
final class PetEngine {
    private(set) var kind: PetKind
    private(set) var stats: PetStats
    private(set) var behavior: BehaviorState = .idle
    private(set) var facingLeft = false
    private(set) var isDragging = false

    /// Where the pet's feet touch its surface, in screen coordinates.
    private(set) var position: CGPoint
    private(set) var support: PetSupport = .floor

    let windowSize: CGSize

    // MARK: Tuning (distances in points, speeds in points per second)

    /// 60 Hz: fast enough that a pet riding a window you drag stays visually glued
    /// to it. The sprite itself still animates at a chunky ~7.5 fps.
    private let physicsInterval = 1.0 / 60.0
    private let fullScanEveryNFrames = 20
    private let gravity: Double = 1200
    /// Set from `AppSettings.speedMultiplier` at init and whenever the settings
    /// window changes it; walk/climb pace scale with it, everything else (gravity,
    /// jump arcs) stays put so the physics still reads as "the same pet, faster".
    private var speedMultiplier: Double = 1.0
    private var walkSpeed: Double { 42 * speedMultiplier }
    private var climbSpeed: Double { 70 * speedMultiplier }
    private let maxFallSpeed: Double = 1500
    // Cartoon physics on purpose: windows usually sit far above the desktop floor,
    // so a realistic hop would never reach them.
    private let maxJumpRise: CGFloat = 620
    private let maxJumpRun: CGFloat = 520
    private let maxJumpRunSpeed: Double = 340
    /// Roughly half the drawn pet, so it stays fully visible while walking.
    private let bodyHalfWidth: CGFloat = 72

    private var frameListeners: [() -> Void] = []
    private var statsListeners: [() -> Void] = []

    func addFrameListener(_ callback: @escaping () -> Void) { frameListeners.append(callback) }
    func addStatsListener(_ callback: @escaping () -> Void) { statsListeners.append(callback) }

    private var frame = 0
    private var animationTimer: Timer?
    private var simulationTimer: Timer?
    private var eatTicksRemaining = 0
    private var idleTicksRemaining = 0
    private var walkDirection: Double = 1
    private var velocity = CGVector.zero
    private var climbTargetY: CGFloat = 0
    private var lastPersist = Date.distantPast

    private var surfaces = WindowSurfaces(ledges: [])
    /// Last known frame of the window we're riding, to follow it when it's moved.
    private var supportRect: CGRect?
    private var lastSupportMoveFrame = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var frameCache: (key: FrameKey, canvas: PixelCanvas)?

    private struct FrameKey: Equatable {
        let kind: PetKind
        let behavior: BehaviorState
        let mood: MoodLevel
        let tick: Int
        let facingLeft: Bool
        let orientation: PetOrientation
    }

    var hungerPercent: Int { Int(stats.hunger.rounded()) }
    var happinessPercent: Int { Int(stats.happiness.rounded()) }
    var energyPercent: Int { Int(stats.energy.rounded()) }
    var currentMood: MoodLevel { MoodLevel.from(hunger: stats.hunger, happiness: stats.happiness) }

    /// Animation runs far slower than physics, to keep the chunky retro feel
    /// while movement itself stays smooth.
    private var spriteTick: Int { frame / 8 }

    /// True when the pet's window must be repositioned on every physics frame:
    /// riding a window the user may be dragging, or flying through the air. While
    /// it just pootles along the floor, half that rate looks identical and moving
    /// a window is by far the most expensive thing this app does.
    var needsPreciseTracking: Bool {
        switch support {
        case .ledge, .airborne: return true
        case .floor, .wall: return false
        }
    }

    var orientation: PetOrientation {
        switch support {
        case .wall(.left): return .wallLeft
        case .wall(.right): return .wallRight
        default: return .upright
        }
    }

    /// Short human-readable state for the menu header, e.g. "Schläft".
    var statusDescription: String {
        switch behavior {
        case .sleeping: return "Schläft"
        case .eating: return "Frisst gerade"
        case .held: return "Wird getragen"
        case .falling: return "Im freien Fall"
        case .climbing: return "Klettert"
        case .idle, .walk:
            let place: String
            switch support {
            case .ledge: place = " auf einem Fenster"
            default: place = ""
            }
            switch currentMood {
            case .hungry: return "Hat Hunger" + place
            case .happy: return "Bester Laune" + place
            case .neutral: return "Zufrieden" + place
            case .sad: return "Schlecht gelaunt" + place
            }
        }
    }

    /// Test hook for the `--trace` dev flag: put the pet straight onto a window edge.
    /// Pass a window id to target one specific window.
    @discardableResult
    func debugStandOnLedge(windowID: CGWindowID? = nil) -> Bool {
        rescanSurfaces()
        let ledge: Ledge?
        if let windowID {
            ledge = surfaces.ledge(windowID)
        } else {
            ledge = surfaces.ledges.first { surfaces.canStand($0, at: $0.rect.midX) }
        }
        guard let ledge else { return false }
        position.x = ledge.rect.midX
        land(at: ledge.topY, on: .ledge(ledge.windowID))
        return true
    }

    /// Test hook for the `--trace` dev flag: start the pet walking from a given spot.
    func debugPlace(x: CGFloat, walkingLeft: Bool) {
        position.x = x
        support = .floor
        behavior = .walk
        walkDirection = walkingLeft ? -1 : 1
        facingLeft = walkingLeft
    }

    /// One-line state summary, used by the `--trace` dev flag.
    var debugSummary: String {
        let place: String
        switch support {
        case .floor: place = "Boden"
        case .ledge(let id): place = "Fenster #\(id)"
        case .wall(.left): place = "Wand links"
        case .wall(.right): place = "Wand rechts"
        case .airborne: place = "Luft"
        }
        let x = String(format: "%5.0f", position.x)
        let y = String(format: "%5.0f", position.y)
        var line = "x=\(x) y=\(y)  \(behavior)".padding(toLength: 34, withPad: " ", startingAt: 0)
            + place.padding(toLength: 16, withPad: " ", startingAt: 0)
        if let rect = supportRect {
            line += String(format: "fenster(x=%.0f oben=%.0f)", rect.minX, rect.maxY)
        } else {
            line += "\(surfaces.ledges.count) Fensterkanten"
        }
        return line
    }

    init(settings: AppSettings = AppSettings()) {
        let save = PetSaveData.load()
        kind = save.kind
        var loadedStats = save.stats
        let elapsed = Date().timeIntervalSince(loadedStats.lastUpdate)
        loadedStats.applyDecay(elapsedSeconds: elapsed, isSleeping: false)
        loadedStats.lastUpdate = Date()
        stats = loadedStats

        let side = max(SpriteBuilder.width, SpriteBuilder.height) * PetView.pixelScale
        windowSize = CGSize(width: CGFloat(side), height: CGFloat(side))

        speedMultiplier = min(max(settings.speedMultiplier, 0.4), 2.5)

        let screen = Self.resolveScreen(preferredID: settings.preferredScreenID)
        position = CGPoint(x: screen.midX, y: screen.minY)
    }

    private static func resolveScreen(preferredID: String?) -> CGRect {
        if let preferredID, let match = NSScreen.screens.first(where: { $0.stableID == preferredID }) {
            return match.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Applied live from the settings window - no restart needed.
    func setSpeedMultiplier(_ multiplier: Double) {
        speedMultiplier = min(max(multiplier, 0.4), 2.5)
    }

    func start() {
        let physics = Timer(timeInterval: physicsInterval, repeats: true) { [weak self] _ in self?.physicsTick() }
        let simulation = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.simulationTick() }
        RunLoop.main.add(physics, forMode: .common)
        RunLoop.main.add(simulation, forMode: .common)
        animationTimer = physics
        simulationTimer = simulation
        rescanSurfaces()
    }

    func stop() {
        animationTimer?.invalidate()
        simulationTimer?.invalidate()
    }

    // MARK: - Rendering

    /// Bumped only when the drawn pixels actually change, so the view can skip
    /// redraws while the pet just stands there.
    private(set) var frameRevision = 0

    func currentFrame() -> PixelCanvas {
        let key = FrameKey(
            kind: kind, behavior: behavior, mood: currentMood,
            tick: spriteTick, facingLeft: facingLeft, orientation: orientation
        )
        if let cached = frameCache, cached.key == key { return cached.canvas }

        var canvas = SpriteBuilder.buildFrame(kind: kind, behavior: behavior, mood: currentMood, tick: spriteTick)
        if facingLeft { canvas = canvas.mirrored() }
        switch orientation {
        case .upright: break
        case .wallLeft: canvas = canvas.rotated(clockwise: true)
        case .wallRight: canvas = canvas.rotated(clockwise: false)
        }

        if frameCache?.canvas != canvas { frameRevision += 1 }
        frameCache = (key, canvas)
        return canvas
    }

    /// Bottom-left corner of the pet's window for the current anchor + orientation.
    var windowOrigin: CGPoint {
        let padding = CGFloat(SpriteBuilder.bottomPadding * PetView.pixelScale)
        switch orientation {
        case .upright:
            return CGPoint(x: position.x - windowSize.width / 2, y: position.y - padding)
        case .wallLeft:
            return CGPoint(x: position.x - padding, y: position.y - windowSize.height / 2)
        case .wallRight:
            return CGPoint(x: position.x + padding - windowSize.width, y: position.y - windowSize.height / 2)
        }
    }

    private func anchor(forWindowOrigin origin: CGPoint) -> CGPoint {
        let padding = CGFloat(SpriteBuilder.bottomPadding * PetView.pixelScale)
        return CGPoint(x: origin.x + windowSize.width / 2, y: origin.y + padding)
    }

    // MARK: - User actions

    func feed() {
        stats.feed()
        if isGrounded {
            behavior = .eating
            eatTicksRemaining = 3 // simulationTick fires every 2s -> ~6s of munching
        }
        persist(force: true)
        statsListeners.forEach { $0() }
    }

    func pet() {
        stats.pet()
        persist(force: true)
        statsListeners.forEach { $0() }
    }

    func changeKind(_ newKind: PetKind) {
        kind = newKind
        persist(force: true)
        statsListeners.forEach { $0() }
    }

    func beginDrag() {
        isDragging = true
        behavior = .held
        support = .airborne
        supportRect = nil
        velocity = .zero
    }

    func dragTo(windowOrigin origin: CGPoint) {
        position = anchor(forWindowOrigin: origin)
    }

    /// Dropping the pet lets it fall to whatever is below - window, or the floor.
    func endDrag(windowOrigin origin: CGPoint) {
        isDragging = false
        position = anchor(forWindowOrigin: origin)
        startFalling()
    }

    // MARK: - Physics

    private var isGrounded: Bool {
        switch support {
        case .floor, .ledge: return true
        case .wall, .airborne: return false
        }
    }

    private var currentScreen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(position) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var floorY: CGFloat { currentScreen.visibleFrame.minY }

    private func physicsTick() {
        frame += 1
        if frame % fullScanEveryNFrames == 0 { rescanSurfaces() }

        if !isDragging {
            followSupportWindow()
            switch behavior {
            case .walk: stepWalk()
            case .falling: stepFall()
            case .climbing: stepClimb()
            case .idle, .eating, .sleeping, .held: break
            }
        }

        _ = currentFrame() // refresh the cache so frameRevision is up to date
        frameListeners.forEach { $0() }
    }

    private func stepWalk() {
        position.x += walkDirection * walkSpeed * physicsInterval

        switch support {
        case .floor:
            let visible = currentScreen.visibleFrame
            if position.x <= visible.minX + bodyHalfWidth {
                position.x = visible.minX + bodyHalfWidth
                reachedScreenEdge(.left)
            } else if position.x >= visible.maxX - bodyHalfWidth {
                position.x = visible.maxX - bodyHalfWidth
                reachedScreenEdge(.right)
            }

        case .ledge(let id):
            guard let ledge = surfaces.ledge(id) else { return startFalling() }
            if !surfaces.canStand(ledge, at: position.x) {
                // At the end of the window: usually turn around, sometimes step off.
                if Double.random(in: 0...1) < 0.6 {
                    position.x = min(max(position.x, ledge.minX + WindowSurfaces.edgeMargin),
                                     ledge.maxX - WindowSurfaces.edgeMargin)
                    turnAround()
                } else {
                    startFalling(velocity: CGVector(dx: walkDirection * walkSpeed, dy: 0))
                }
            }

        case .wall, .airborne:
            break
        }
    }

    private func stepFall() {
        velocity.dy = max(velocity.dy - gravity * physicsInterval, -maxFallSpeed)

        let previousY = position.y
        position.x += velocity.dx * physicsInterval
        position.y += velocity.dy * physicsInterval

        let visible = currentScreen.visibleFrame
        position.x = min(max(position.x, visible.minX), visible.maxX)

        guard velocity.dy < 0 else { return } // still rising: pass ledges by

        if let landing = surfaces.landing(fallingFrom: previousY, to: position.y, at: position.x, floorY: floorY) {
            land(at: landing.y, on: landing.support)
        } else if position.y <= floorY {
            land(at: floorY, on: .floor)
        }
    }

    private func stepClimb() {
        guard case .wall(let side) = support else { return startFalling() }

        position.y += climbSpeed * physicsInterval

        // Step off the wall onto a window edge we're level with.
        if let target = surfaces.ledgeFromWall(side: side, wallX: position.x, atHeight: position.y, reach: 90) {
            position.x = target.x
            land(at: target.ledge.topY, on: .ledge(target.ledge.windowID))
            return
        }

        if position.y >= climbTargetY || position.y >= currentScreen.visibleFrame.maxY - 30 {
            // Let go and drop back down, pushing off the wall so it can land on a window.
            let push: Double = (side == .left) ? 130 : -130
            startFalling(velocity: CGVector(dx: push, dy: 0))
        }
    }

    private func reachedScreenEdge(_ side: WallSide) {
        // Sometimes climb the edge like a proper desktop pet, otherwise turn around.
        guard Double.random(in: 0...1) < 0.5 else { return turnAround() }

        let visible = currentScreen.visibleFrame
        // Grab the edge itself: while climbing, the feet touch the screen border.
        position.x = (side == .left) ? visible.minX : visible.maxX
        support = .wall(side)
        behavior = .climbing
        // Rotating the sprite maps its "left" to "up" on the left wall, and its
        // "right" to "up" on the right wall - so this makes it face upwards.
        facingLeft = side == .left
        climbTargetY = position.y + CGFloat.random(in: 200...750)
    }

    private func turnAround() {
        walkDirection *= -1
        facingLeft = walkDirection < 0
    }

    private func startFalling(velocity initial: CGVector = .zero) {
        velocity = initial
        support = .airborne
        supportRect = nil
        behavior = .falling
    }

    private func land(at y: CGFloat, on newSupport: PetSupport) {
        position.y = y
        support = newSupport
        velocity = .zero
        behavior = .idle
        idleTicksRemaining = Int.random(in: 0...2)
        supportRect = nil
        if case .ledge(let id) = newSupport {
            supportRect = surfaces.ledge(id)?.rect
        }
    }

    private func jump(to target: CGPoint) {
        let rise = max(target.y - position.y, 30) + 50 // clear the edge before landing
        let riseSpeed = (2 * gravity * Double(rise)).squareRoot()
        let flightTime = (riseSpeed / gravity) * 1.35
        let horizontal = min(max(Double(target.x - position.x) / flightTime, -maxJumpRunSpeed), maxJumpRunSpeed)

        facingLeft = target.x < position.x
        walkDirection = facingLeft ? -1 : 1
        startFalling(velocity: CGVector(dx: horizontal, dy: riseSpeed))
    }

    /// Every frame: stay glued to the window we're standing on. A targeted lookup of
    /// that one window is cheap enough to run at 60 Hz, so dragging a window carries
    /// the pet along smoothly instead of in visible jumps.
    private func followSupportWindow() {
        guard case .ledge(let id) = support else { return }

        // Asking the window server for a window's frame is by far the most expensive
        // thing this app does per frame (it's an XPC round trip). So poll at 20 Hz
        // while the window sits still, and switch to every single frame as soon as it
        // starts moving - i.e. exactly while the user is dragging it around.
        let movingRightNow = frame - lastSupportMoveFrame < 60
        guard movingRightNow || frame % 3 == 0 else { return }

        guard let rect = WindowScanner.frame(of: id) else { return startFalling() }

        if let previous = supportRect {
            if rect != previous { lastSupportMoveFrame = frame }
            // Moved or resized from the left: shift the pet by the same amount.
            position.x += rect.minX - previous.minX
        }
        supportRect = rect
        position.y = rect.maxY

        // Resized out from under the pet?
        let margin = WindowSurfaces.edgeMargin
        if position.x < rect.minX + margin || position.x > rect.maxX - margin {
            startFalling()
        }
    }

    /// Every ~third of a second: re-read the whole window list. This is what finds
    /// new ledges, and it owns the occlusion check (which needs all windows).
    private func rescanSurfaces() {
        surfaces = WindowScanner.scan(excluding: ownPID)

        guard case .ledge(let id) = support, !isDragging else { return }
        guard let ledge = surfaces.ledge(id) else { return startFalling() }
        if !surfaces.canStand(ledge, at: position.x) { startFalling() }
    }

    // MARK: - Decisions

    private func simulationTick() {
        stats.applyDecay(elapsedSeconds: 2.0, isSleeping: behavior == .sleeping)
        stats.lastUpdate = Date()

        if !isDragging, isGrounded {
            if behavior == .eating {
                eatTicksRemaining -= 1
                if eatTicksRemaining <= 0 { behavior = .idle }
            } else if stats.energy < 12 {
                behavior = .sleeping
            } else if behavior == .sleeping {
                if stats.energy > 55 { behavior = .idle }
            } else {
                decideNextBehavior()
            }
        }

        persist()
        statsListeners.forEach { $0() }
    }

    private func decideNextBehavior() {
        if idleTicksRemaining > 0 {
            idleTicksRemaining -= 1
            return
        }

        // Every so often, hop up onto a window that's within reach.
        if Double.random(in: 0...1) < 0.25 {
            let targets = surfaces.jumpTargets(from: position, maxUp: maxJumpRise, maxSide: maxJumpRun)
            if let target = targets.randomElement() {
                jump(to: target)
                return
            }
        }

        if behavior == .walk {
            let roll = Double.random(in: 0...1)
            if roll < 0.4 {
                behavior = .idle
                idleTicksRemaining = Int.random(in: 1...3)
            } else if roll < 0.55 {
                turnAround()
            }
        } else {
            if Double.random(in: 0...1) < 0.6 {
                behavior = .walk
                walkDirection = Bool.random() ? 1 : -1
                facingLeft = walkDirection < 0
            } else {
                idleTicksRemaining = Int.random(in: 1...2)
            }
        }
    }

    private func persist(force: Bool = false) {
        if !force {
            guard Date().timeIntervalSince(lastPersist) > 15 else { return }
        }
        lastPersist = Date()
        PetSaveData(kind: kind, stats: stats).save()
    }
}
