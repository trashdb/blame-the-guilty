import Foundation
import AppKit
import SwiftUI

struct IDEDefinition: Identifiable, Equatable {
    let id: String
    let displayName: String
    let icon: String
    let appName: String
    let launch: IDELaunch

    static func == (lhs: IDEDefinition, rhs: IDEDefinition) -> Bool { lhs.id == rhs.id }

    private static var installCache: [String: String?] = [:]

    var installedPath: String? {
        if let cached = Self.installCache[id] { return cached }
        let result = Self.locate(id: id, launch: launch, displayName: displayName)
        Self.installCache[id] = result
        return result
    }

    var isInstalled: Bool { installedPath != nil }

    private static let appForCLI: [String: String] = [
        "vscode": "Visual Studio Code",
        "cursor": "Cursor",
        "windsurf": "WindSurf",
        "codium": "VS Codium",
        "sublime": "Sublime Text",
        "zed": "Zed",
        "emacs": "Emacs",
        "textmate": "TextMate",
    ]

    private static func locate(id: String, launch: IDELaunch, displayName: String) -> String? {
        switch launch {
        case .openApp(let name):
            let candidates = ["/Applications/\(name).app", "\(NSHomeDirectory())/Applications/\(name).app",
                              "/Applications/\(name.replacingOccurrences(of: " ", with: "")).app",
                              "\(NSHomeDirectory())/Applications/\(name.replacingOccurrences(of: " ", with: "")).app"]
            for p in candidates {
                if FileManager.default.fileExists(atPath: p) { return p }
            }
            if let bundleID = launch.bundleIdentifier {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    return url.path
                }
            }
            return nil
        case .jetbrains:
            let appName = displayName
            let candidates = ["/Applications/\(appName).app", "\(NSHomeDirectory())/Applications/\(appName).app",
                              "/Applications/\(appName.replacingOccurrences(of: " ", with: "")).app",
                              "\(NSHomeDirectory())/Applications/\(appName.replacingOccurrences(of: " ", with: "")).app"]
            for p in candidates {
                if FileManager.default.fileExists(atPath: p) { return p }
            }
            if let bundleID = launch.bundleIdentifier {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    return url.path
                }
            }
            return nil
        case .cli(let path, _):
            // App bundle first (gives real icon)
            if let appName = appForCLI[id] {
                let appCandidates = ["/Applications/\(appName).app", "\(NSHomeDirectory())/Applications/\(appName).app"]
                for p in appCandidates {
                    if FileManager.default.fileExists(atPath: p) { return p }
                }
            }
            // CLI binary paths
            let cliPaths = ["/usr/local/bin/\(path)", "/opt/homebrew/bin/\(path)",
                            "\(NSHomeDirectory())/.local/bin/\(path)"]
            for p in cliPaths {
                if FileManager.default.fileExists(atPath: p) { return p }
            }
            // Fallback `which` — exclude system paths (/usr/bin)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = [path]
            let out = Pipe()
            task.standardOutput = out
            try? task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if str.hasPrefix("/usr/bin/") { return nil }
            return str.isEmpty ? nil : str
        case .custom:
            return "custom"
        }
    }
}

extension IDELaunch {
    fileprivate func appName(displayName: String) -> String? {
        switch self {
        case .openApp(let name): return name
        case .jetbrains: return displayName
        default: return nil
        }
    }

    fileprivate var bundleIdentifier: String? {
        switch self {
        case .jetbrains(let product):
            let map: [String: String] = [
                "rider": "com.jetbrains.rider",
                "idea": "com.jetbrains.intellij",
                "pycharm": "com.jetbrains.pycharm",
                "webstorm": "com.jetbrains.webstorm",
                "goland": "com.jetbrains.goland",
                "rubymine": "com.jetbrains.rubymine",
                "phpstorm": "com.jetbrains.phpstorm",
                "clion": "com.jetbrains.clion",
                "datagrip": "com.jetbrains.datagrip",
                "fleet": "com.jetbrains.fleet",
            ]
            return map[product]
        default: return nil
        }
    }
}

let installedIDEs: [IDEDefinition] = {
    let custom = IDEDefinition(id: "custom", displayName: "Custom…", icon: "gearshape.fill", appName: "", launch: .custom)
    return builtInIDEs.filter { $0.isInstalled } + [custom]
}()

extension IDEDefinition {
    func viewIcon(size: CGFloat = 14) -> Image {
        if let path = installedPath, path != "custom" {
            let ns = NSWorkspace.shared.icon(forFile: path)
            ns.size = NSSize(width: size, height: size)
            return Image(nsImage: ns)
        }
        return Image(systemName: icon)
    }
}

enum IDELaunch {
    case jetbrains(product: String)
    case cli(path: String, supportsGoto: Bool)
    case openApp(String)
    case custom
}

let builtInIDEs: [IDEDefinition] = [
    .init(id: "rider",         displayName: "Rider",          icon: "hammer.fill",                        appName: "Rider",          launch: .jetbrains(product: "rider")),
    .init(id: "vscode",        displayName: "VS Code",        icon: "chevron.left.forwardslash.chevron.right", appName: "VS Code",    launch: .cli(path: "code", supportsGoto: true)),
    .init(id: "cursor",        displayName: "Cursor",         icon: "cursorarrow.click.2",                appName: "Cursor",         launch: .cli(path: "cursor", supportsGoto: true)),
    .init(id: "windsurf",      displayName: "WindSurf",       icon: "wind",                                appName: "WindSurf",       launch: .cli(path: "windsurf", supportsGoto: true)),
    .init(id: "codium",        displayName: "VS Codium",      icon: "chevron.left.forwardslash.chevron.right", appName: "VS Codium",  launch: .cli(path: "codium", supportsGoto: true)),
    .init(id: "visualstudio",  displayName: "Visual Studio",  icon: "building.2.fill",                    appName: "Visual Studio",  launch: .openApp("Visual Studio")),
    .init(id: "intellij",      displayName: "IntelliJ IDEA",  icon: "brain.head.profile",                 appName: "IntelliJ IDEA",  launch: .jetbrains(product: "idea")),
    .init(id: "pycharm",       displayName: "PyCharm",        icon: "pyramid.fill",                       appName: "PyCharm",        launch: .jetbrains(product: "pycharm")),
    .init(id: "webstorm",      displayName: "WebStorm",       icon: "globe",                               appName: "WebStorm",       launch: .jetbrains(product: "webstorm")),
    .init(id: "goland",        displayName: "GoLand",         icon: "g.circle.fill",                      appName: "GoLand",         launch: .jetbrains(product: "goland")),
    .init(id: "rubymine",      displayName: "RubyMine",       icon: "r.circle.fill",                      appName: "RubyMine",       launch: .jetbrains(product: "rubymine")),
    .init(id: "phpstorm",      displayName: "PhpStorm",       icon: "p.circle.fill",                      appName: "PhpStorm",       launch: .jetbrains(product: "phpstorm")),
    .init(id: "clion",         displayName: "CLion",          icon: "c.circle.fill",                      appName: "CLion",          launch: .jetbrains(product: "clion")),
    .init(id: "datagrip",      displayName: "DataGrip",       icon: "d.circle.fill",                      appName: "DataGrip",       launch: .jetbrains(product: "datagrip")),
    .init(id: "fleet",         displayName: "Fleet",          icon: "sailboat.fill",                      appName: "Fleet",          launch: .jetbrains(product: "fleet")),
    .init(id: "androidstudio", displayName: "Android Studio", icon: "gearshape.2.fill",                   appName: "Android Studio", launch: .openApp("Android Studio")),
    .init(id: "eclipse",       displayName: "Eclipse",        icon: "square.3.layers.3d",                 appName: "Eclipse",        launch: .openApp("Eclipse")),
    .init(id: "xcode",         displayName: "Xcode",          icon: "hammer.fill",                        appName: "Xcode",          launch: .openApp("Xcode")),
    .init(id: "sublime",       displayName: "Sublime Text",   icon: "text.bubble.fill",                   appName: "Sublime Text",   launch: .cli(path: "subl", supportsGoto: true)),
    .init(id: "zed",           displayName: "Zed",            icon: "bolt.fill",                          appName: "Zed",            launch: .cli(path: "zed", supportsGoto: false)),
    .init(id: "nova",          displayName: "Nova",           icon: "sparkle",                            appName: "Nova",           launch: .openApp("Nova")),
    .init(id: "vim",           displayName: "Vim",            icon: "terminal.fill",                      appName: "Vim",            launch: .cli(path: "vim", supportsGoto: false)),
    .init(id: "neovim",        displayName: "NeoVim",         icon: "terminal.fill",                      appName: "NeoVim",         launch: .cli(path: "nvim", supportsGoto: false)),
    .init(id: "emacs",         displayName: "Emacs",          icon: "textformat.alt",                     appName: "Emacs",          launch: .cli(path: "emacs", supportsGoto: false)),
    .init(id: "helix",         displayName: "Helix",          icon: "terminal.fill",                      appName: "Helix",          launch: .cli(path: "hx", supportsGoto: false)),
    .init(id: "textmate",      displayName: "TextMate",       icon: "doc.text.fill",                      appName: "TextMate",       launch: .openApp("TextMate")),
    .init(id: "coderunner",    displayName: "CodeRunner",     icon: "play.fill",                          appName: "CodeRunner",     launch: .openApp("CodeRunner")),
]

func ideDefinition(for id: String) -> IDEDefinition {
    if let ide = builtInIDEs.first(where: { $0.id == id }) {
        return ide
    }
    return .init(id: "custom", displayName: "Custom…", icon: "gearshape.fill", appName: "", launch: .custom)
}

func migrateOldIDEKey() {
    let key = "defaultIDE"
    let old = UserDefaults.standard.string(forKey: key) ?? ""
    let oldToNew: [String: String] = [
        "Rider": "rider",
        "VS Code": "vscode",
        "Custom": "custom",
    ]
    if let new = oldToNew[old] {
        UserDefaults.standard.set(new, forKey: key)
    }
}

enum IDEOpener {
    private static func resolveExec(for def: IDEDefinition) -> (url: URL, isApp: Bool) {
        if let installed = def.installedPath {
            if installed.hasSuffix(".app") {
                return (URL(fileURLWithPath: "/usr/bin/open"), true)
            }
            return (URL(fileURLWithPath: installed), false)
        }
        if case .cli(let cliPath, _) = def.launch {
            return (URL(fileURLWithPath: "/usr/local/bin/\(cliPath)"), false)
        }
        return (URL(fileURLWithPath: "/usr/bin/open"), true)
    }

    static func openFile(filePath: String, line: Int? = nil) {
        migrateOldIDEKey()
        let raw = UserDefaults.standard.string(forKey: "defaultIDE") ?? "rider"
        let def = ideDefinition(for: raw)
        let exec = resolveExec(for: def)

        switch def.launch {
        case .jetbrains(let product):
            var urlStr = "jetbrains://\(product)/navigate/reference?file=\(filePath)"
            if let line { urlStr += "&line=\(line)" }
            urlStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlStr
            if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }

        case .cli(_, let supportsGoto):
            let task = Process()
            task.executableURL = exec.url
            if exec.isApp {
                var args = ["-a", def.appName, filePath]
                if let line { args += ["--line", "\(line)"] }
                task.arguments = args
            } else {
                if supportsGoto, let line {
                    task.arguments = ["--goto", "\(filePath):\(line)"]
                } else {
                    task.arguments = [filePath]
                }
            }
            try? task.run()

        case .openApp(let app):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var args = ["-a", app, filePath]
            if let line { args += ["--line", "\(line)"] }
            task.arguments = args
            try? task.run()

        case .custom:
            let template = UserDefaults.standard.string(forKey: "customIDECommand") ?? ""
            var cmd = template.replacingOccurrences(of: "{file}", with: filePath)
            if let line {
                cmd = cmd.replacingOccurrences(of: "{line}", with: "\(line)")
            }
            guard let url = URL(string: cmd) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    static func openRepo(repoPath: String) {
        migrateOldIDEKey()
        let raw = UserDefaults.standard.string(forKey: "defaultIDE") ?? "rider"
        let def = ideDefinition(for: raw)
        let exec = resolveExec(for: def)

        switch def.launch {
        case .jetbrains:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", def.appName, repoPath]
            try? task.run()

        case .openApp(let app):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", app, repoPath]
            try? task.run()

        case .cli:
            let task = Process()
            task.executableURL = exec.url
            if exec.isApp {
                task.arguments = ["-a", def.appName, repoPath]
            } else {
                task.arguments = [repoPath]
            }
            try? task.run()

        case .custom:
            let template = UserDefaults.standard.string(forKey: "customIDECommand") ?? ""
            let cmd = template.replacingOccurrences(of: "{file}", with: repoPath)
            guard let url = URL(string: cmd) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    static func openSolution(repoPath: String, solutionFinder: (String) -> String?) {
        migrateOldIDEKey()
        let raw = UserDefaults.standard.string(forKey: "defaultIDE") ?? "rider"
        let def = ideDefinition(for: raw)
        let target = solutionFinder(repoPath) ?? repoPath
        let exec = resolveExec(for: def)

        switch def.launch {
        case .jetbrains:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", def.appName, target]
            try? task.run()

        case .openApp(let app):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", app, target]
            try? task.run()

        case .cli:
            let task = Process()
            task.executableURL = exec.url
            // CLI editors open the folder, not a solution file
            task.arguments = exec.isApp ? ["-a", def.appName, repoPath] : [repoPath]
            try? task.run()

        case .custom:
            let template = UserDefaults.standard.string(forKey: "customIDECommand") ?? ""
            let cmd = template.replacingOccurrences(of: "{file}", with: target)
            guard let url = URL(string: cmd) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
