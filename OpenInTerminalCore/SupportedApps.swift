//
//  SupportedApps.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2020/12/5.
//  Copyright © 2020 Jianing Wang. All rights reserved.
//

import AppKit
import Foundation

public enum SupportedApps: String, CaseIterable {
    
    // MARK: - Terminals
    case terminal = "Terminal"
    case iTerm = "iTerm"
    case hyper = "Hyper"
    case alacritty = "Alacritty"
    case kitty = "kitty"
    case wezterm = "WezTerm"
    case tabby = "Tabby"
    case warp = "Warp"
    case cmux = "cmux"
    case githubDesktop = "GitHub Desktop"
    case gitKraken = "GitKraken"
    case fork = "Fork"
    case ghostty = "Ghostty"
    case kaku = "Kaku"
    case otty = "Otty"
    
    // MARK: - Editors
    case textEdit = "TextEdit"
    case xcode = "Xcode"
    case vscode = "Visual Studio Code"
    case atom = "Atom"
    case sublime = "Sublime Text"
    case vscodium = "VSCodium"
    case bbedit = "BBEdit"
    case vscodeInsiders = "Visual Studio Code - Insiders"
    case textMate = "TextMate"
    case cotEditor = "CotEditor"
    case macVim = "MacVim"
    case typora = "Typora"
    case nova = "Nova"
    case cursor = "Cursor"
    case neovim = "Neovim"
    case zed = "Zed"
    case emacs = "Emacs"
    // JetBrains
    case appCode = "AppCode"
    case cLion = "CLion"
    case fleet = "Fleet"
    case goLand = "GoLand"
    case intelliJIDEA = "IntelliJ IDEA"
    case phpStorm = "PhpStorm"
    case pyCharm = "PyCharm"
    case rubyMine = "RubyMine"
    case webStorm = "WebStorm"
    case androidstudio = "Android Studio"
    
    public var name: String {
        return self.rawValue
    }
    
    public var shortName: String {
        switch self {
        case .vscode: return "VSCode"
        case .sublime: return "Sublime"
        case .vscodeInsiders: return "VSCodeInsiders"
        case .intelliJIDEA: return "IntelliJ_IDEA"
        case .androidstudio: return "Android_Studio"
        default:
            return self.rawValue
        }
    }
    
    public var type: AppType {
        switch self {
        case .terminal, .iTerm, .hyper, .alacritty, .kitty, .wezterm, .tabby, .warp, .cmux, .githubDesktop, .fork, .ghostty, .gitKraken, .kaku, .otty:
            return .terminal
        default:
            return .editor
        }
    }
    
    /// Finds a supported app whose name matches the given name, ignoring case.
    public static func from(name: String) -> SupportedApps? {
        return SupportedApps.allCases.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    public static func isSupported(_ app: App) -> Bool {
        return from(name: app.name) != nil
    }

    public static func `is`(_ app: App, is supported: SupportedApps) -> Bool {
        return app.name.caseInsensitiveCompare(supported.name) == .orderedSame
    }
    
    public static var terminals: [SupportedApps] {
        return SupportedApps.allCases.filter {
            $0.type == .terminal
        }
    }
    
    public static var editors: [SupportedApps] {
        return SupportedApps.allCases.filter {
            $0.type == .editor
        }
    }
    
    public var bundleId: String {
        switch self {
        // Terminals
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .hyper: return "co.zeit.hyper"
        case .alacritty: return "io.alacritty"
        case .kitty: return "net.kovidgoyal.kitty"
        case .wezterm: return "com.github.wez.wezterm"
        case .tabby: return "org.tabby"
        case .warp: return "dev.warp.Warp-Stable"
        case .cmux: return "com.cmuxterm.app"
        case .githubDesktop: return "com.github.GitHubClient"
        case .gitKraken: return "com.axosoft.gitkraken"
        case .fork: return "com.DanPristupov.Fork"
        case .ghostty: return "com.mitchellh.ghostty"
        case .kaku: return "fun.tw93.kaku"
        case .otty: return "io.appmakes.otty"
        // Editors
        case .textEdit: return "com.apple.TextEdit"
        case .xcode: return "com.apple.Xcode"
        case .vscode: return "com.microsoft.VSCode"
        case .atom: return "com.github.atom"
        case .sublime: return "com.sublimetext.4"
        case .vscodium: return "com.visualstudio.code.oss"
        case .bbedit: return "com.barebones.bbedit"
        case .vscodeInsiders: return "com.microsoft.VSCodeInsiders"
        case .textMate: return "com.macromates.TextMate"
        case .cotEditor: return "com.coteditor.CotEditor"
        case .macVim: return "org.vim.MacVim"
        case .typora: return "abnerworks.Typora"
        case .nova: return "com.panic.Nova"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .appCode: return "com.jetbrains.appcode"
        case .cLion: return "com.jetbrains.clion"
        case .fleet: return "com.jetbrains.fleet"
        case .goLand: return "com.jetbrains.goland"
        case .intelliJIDEA: return "com.jetbrains.intellij"
        case .phpStorm: return "com.jetbrains.PhpStorm"
        case .pyCharm: return "com.jetbrains.pycharm"
        case .rubyMine: return "com.jetbrains.rubymine"
        case .webStorm: return "com.jetbrains.webstorm"
        case .androidstudio: return "com.google.android.studio"
        case .neovim: return ""
        case .zed: return "dev.zed.Zed"
        case .emacs: return "org.gnu.Emacs"
        }
    }

    /// Alternate bundle identifiers for Community Edition / Preview / legacy releases.
    public var alternateBundleIds: [String] {
        switch self {
        case .alacritty:
            return ["org.alacritty"]
        case .wezterm:
            return ["org.wezfurlong.wezterm"]
        case .warp:
            return ["dev.warp", "dev.warp.Warp-Preview"]
        case .sublime:
            return ["com.sublimetext.3", "com.sublimetext.2"]
        case .intelliJIDEA:
            return ["com.jetbrains.intellij.ce", "com.jetbrains.intellij-EAP"]
        case .pyCharm:
            return ["com.jetbrains.pycharm.ce", "com.jetbrains.pycharm-EAP"]
        case .zed:
            return ["dev.zed.Zed-Preview"]
        default:
            return []
        }
    }

    public var allBundleIds: [String] {
        return ([bundleId] + alternateBundleIds).filter { !$0.isEmpty }
    }

    /// Resolves the bundle identifier of whichever edition is currently installed on disk.
    public var resolvedBundleId: String? {
        for candidate in allBundleIds {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil {
                return candidate
            }
        }
        return nil
    }

    /// Resolves the on-disk `.app` bundle URL via Launch Services.
    public var installedApplicationURL: URL? {
        for candidate in allBundleIds {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                return url
            }
        }
        return nil
    }

    /// Builds a `warp://action/new_window?path=...` deep link so Warp opens a single window
    /// instead of both a startup `~` window and a target folder window on cold launch (#230).
    public static func warpURI(forPath path: String, newTab: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = newTab ? "/new_tab" : "/new_window"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
    
    public var app: App {
        var app = App(name: self.name, type: self.type)
        app.bundleId = self.resolvedBundleId ?? self.bundleId
        return app
    }
}
