import AppKit

if let flagIndex = CommandLine.arguments.firstIndex(of: "--export-icon"),
   CommandLine.arguments.count > flagIndex + 1 {
    let path = CommandLine.arguments[flagIndex + 1]
    let extra = CommandLine.arguments[(flagIndex + 2)...]
    let kind = extra.first.flatMap { PetKind(rawValue: $0) } ?? .cat
    let mood: MoodLevel
    switch extra.dropFirst().first {
    case "happy": mood = .happy
    case "sad": mood = .sad
    case "hungry": mood = .hungry
    case "neutral": mood = .neutral
    default: mood = .happy
    }
    IconExporter.export(to: path, kind: kind, mood: mood)
    exit(0)
}

if let flagIndex = CommandLine.arguments.firstIndex(of: "--print-ascii") {
    let extra = CommandLine.arguments[(flagIndex + 1)...]
    let kind = extra.first.flatMap { PetKind(rawValue: $0) } ?? .cat
    let canvas = SpriteBuilder.buildFrame(kind: kind, behavior: .idle, mood: .neutral, tick: 0)
    for y in 0..<canvas.height {
        var line = ""
        for x in 0..<canvas.width {
            let v = canvas.get(x, y)
            line += v < 0 ? "." : String(v)
        }
        print(line)
    }
    exit(0)
}

if let flagIndex = CommandLine.arguments.firstIndex(of: "--trace") {
    let seconds = Double(CommandLine.arguments[(flagIndex + 1)...].first ?? "") ?? 20
    _ = NSApplication.shared

    let engine = PetEngine()
    engine.start()
    let extra = CommandLine.arguments[(flagIndex + 2)...].first
    if extra == "ledge" || extra?.hasPrefix("win:") == true {
        let id = extra?.hasPrefix("win:") == true ? CGWindowID(extra!.dropFirst(4)) : nil
        let ok = engine.debugStandOnLedge(windowID: id)
        print(ok ? "-> auf Fensterkante gesetzt" : "-> keine Fensterkante gefunden")
    } else if let startX = extra.flatMap(Double.init) {
        engine.debugPlace(x: CGFloat(startX), walkingLeft: true)
    }

    var lastPrint = Date.distantPast
    engine.addFrameListener {
        guard Date().timeIntervalSince(lastPrint) > 0.4 else { return }
        lastPrint = Date()
        print(engine.debugSummary)
    }

    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    exit(0)
}

if CommandLine.arguments.contains("--dump-menu") {
    _ = NSApplication.shared
    let builder = PetMenuBuilder(engine: PetEngine(), settingsStore: SettingsStore())

    func dump(_ menu: NSMenu, indent: String) {
        for item in menu.items {
            if item.isSeparatorItem {
                print(indent + "──────────")
                continue
            }
            let key = item.keyEquivalent.isEmpty ? "" : "   ⌘\(item.keyEquivalent.uppercased())"
            let check = item.state == .on ? " ✓" : ""
            let icon = item.image == nil ? "" : " [icon]"
            let dimmed = item.isEnabled ? "" : " (info)"
            print(indent + item.title.replacingOccurrences(of: "\t", with: "   ") + key + check + icon + dimmed)
            if let submenu = item.submenu {
                dump(submenu, indent: indent + "    ")
            }
        }
    }

    dump(builder.makeMenu(), indent: "")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
