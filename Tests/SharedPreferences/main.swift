import AppKit
import Foundation
import OpenInTerminalCore

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition() {
        fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
        exit(1)
    }
}

func cleanCurrentDomain() {
    if let domain = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: \(args[0]) <mode>\n", stderr)
    exit(2)
}

let mode = args[1]

switch mode {
case "clean":
    cleanCurrentDomain()
    print("OK: cleaned domain \(Bundle.main.bundleIdentifier ?? "nil")")

case "migrate-and-write":
    cleanCurrentDomain()

    // 1. Start host sync: should migrate once from OIT_LEGACY_PREFERENCES_PATH
    SharedPreferences.startHost()
    DefaultsManager.shared.firstSetup()
    SharedPreferences.publish()

    check(DefaultsManager.shared.defaultTerminal?.name == "Ghostty",
          "Expected migrated defaultTerminal == Ghostty, got \(String(describing: DefaultsManager.shared.defaultTerminal?.name))")
    check(DefaultsManager.shared.defaultEditor?.name == "Visual Studio Code",
          "Expected migrated defaultEditor == Visual Studio Code, got \(String(describing: DefaultsManager.shared.defaultEditor?.name))")
    check(DefaultsManager.shared.isContextMenuUseSubmenu == true,
          "Expected migrated isContextMenuUseSubmenu == true")

    guard let sharedURL = SharedPreferences.sharedSettingsURL else {
        fputs("FAIL: sharedSettingsURL is nil\n", stderr)
        exit(1)
    }
    check(FileManager.default.fileExists(atPath: sharedURL.path),
          "Expected shared-settings.plist to exist at \(sharedURL.path)")
    if let perms = (try? FileManager.default.attributesOfItem(atPath: sharedURL.path))?[.posixPermissions] as? NSNumber {
        check(perms.intValue & 0o777 == 0o600,
              "Expected 0600 permissions on shared-settings.plist, got \(String(perms.intValue, radix: 8))")
    }

    // 2. Update preferences in host app and ensure they persist + publish
    DefaultsManager.shared.defaultTerminal = SupportedApps.otty.app
    DefaultsManager.shared.defaultEditor = SupportedApps.zed.app
    DefaultsManager.shared.setNewOption(.terminal, .tab)
    DefaultsManager.shared.isCustomMenuApplyToToolbar = true
    DefaultsManager.shared.customMenuIconOption = .original
    DefaultsManager.shared.customMenuOptions = [SupportedApps.ghostty.app, SupportedApps.vscode.app]
    SharedPreferences.publish()
    UserDefaults.standard.synchronize()
    print("OK: migrate-and-write")

case "host-relaunch-verify":
    // Legacy plist has been deleted by the runner script before this step;
    // values must come from native UserDefaults.standard persistence.
    SharedPreferences.startHost()

    check(DefaultsManager.shared.defaultTerminal?.name == "Otty",
          "Expected persisted defaultTerminal == Otty after relaunch, got \(String(describing: DefaultsManager.shared.defaultTerminal?.name))")
    check(DefaultsManager.shared.defaultTerminal?.bundleId == "io.appmakes.otty",
          "Expected Otty bundleId == io.appmakes.otty")
    check(DefaultsManager.shared.defaultEditor?.name == "Zed",
          "Expected persisted defaultEditor == Zed after relaunch")
    check(DefaultsManager.shared.getNewOption(.terminal) == .tab,
          "Expected persisted TerminalNewOption == .tab")
    check(DefaultsManager.shared.isCustomMenuApplyToToolbar == true,
          "Expected persisted isCustomMenuApplyToToolbar == true")
    check(DefaultsManager.shared.customMenuOptions?.map(\.name) == ["Ghostty", "Visual Studio Code"],
          "Expected persisted customMenuOptions == [Ghostty, Visual Studio Code]")

    // Verify Warp single-window URI builder (#230)
    let warpURL = SupportedApps.warpURI(forPath: "/Volumes/Work SSD/My Project", newTab: false)
    check(warpURL?.absoluteString == "warp://action/new_window?path=/Volumes/Work%20SSD/My%20Project",
          "Unexpected Warp URI: \(String(describing: warpURL?.absoluteString))")

    // Verify alternate bundle IDs for Community Editions
    check(SupportedApps.intelliJIDEA.allBundleIds.contains("com.jetbrains.intellij.ce"),
          "Expected IntelliJ CE bundle ID in allBundleIds")
    check(SupportedApps.pyCharm.allBundleIds.contains("com.jetbrains.pycharm.ce"),
          "Expected PyCharm CE bundle ID in allBundleIds")

    // Verify percent-sign app filename safety
    check(AppManager.getApplicationFileName(from: "/Applications/100% App.app") == "100% App",
          "Expected safe handling of % in app name")

    // Verify Finder Alias resolution (#156)
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("oit-alias-test-\(UUID().uuidString)", isDirectory: true)
    let realFolder = tempRoot.appendingPathComponent("RealProject", isDirectory: true)
    let realFile = realFolder.appendingPathComponent("hello.txt", isDirectory: false)
    let folderAlias = tempRoot.appendingPathComponent("FolderAlias", isDirectory: false)
    let fileAlias = tempRoot.appendingPathComponent("FileAlias", isDirectory: false)
    try! FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
    try! "hello".write(to: realFile, atomically: true, encoding: .utf8)

    let folderBookmark = try! realFolder.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
    try! URL.writeBookmarkData(folderBookmark, to: folderAlias)
    let fileBookmark = try! realFile.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
    try! URL.writeBookmarkData(fileBookmark, to: fileAlias)

    check(folderAlias.resolvingFinderAlias().standardizedFileURL.path == realFolder.standardizedFileURL.path,
          "Expected folder Finder alias to resolve to \(realFolder.path), got \(folderAlias.resolvingFinderAlias().path)")
    var resolvedParent = fileAlias
    resolvedParent.getDirectory()
    check(resolvedParent.standardizedFileURL.path == realFolder.standardizedFileURL.path,
          "Expected file Finder alias getDirectory() to resolve to \(realFolder.path), got \(resolvedParent.path)")
    try? FileManager.default.removeItem(at: tempRoot)

    // Verify AppleScripts compile cleanly even with quotes/backslashes in paths
    for (label, source) in [
        ("generalScript", ScriptManager.shared.getGeneralScript()),
        ("terminalNewTabScript", ScriptManager.shared.getTerminalNewTabAppleScript()),
        ("terminalNewTabURL", ScriptManager.shared.getTerminalNewTabAppleScript(url: URL(fileURLWithPath: "/tmp/dir with \"quotes\" and \\backslash"))),
    ] {
        guard let appleScript = NSAppleScript(source: source) else {
            fputs("FAIL: NSAppleScript init failed for \(label)\n", stderr)
            exit(1)
        }
        var compileError: NSDictionary?
        let compiled = appleScript.compileAndReturnError(&compileError)
        check(compiled && compileError == nil,
              "AppleScript compilation failed for \(label): \(String(describing: compileError))")
    }

    print("OK: host-relaunch-verify")

case "extension-verify":
    check(SharedPreferences.isAppExtension == true,
          "Expected SharedPreferences.isAppExtension == true in extension mode")
    SharedPreferences.refreshExtension(force: true)

    check(DefaultsManager.shared.defaultTerminal?.name == "Otty",
          "Extension expected defaultTerminal == Otty, got \(String(describing: DefaultsManager.shared.defaultTerminal?.name))")
    check(DefaultsManager.shared.defaultEditor?.name == "Zed",
          "Extension expected defaultEditor == Zed, got \(String(describing: DefaultsManager.shared.defaultEditor?.name))")
    check(DefaultsManager.shared.getNewOption(.terminal) == .tab,
          "Extension expected TerminalNewOption == .tab")
    check(DefaultsManager.shared.isCustomMenuApplyToToolbar == true,
          "Extension expected isCustomMenuApplyToToolbar == true")
    check(DefaultsManager.shared.customMenuIconOption == .original,
          "Extension expected customMenuIconOption == .original")
    check(DefaultsManager.shared.customMenuOptions?.map(\.name) == ["Ghostty", "Visual Studio Code"],
          "Extension expected customMenuOptions == [Ghostty, Visual Studio Code]")
    print("OK: extension-verify")

case "host-reset":
    SharedPreferences.startHost()
    DefaultsManager.shared.removeAllUserDefaults()
    DefaultsManager.shared.firstSetup()
    SharedPreferences.publish()
    UserDefaults.standard.synchronize()

    check(DefaultsManager.shared.defaultTerminal?.name == "Terminal",
          "Expected defaultTerminal == Terminal after reset, got \(String(describing: DefaultsManager.shared.defaultTerminal?.name))")
    check(DefaultsManager.shared.defaultEditor?.name == "TextEdit",
          "Expected defaultEditor == TextEdit after reset, got \(String(describing: DefaultsManager.shared.defaultEditor?.name))")
    check(DefaultsManager.shared.isCustomMenuApplyToToolbar == false,
          "Expected isCustomMenuApplyToToolbar == false after reset")
    check(DefaultsManager.shared.customMenuOptions == nil,
          "Expected customMenuOptions == nil after reset")
    print("OK: host-reset")

case "extension-after-reset":
    SharedPreferences.refreshExtension(force: true)
    check(DefaultsManager.shared.defaultTerminal?.name == "Terminal",
          "Extension expected defaultTerminal == Terminal after reset")
    check(DefaultsManager.shared.defaultEditor?.name == "TextEdit",
          "Extension expected defaultEditor == TextEdit after reset")
    check(DefaultsManager.shared.isCustomMenuApplyToToolbar == false,
          "Extension expected isCustomMenuApplyToToolbar == false after reset")
    check(DefaultsManager.shared.customMenuOptions == nil,
          "Extension expected customMenuOptions == nil after reset")
    print("OK: extension-after-reset")

default:
    fputs("Unknown mode: \(mode)\n", stderr)
    exit(2)
}
