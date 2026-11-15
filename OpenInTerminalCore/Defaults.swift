//
//  Defaults.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2019/4/21.
//  Copyright © 2019 Jianing Wang. All rights reserved.
//

import Foundation

/// Standard per-process preferences store.
///
/// On macOS 26/27+, `cfprefsd` rejects unprefixed/unowned `group.*` App Group suites,
/// causing host settings to vanish on quit/reboot and leaving the sandboxed Finder
/// extension with empty menus. Using `UserDefaults.standard` in the host app preserves
/// native persistence (`~/Library/Preferences/<hostBundleID>.plist`), KVO, and Cocoa
/// Bindings (`ShortcutRecorder`), while `SharedPreferences` mirrors extension-relevant
/// settings into `~/Library/Application Scripts/<extensionBundleID>/shared-settings.plist`
/// where the sandboxed Finder Sync extension can read them without App Group entitlements
/// or TCC "access data from other apps" prompts.
public var Defaults: UserDefaults = UserDefaults.standard

public enum SharedPreferences {

    public static let sharedFileName = "shared-settings.plist"
    public static let legacyMigrationKey = "LegacyPreferencesMigrated"

    /// Keys mirrored from the host app to the Finder Sync extension snapshot.
    public static let sharedKeys: [String] = [
        "FirstSetup",
        "LaunchAtLogin",
        "QuickToggle",
        "QuickToggleType",
        "HideStatusItem",
        "HideContextMenuItems",
        "ContextMenuUseSubmenu",
        "DefaultTerminal",
        "DefaultEditor",
        "TerminalNewOption",
        "iTermNewOption",
        "CustomMenuOptions",
        "CustomMenuApplyToToolbar",
        "CustomMenuApplyToContext",
        "CustomMenuIconOption",
        "PathEscapeOption",
        "KittyCommand",
        "OnlyActivateShortcutsInFinder",
        "NeovimCommand",
        "GitkrakenCommand",
    ]

    /// Additional host-only keys migrated once from legacy `group.wang.jianing.app.OpenInTerminal`.
    private static let hostOnlyLegacyKeys: [String] = [
        "OIT_DefaultTerminalShortcut",
        "OIT_DefaultEditorShortcut",
        "OIT_CopyPathShortcut",
    ]

    private static let lock = NSLock()
    private static var hostStarted = false
    private static var hostObserver: NSObjectProtocol?
    private static var isPublishing = false
    private static var cachedSnapshot: [String: Any] = [:]
    private static var cachedModificationDate: Date?
    private static var cachedFileSize: UInt64?

    public static var isAppExtension: Bool {
        if ProcessInfo.processInfo.environment["OIT_FORCE_EXTENSION_MODE"] == "1" {
            return true
        }
        return Bundle.main.bundlePath.hasSuffix(".appex")
    }

    public static var isLiteApp: Bool {
        let bundleId = Bundle.main.bundleIdentifier
        return bundleId == Constants.Id.OpenInTerminalLite ||
            bundleId == Constants.Id.OpenInEditorLite
    }

    public static var isHostApp: Bool {
        return !isAppExtension && !isLiteApp
    }

    public static var extensionBundleIdentifier: String {
        if isAppExtension, let id = Bundle.main.bundleIdentifier, !id.isEmpty {
            return id
        }
        let hostId = Bundle.main.bundleIdentifier ?? Constants.Id.HostApp
        if hostId.hasSuffix(Constants.Id.FinderExtensionSuffix) {
            return hostId
        }
        return hostId + Constants.Id.FinderExtensionSuffix
    }

    /// Location of `shared-settings.plist` inside `~/Library/Application Scripts/<extensionBundleID>/`.
    public static var sharedSettingsURL: URL? {
        if let overridePath = ProcessInfo.processInfo.environment["OIT_SHARED_PREFERENCES_PATH"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        if isAppExtension {
            guard let scriptsDir = try? FileManager.default.url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ) else {
                return nil
            }
            return scriptsDir.appendingPathComponent(sharedFileName)
        } else {
            guard var scriptsDir = try? FileManager.default.url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                return nil
            }
            scriptsDir.deleteLastPathComponent()
            return scriptsDir
                .appendingPathComponent(extensionBundleIdentifier, isDirectory: true)
                .appendingPathComponent(sharedFileName)
        }
    }

    /// Starts host-side preference migration, change observation, and snapshot publishing.
    public static func startHost() {
        guard isHostApp else { return }
        lock.lock()
        let alreadyStarted = hostStarted
        hostStarted = true
        lock.unlock()

        migrateLegacyPreferencesIfNeeded()

        if !alreadyStarted {
            let token = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: Defaults,
                queue: nil
            ) { _ in
                publish()
            }
            lock.lock()
            hostObserver = token
            lock.unlock()
        }

        publish()
    }

    /// Migrates readable settings once from legacy `group.wang.jianing.app.OpenInTerminal` plist files
    /// without invoking `UserDefaults(suiteName:)` (avoiding `cfprefsd` / TCC prompts on macOS 26/27).
    public static func migrateLegacyPreferencesIfNeeded() {
        guard isHostApp else { return }
        if Defaults.bool(forKey: legacyMigrationKey) {
            return
        }

        var candidateURLs: [URL] = []
        if let customLegacy = ProcessInfo.processInfo.environment["OIT_LEGACY_PREFERENCES_PATH"],
           !customLegacy.isEmpty {
            candidateURLs.append(URL(fileURLWithPath: customLegacy))
        } else {
            let home = NSHomeDirectory()
            let groupContainerPlist = (home as NSString)
                .appendingPathComponent("Library/Group Containers/\(Constants.Id.Group)/Library/Preferences/\(Constants.Id.Group).plist")
            let standardLibraryPlist = (home as NSString)
                .appendingPathComponent("Library/Preferences/\(Constants.Id.Group).plist")
            candidateURLs.append(URL(fileURLWithPath: groupContainerPlist))
            candidateURLs.append(URL(fileURLWithPath: standardLibraryPlist))
        }

        let keysToMigrate = sharedKeys + hostOnlyLegacyKeys
        for url in candidateURLs {
            guard FileManager.default.isReadableFile(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }
            for key in keysToMigrate {
                if Defaults.object(forKey: key) == nil, let legacyValue = plist[key] {
                    Defaults.set(legacyValue, forKey: key)
                }
            }
            break
        }

        Defaults.set(true, forKey: legacyMigrationKey)
    }

    /// Atomically writes all extension-relevant preferences to `shared-settings.plist` with mode `0600`.
    public static func publish() {
        guard isHostApp else { return }

        lock.lock()
        if isPublishing {
            lock.unlock()
            return
        }
        isPublishing = true
        lock.unlock()
        defer {
            lock.lock()
            isPublishing = false
            lock.unlock()
        }

        guard let targetURL = sharedSettingsURL else { return }
        let directoryURL = targetURL.deletingLastPathComponent()

        var snapshot: [String: Any] = [:]
        for key in sharedKeys {
            if let value = Defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: snapshot,
            format: .binary,
            options: 0
        ) else {
            return
        }

        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directoryURL.path) {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            let tempURL = directoryURL.appendingPathComponent(".\(sharedFileName).\(UUID().uuidString).tmp")
            try data.write(to: tempURL, options: [])
            try? fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: tempURL.path)
            if fm.fileExists(atPath: targetURL.path) {
                _ = try fm.replaceItemAt(targetURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: targetURL)
            }
            try? fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: targetURL.path)
        } catch {
            logw("Failed to publish shared settings: \(error.localizedDescription)")
        }
    }

    /// Reloads `shared-settings.plist` in the Finder Sync extension when the file has changed on disk.
    public static func refreshExtension(force: Bool = false) {
        guard let url = sharedSettingsURL else { return }
        let fm = FileManager.default

        lock.lock()
        defer { lock.unlock() }

        guard fm.fileExists(atPath: url.path),
              let attrs = try? fm.attributesOfItem(atPath: url.path) else {
            if force {
                cachedSnapshot = [:]
                cachedModificationDate = nil
                cachedFileSize = nil
            }
            return
        }

        let mtime = attrs[.modificationDate] as? Date
        let size = (attrs[.size] as? NSNumber)?.uint64Value
        if !force,
           let cachedMtime = cachedModificationDate,
           let mtime = mtime,
           cachedMtime == mtime,
           cachedFileSize == size {
            return
        }

        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return
        }
        cachedSnapshot = dict
        cachedModificationDate = mtime
        cachedFileSize = size
    }

    fileprivate static func extensionValue(forKey key: String) -> Any? {
        refreshExtension(force: false)
        lock.lock()
        let value = cachedSnapshot[key]
        lock.unlock()
        return value
    }
}

public class DefaultsKeys {
    fileprivate init() {}
}

public class DefaultsKey<ValueType>: DefaultsKeys {
    let _key: String
    
    init(_ key: String) {
        self._key = key
    }
}

public extension DefaultsKeys {
    // Preferences - General
    static let firstSetup = DefaultsKey<Bool>("FirstSetup")
    static let launchAtLogin = DefaultsKey<Bool>("LaunchAtLogin")
    static let quickToggle = DefaultsKey<Bool>("QuickToggle")
    static let quickToggleType = DefaultsKey<String>("QuickToggleType")
    static let hideStatusItem = DefaultsKey<Bool>("HideStatusItem")
    static let hideContextMenuItems = DefaultsKey<Bool>("HideContextMenuItems")
    static let contextMenuUseSubmenu = DefaultsKey<Bool>("ContextMenuUseSubmenu")
    static let defaultTerminal = DefaultsKey<String>("DefaultTerminal")
    static let defaultEditor = DefaultsKey<String>("DefaultEditor")
    // Preferences - Custom
    static let terminalNewOption = DefaultsKey<String>("TerminalNewOption")
    static let iTermNewOption = DefaultsKey<String>("iTermNewOption")
    static let customMenuOptions = DefaultsKey<Data>("CustomMenuOptions")
    static let customMenuApplyToToolbar = DefaultsKey<Bool>("CustomMenuApplyToToolbar")
    static let customMenuApplyToContext = DefaultsKey<Bool>("CustomMenuApplyToContext")
    static let customMenuIconOption = DefaultsKey<String>("CustomMenuIconOption")
    static let pathEscapeOption = DefaultsKey<Bool>("PathEscapeOption")
    static let kittyCommand = DefaultsKey<String>("KittyCommand")
    static let onlyActivateShortcutsInFinder = DefaultsKey<Bool>("OnlyActivateShortcutsInFinder")
    static let neovimCommand = DefaultsKey<String>("NeovimCommand")
    static let gitkrakenCommand = DefaultsKey<String>("GitkrakenCommand")
    
    // for Lite
    static let liteDefaultTerminal = DefaultsKey<String>("LiteDefaultTerminal")
    static let liteDefaultEditor = DefaultsKey<String>("LiteDefaultEditor")
}

public extension UserDefaults {
    private func usesExtensionSnapshot() -> Bool {
        return self === Defaults && SharedPreferences.isAppExtension
    }

    private func publishIfHost() {
        if self === Defaults && SharedPreferences.isHostApp {
            SharedPreferences.publish()
        }
    }

    subscript(key: DefaultsKey<String>) -> String? {
        get {
            if usesExtensionSnapshot() {
                return (SharedPreferences.extensionValue(forKey: key._key) as? String) ?? string(forKey: key._key)
            }
            return string(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Bool>) -> Bool {
        get {
            if usesExtensionSnapshot() {
                if let val = SharedPreferences.extensionValue(forKey: key._key) as? Bool {
                    return val
                }
                if let num = SharedPreferences.extensionValue(forKey: key._key) as? NSNumber {
                    return num.boolValue
                }
            }
            return bool(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Int>) -> Int {
        get {
            if usesExtensionSnapshot() {
                if let val = SharedPreferences.extensionValue(forKey: key._key) as? Int {
                    return val
                }
                if let num = SharedPreferences.extensionValue(forKey: key._key) as? NSNumber {
                    return num.intValue
                }
            }
            return integer(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Float>) -> Float {
        get {
            if usesExtensionSnapshot() {
                if let val = SharedPreferences.extensionValue(forKey: key._key) as? Float {
                    return val
                }
                if let num = SharedPreferences.extensionValue(forKey: key._key) as? NSNumber {
                    return num.floatValue
                }
            }
            return float(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Double>) -> Double {
        get {
            if usesExtensionSnapshot() {
                if let val = SharedPreferences.extensionValue(forKey: key._key) as? Double {
                    return val
                }
                if let num = SharedPreferences.extensionValue(forKey: key._key) as? NSNumber {
                    return num.doubleValue
                }
            }
            return double(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<URL>) -> URL? {
        get {
            if usesExtensionSnapshot() {
                if let url = SharedPreferences.extensionValue(forKey: key._key) as? URL {
                    return url
                }
                if let str = SharedPreferences.extensionValue(forKey: key._key) as? String {
                    return URL(string: str)
                }
            }
            return url(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Any>) -> Any? {
        get {
            if usesExtensionSnapshot() {
                return SharedPreferences.extensionValue(forKey: key._key) ?? value(forKey: key._key)
            }
            return value(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<[Any]>) -> [Any]? {
        get {
            if usesExtensionSnapshot() {
                return (SharedPreferences.extensionValue(forKey: key._key) as? [Any]) ?? array(forKey: key._key)
            }
            return array(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<Data>) -> Data? {
        get {
            if usesExtensionSnapshot() {
                return (SharedPreferences.extensionValue(forKey: key._key) as? Data) ?? data(forKey: key._key)
            }
            return data(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<[String : Any]>) -> [String : Any]? {
        get {
            if usesExtensionSnapshot() {
                return (SharedPreferences.extensionValue(forKey: key._key) as? [String: Any]) ?? dictionary(forKey: key._key)
            }
            return dictionary(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
    subscript(key: DefaultsKey<[String]>) -> [String]? {
        get {
            if usesExtensionSnapshot() {
                return (SharedPreferences.extensionValue(forKey: key._key) as? [String]) ?? stringArray(forKey: key._key)
            }
            return stringArray(forKey: key._key)
        }
        set {
            set(newValue, forKey: key._key)
            publishIfHost()
        }
    }
}
