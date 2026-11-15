//
//  FinderManager.swift
//  OpenInTerminalCore
//
//  Created by Cameron Ingham on 4/17/19.
//  Copyright © 2019 Cameron Ingham. All rights reserved.
//

import Cocoa
import ScriptingBridge

public class FinderManager {
    
    public static var shared = FinderManager()
    
    private func normalizeFinderURL(_ rawURLString: String) -> URL? {
        if rawURLString.hasPrefix("/") {
            return URL(fileURLWithPath: rawURLString).resolvingFinderAlias()
        }
        if let url = URL(string: rawURLString) {
            let fileURL = (url as NSURL).filePathURL ?? url
            return fileURL.resolvingFinderAlias()
        }
        if let encoded = rawURLString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded) {
            let fileURL = (url as NSURL).filePathURL ?? url
            return fileURL.resolvingFinderAlias()
        }
        return nil
    }

    /// Fallback via AppleScript `POSIX path` for volume roots (`FinderDisk` on `/Volumes/...`)
    /// or Finder items whose ScriptingBridge `.URL` property is nil (#212).
    private func queryFinderURLsViaAppleScript() -> [URL] {
        let source = """
        tell application "Finder"
            set outPaths to {}
            try
                set selList to selection as alias list
                if selList is not {} then
                    repeat with anItem in selList
                        set end of outPaths to POSIX path of anItem
                    end repeat
                    return outPaths
                end if
            end try
            try
                if (count of Finder windows) > 0 then
                    set winTarget to target of front Finder window as alias
                    set end of outPaths to POSIX path of winTarget
                end if
            end try
            return outPaths
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            return []
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if error != nil {
            return []
        }
        let count = descriptor.numberOfItems
        guard count > 0 else {
            if let single = descriptor.stringValue, !single.isEmpty {
                return [URL(fileURLWithPath: single).resolvingFinderAlias()]
            }
            return []
        }
        var urls: [URL] = []
        for idx in 1...count {
            if let posixPath = descriptor.atIndex(idx)?.stringValue, !posixPath.isEmpty {
                urls.append(URL(fileURLWithPath: posixPath).resolvingFinderAlias())
            }
        }
        return urls
    }

    /// Get full url to front Finder window or selected file
    public func getFullUrlToFrontFinderWindowOrSelectedFile() throws -> URL? {
        let urls = try getFullUrlsToFrontFinderWindowOrSelectedFile()
        return urls.first
    }
    
    /// Get full path to front Finder window or selected file
    public func getFullPathToFrontFinderWindowOrSelectedFile() throws -> String {
        guard let url = try getFullUrlToFrontFinderWindowOrSelectedFile() else {
            return ""
        }
        return url.path
    }
    
    /// Get full urls to front Finder windows or selected files
    public func getFullUrlsToFrontFinderWindowOrSelectedFile() throws -> [URL] {
        guard let finderObject = SBApplication(bundleIdentifier: Constants.Id.Finder) else {
            throw OITError.cannotAccessFinder
        }
        let finder = finderObject as FinderApplication
        
        guard let selection = finder.selection,
              let selectionItems = selection.get() else {
            let fallback = queryFinderURLsViaAppleScript()
            if !fallback.isEmpty {
                return fallback
            }
            throw OITError.cannotAccessFinder
        }
        
        var resolvedURLs: [URL] = []
        if let rawItems = selectionItems as? [AnyObject], !rawItems.isEmpty {
            // Files or folders are selected
            for item in rawItems {
                if let finderItem = item as? FinderItem,
                   let urlString = finderItem.URL,
                   let url = normalizeFinderURL(urlString) {
                    resolvedURLs.append(url)
                }
            }
            if resolvedURLs.isEmpty {
                resolvedURLs = queryFinderURLsViaAppleScript()
            }
            return resolvedURLs
        }

        // Check if there are opened finder windows
        guard let windows = finder.FinderWindows?(),
              let firstWindow = windows.firstObject else {
            return []
        }

        if let finderWindow = firstWindow as? FinderFinderWindow,
           let targetObject = finderWindow.target?.get(),
           let targetItem = targetObject as? FinderItem,
           let urlString = targetItem.URL,
           let url = normalizeFinderURL(urlString) {
            return [url]
        }

        return queryFinderURLsViaAppleScript()
    }
    
    /// Get full paths to front Finder windows or selected files
    public func getFullPathsToFrontFinderWindowOrSelectedFile() throws -> [String] {
        let urls = try getFullUrlsToFrontFinderWindowOrSelectedFile()
        return urls.map { $0.path }
    }
    
    /// Get path to front Finder window or selected file.
    /// If the selected one is file, return it's parent path.
    public func getPathToFrontFinderWindowOrSelectedFile() throws -> String {
        guard var fullUrl = try getFullUrlToFrontFinderWindowOrSelectedFile() else {
            return ""
        }
        fullUrl.getDirectory()
        guard FileManager.default.fileExists(atPath: fullUrl.path) else {
            return ""
        }
        return fullUrl.path
    }
    
    public func getDesktopPath() -> String? {
        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            return desktopURL.path
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }
    
    /// Get all installed applications' names
    public func getAllInstalledApps() -> Set<String> {
        var applications: Set<String> = Set()
        // add system application
        applications.insert("Terminal")
        applications.insert("TextEdit")
        // neovim is a command-line program (`nvim`), not a `.app`, so probe for its binary
        if isCommandLineToolInstalled("nvim") {
            applications.insert("Neovim")
        }
        // Query Launch Services for all known SupportedApps bundle IDs (including Community Editions,
        // Homebrew/Nix locations, Setapp, and JetBrains Toolbox installs).
        for supported in SupportedApps.allCases where supported.installedApplicationURL != nil {
            applications.insert(supported.name)
        }

        let fileManager = FileManager.default
        var searchDirs: Set<URL> = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]
        for userAppDir in fileManager.urls(for: .applicationDirectory, in: .userDomainMask) {
            searchDirs.insert(userAppDir)
        }
        if let libDirURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let toolboxURL = libDirURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("JetBrains", isDirectory: true)
                .appendingPathComponent("Toolbox", isDirectory: true)
            if fileManager.fileExists(atPath: toolboxURL.path) {
                searchDirs.insert(toolboxURL)
            }
        }

        let skippedBundleExtensions: Set<String> = ["app", "framework", "bundle", "plugin", "appex", "xcodeproj", "xcworkspace"]
        var visitedDirs: Set<String> = Set()
        var levelCount = 0

        while !searchDirs.isEmpty && levelCount < 20 {
            levelCount += 1
            var nextSearchDirs: Set<URL> = Set()

            for currentDir in searchDirs {
                let canonicalDir = currentDir.resolvingSymlinksInPath().standardizedFileURL.path
                if visitedDirs.contains(canonicalDir) {
                    continue
                }
                visitedDirs.insert(canonicalDir)

                guard let fileURLs = try? fileManager.contentsOfDirectory(
                    at: currentDir,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for fileURL in fileURLs {
                    let baseName = fileURL.lastPathComponent
                    let ext = fileURL.pathExtension.lowercased()

                    if ext == "app" {
                        let rawAppName = fileURL.deletingPathExtension().lastPathComponent
                        applications.insert(Self.normalizedInstalledAppName(rawAppName))
                        continue
                    }

                    if skippedBundleExtensions.contains(ext) {
                        continue
                    }

                    // Resolve symlinks (such as nix-darwin's "Nix Apps" directory) safely without force-unwraps
                    let candidateURL: URL
                    let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey])
                    if values?.isPackage == true {
                        continue
                    }
                    if values?.isSymbolicLink == true || baseName == "Nix Apps" {
                        candidateURL = fileURL.resolvingSymlinksInPath()
                    } else if values?.isAliasFile == true {
                        continue
                    } else {
                        candidateURL = fileURL
                    }

                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDir), isDir.boolValue {
                        let resolvedPath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
                        if !visitedDirs.contains(resolvedPath) {
                            nextSearchDirs.insert(candidateURL)
                        }
                    }
                }
            }

            searchDirs = nextSearchDirs
        }
        
        return applications
    }

    private static func normalizedInstalledAppName(_ appName: String) -> String {
        switch appName {
        case "iTerm2":
            return "iTerm"
        case "IntelliJ IDEA CE", "IntelliJ IDEA Community Edition", "IntelliJ IDEA Ultimate":
            return "IntelliJ IDEA"
        case "PyCharm CE", "PyCharm Community Edition", "PyCharm Professional", "PyCharm Professional Edition":
            return "PyCharm"
        default:
            return appName
        }
    }

    /// Check whether a command-line tool is actually installed, by looking in the
    /// common install locations (Homebrew, MacPorts, Nix, system, user-local) and
    /// on the user's `PATH`.
    public func isCommandLineToolInstalled(_ tool: String) -> Bool {
        let fileManager = FileManager.default
        var searchPaths = [
            "/opt/homebrew/bin",            // Apple Silicon Homebrew
            "/usr/local/bin",              // Intel Homebrew
            "/usr/bin",
            "/bin",
            "/opt/local/bin",             // MacPorts
            "/run/current-system/sw/bin", // Nix
            NSHomeDirectory() + "/.local/bin",
        ]
        // Also honor the directories on the user's PATH, if it is available.
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        for dir in searchPaths {
            let fullPath = (dir as NSString).appendingPathComponent(tool)
            if fileManager.isExecutableFile(atPath: fullPath) {
                return true
            }
        }
        return false
    }

}
