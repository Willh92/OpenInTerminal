//
//  App.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2020/12/5.
//  Copyright © 2020 Jianing Wang. All rights reserved.
//

import AppKit
import Foundation
import ScriptingBridge

public enum AppType: String, Codable {
    case terminal
    case editor
}

public struct App: Codable {
    public var name: String
    public var path: String?
    public var bundleId: String?
    public var type: AppType
    
    public init(name: String, type: AppType) {
        self.name = name
        self.type = type
    }
}

extension App: Equatable {
    public static func == (lhs: App, rhs: App) -> Bool {
        return lhs.name == rhs.name && lhs.bundleId == rhs.bundleId
    }
}

// MARK: - Openable

public protocol Openable {
    func openOutsideSandbox() throws
    func openInSandbox(_ urls: [URL]) throws
}

extension App: Openable {
    
    public func openOutsideSandbox() throws {

        // Launch the `open` command directly, passing each path as a discrete
        // argument. This avoids building a shell command string or an AppleScript
        // source string from an untrusted path, which was exploitable for both
        // AppleScript injection and shell command injection via crafted folder
        // names. See the security advisory (Findings 1 & 2).
        func runOpen(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            logw("open " + arguments.joined(separator: " "))
            do {
                try process.run()
            } catch {
                throw OITError.cannotAccessApp(self.name)
            }
        }

        switch self.type {
        case .terminal:
            // get path
            var path = try FinderManager.shared.getPathToFrontFinderWindowOrSelectedFile()
            if path == "" {
                // No Finder window and no file selected.
                guard let desktopPath = FinderManager.shared.getDesktopPath() else { return }
                path = desktopPath
            }

            if SupportedApps.is(self, is: .warp),
               let warpURL = SupportedApps.warpURI(forPath: path, newTab: false) {
                try runOpen([warpURL.absoluteString])
            } else if SupportedApps.is(self, is: .terminal) {
                let url = URL(fileURLWithPath: path)
                if DefaultsManager.shared.getNewOption(.terminal) == .tab,
                   let script = NSAppleScript(source: ScriptManager.shared.getTerminalNewTabAppleScript(url: url)) {
                    var error: NSDictionary?
                    script.executeAndReturnError(&error)
                    if error == nil {
                        return
                    }
                    logw("Terminal new-tab AppleScript failed, falling back to Launch Services: \(String(describing: error))")
                }
                // Launch Services (`open -b com.apple.Terminal <path>`) opens the target folder
                // directly without requiring Terminal Automation TCC (#278).
                try runOpen(["-b", SupportedApps.terminal.bundleId, path])
            } else {
                // this app is general (e.g. iTerm, Alacritty, kitty, Ghostty)
                var arguments = DefaultsManager.shared.getOpenArguments(self)
                arguments.append(path)
                try runOpen(arguments)
            }

        case .editor:
            // get paths
            var paths = try FinderManager.shared.getFullPathsToFrontFinderWindowOrSelectedFile()
            if paths.count == 0 {
                // No Finder window and no file selected.
                guard let desktopPath = FinderManager.shared.getDesktopPath() else { return }
                paths.append(desktopPath)
            }

            var arguments = DefaultsManager.shared.getOpenArguments(self)
            // fix for neovim: the command template carries a "PATH" placeholder
            // token that must be replaced by the actual path arguments.
            if SupportedApps.is(self, is: .neovim) {
                arguments = arguments.flatMap { $0 == "PATH" ? paths : [$0] }
            } else {
                arguments.append(contentsOf: paths)
            }
            try runOpen(arguments)
        }
    }
    
    public func openInSandbox(_ urls: [URL]) throws {
        let resolvedURLs = urls.map { $0.resolvingFinderAlias() }
        guard !resolvedURLs.isEmpty else { return }

        let targetURLs: [URL]
        switch self.type {
        case .terminal:
            var dirURL = resolvedURLs[0]
            dirURL.getDirectory()
            targetURLs = [dirURL]
        case .editor:
            targetURLs = resolvedURLs
        }

        // Warp cold-start single-window fix (#230): open `warp://action/new_window?path=...`
        if self.type == .terminal,
           SupportedApps.is(self, is: .warp),
           let warpURL = SupportedApps.warpURI(forPath: targetURLs[0].path, newTab: false),
           NSWorkspace.shared.open(warpURL) {
            return
        }

        // Terminal new-tab option
        if self.type == .terminal,
           SupportedApps.is(self, is: .terminal),
           DefaultsManager.shared.getNewOption(.terminal) == .tab,
           let tabScriptURL = ScriptManager.shared.getScriptURL(with: Constants.terminalNewTabScript),
           FileManager.default.fileExists(atPath: tabScriptURL.path),
           let tabTask = try? NSUserAppleScriptTask(url: tabScriptURL) {
            let appCopy = self
            let event = ScriptManager.shared.getScriptEvent(functionName: "openApp", arguments: [targetURLs[0].path])
            tabTask.execute(withAppleEvent: event) { _, error in
                if let error = error {
                    logw("Terminal new-tab script failed: \(error)")
                    appCopy.openViaWorkspaceFallback(targetURLs: targetURLs)
                }
            }
            return
        }

        // Build the invocation as a list of discrete arguments — the leading
        // program, the app-specific option tokens (trusted config from
        // getOpenArguments), then the raw target paths as individual elements.
        // The installed AppleScript shell-quotes every element via
        // `quoted form of`, so nothing here is manually escaped and a crafted
        // file/folder name cannot inject shell commands. This mirrors the
        // argument-array approach used by openOutsideSandbox.
        var arguments = ["/usr/bin/open"]
        let openArgs = DefaultsManager.shared.getOpenArguments(self)
        arguments.append(contentsOf: openArgs)
        let usesCustomCLIArgs = openArgs.contains("--args")

        switch self.type {
        case .terminal:
            arguments.append(targetURLs[0].path)
        case .editor:
            let paths = targetURLs.map { $0.path }
            // fix for neovim: the command template carries a "PATH" placeholder
            // token that must be replaced by the actual path arguments.
            if SupportedApps.is(self, is: .neovim) {
                arguments = arguments.flatMap { $0 == "PATH" ? paths : [$0] }
            } else {
                arguments.append(contentsOf: paths)
            }
        }

        let appCopy = self
        if let scriptURL = ScriptManager.shared.getScriptURL(with: Constants.generalScript),
           FileManager.default.fileExists(atPath: scriptURL.path),
           let script = try? NSUserAppleScriptTask(url: scriptURL) {
            let event = ScriptManager.shared.getScriptEvent(functionName: "openApp", arguments: arguments)
            script.execute(withAppleEvent: event) { _, error in
                if let error = error {
                    logw("cannot execute applescript: \(error)")
                    if !usesCustomCLIArgs {
                        appCopy.openViaWorkspaceFallback(targetURLs: targetURLs)
                    }
                }
            }
        } else if !usesCustomCLIArgs {
            openViaWorkspaceFallback(targetURLs: targetURLs)
        } else {
            logw("AppleScript runner not installed yet for CLI-arg app: \(self.name)")
        }
    }

    private func openViaWorkspaceFallback(targetURLs: [URL]) {
        let appURL: URL? = {
            if let supported = SupportedApps.from(name: self.name),
               let url = supported.installedApplicationURL {
                return url
            }
            if let bundleId = self.bundleId, !bundleId.isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return url
            }
            if let appPath = self.path, !appPath.isEmpty,
               FileManager.default.fileExists(atPath: appPath) {
                return URL(fileURLWithPath: appPath)
            }
            let candidates = [
                "/Applications/\(self.name).app",
                "/System/Applications/\(self.name).app",
                "/System/Applications/Utilities/\(self.name).app",
                (NSHomeDirectory() as NSString).appendingPathComponent("Applications/\(self.name).app"),
            ]
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
            return nil
        }()

        guard let resolvedAppURL = appURL else {
            logw("Workspace fallback could not locate application: \(self.name)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(targetURLs, withApplicationAt: resolvedAppURL, configuration: configuration) { _, error in
            if let error = error {
                logw("Workspace fallback failed for \(self.name): \(error.localizedDescription)")
            }
        }
    }
    
}

