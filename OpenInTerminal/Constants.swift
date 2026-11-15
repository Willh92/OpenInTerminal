//
//  Config.swift
//  OpenInTerminal
//
//  Created by Jianing Wang on 2019/4/20.
//  Copyright © 2019 Jianing Wang. All rights reserved.
//

import Cocoa
import Foundation
import OpenInTerminalCore
import ServiceManagement

struct Constants {
    
    struct Id {
        static let LauncherApp = "wang.jianing.app.OpenInTerminalHelper"
        static var FinderExtension: String {
            return SharedPreferences.extensionBundleIdentifier
        }
        static let CustomAppCell = NSUserInterfaceItemIdentifier(rawValue: "customAppCell")
        static let CustomMenuCell = NSUserInterfaceItemIdentifier(rawValue: "customMenuCell")
        static let CustomInputViewController = "CustomInputViewController"
    }
    
    static let none = "None"
    
    struct Key {
        static let defaultTerminalShortcut = "OIT_DefaultTerminalShortcut"
        static let defaultEditorShortcut = "OIT_DefaultEditorShortcut"
        static let copyPathShortcut = "OIT_CopyPathShortcut"
        static let onlyActivateShortcutsInFinder = "OnlyActivateShortcutsInFinder"
    }
    
    static let PreferencesStoryboard = NSStoryboard(name: "Preferences", bundle: nil)
}

enum LaunchAtLoginManager {

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                return true
            }
            return DefaultsManager.shared.isLaunchAtLogin && status == .requiresApproval
        } else {
            return DefaultsManager.shared.isLaunchAtLogin
        }
    }

    static func setEnabled(_ enabled: Bool) {
        DefaultsManager.shared.isLaunchAtLogin = enabled
        if #available(macOS 13.0, *) {
            _ = SMLoginItemSetEnabled(Constants.Id.LauncherApp as CFString, false)
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logw("SMAppService.mainApp \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            }
        } else {
            _ = SMLoginItemSetEnabled(Constants.Id.LauncherApp as CFString, enabled)
        }
    }

    static func syncOnLaunch() {
        guard #available(macOS 13.0, *) else { return }
        if DefaultsManager.shared.isLaunchAtLogin && SMAppService.mainApp.status == .notRegistered {
            do {
                _ = SMLoginItemSetEnabled(Constants.Id.LauncherApp as CFString, false)
                try SMAppService.mainApp.register()
            } catch {
                logw("SMAppService migration on launch failed: \(error.localizedDescription)")
            }
        }
    }
}

extension NSImage {
    
    enum AssetIdentifier: String {
        case StatusBarIcon
    }
    
    convenience init(assetIdentifier: AssetIdentifier) {
        self.init(named: assetIdentifier.rawValue)!
    }
}

extension NSStoryboard {
    
    enum StoryboardIdentifier: String {
        case Preferences
    }
    
    convenience init(storyboardIdentifier: StoryboardIdentifier) {
        self.init(name: storyboardIdentifier.rawValue, bundle: nil)
    }
}
