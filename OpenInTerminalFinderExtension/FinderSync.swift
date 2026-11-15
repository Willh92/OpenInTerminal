//
//  FinderSync.swift
//  OpenInTerminalFinderExtension
//
//  Created by Cameron Ingham on 4/17/19.
//  Copyright © 2019 Cameron Ingham. All rights reserved.
//

import Cocoa
import FinderSync
import OpenInTerminalCore
import Carbon

class FinderSync: FIFinderSync {
    
    override init() {
        super.init()
        SharedPreferences.refreshExtension(force: true)
        let finderSync = FIFinderSyncController.default()
        var watchedURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            watchedURLs.formUnion(mountedVolumes)
        }
        finderSync.directoryURLs = watchedURLs

        // Monitor volumes
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { notification in
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                var urls = finderSync.directoryURLs ?? Set<URL>()
                urls.insert(volumeURL)
                finderSync.directoryURLs = urls
            }
        }
        notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { notification in
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                var urls = finderSync.directoryURLs ?? Set<URL>()
                urls.remove(volumeURL)
                finderSync.directoryURLs = urls
            }
        }
    }

    override var toolbarItemName: String {
        return NSLocalizedString("toolbar.item_name",
                                 comment: "Open in Terminal")
    }
    
    override var toolbarItemToolTip: String {
        return NSLocalizedString("toolbar.item_tooltip",
                                 comment: "Open current directory in Terminal.")
    }
    
    override var toolbarItemImage: NSImage {
        return NSImage(named: "Icon") ?? NSImage()
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        SharedPreferences.refreshExtension()
        var menu = NSMenu(title: "")
        
        switch menuKind {

        case .contextualMenuForContainer,
             .contextualMenuForItems,
             .contextualMenuForSidebar:
            // need to hide or not
            let isHideContextMenuItems = DefaultsManager.shared.isHideContextMenuItems
            guard !isHideContextMenuItems else { return NSMenu() }

            // the submenu grouping only applies to the Finder context menu
            let useSubmenu = DefaultsManager.shared.isContextMenuUseSubmenu

            // show custom menu or default
            let isCustomMenuApplyToContext = DefaultsManager.shared.isCustomMenuApplyToContext
            if isCustomMenuApplyToContext {
                menu = createCustomMenu(useSubmenu: useSubmenu)
            } else {
                menu = createDefaultMenu(useSubmenu: useSubmenu)
            }

        case .toolbarItemMenu:
            // the toolbar menu never groups items into a submenu
            let isCustomMenuApplyToToolbar = DefaultsManager.shared.isCustomMenuApplyToToolbar
            if isCustomMenuApplyToToolbar {
                menu = createCustomMenu(useSubmenu: false)
            } else {
                menu = createDefaultMenu(useSubmenu: false)
            }
            
        default:
            break
        }
        
        return menu
    }
    
    var scriptPath: URL? {
        return try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }

    func fileScriptPath(fileName: String) -> URL? {
        return scriptPath?
            .appendingPathComponent(fileName)
            .appendingPathExtension("scpt")
    }
    
    var copyPathItem: NSMenuItem {
        get {
            let copyPathItem = NSMenuItem(title: NSLocalizedString("menu.copy_path_to_clipboard",
                                                                   comment: "Copy path to Clipboard"),
                                                action: #selector(copyPathToClipboard),
                                                keyEquivalent: "")
            copyPathItem.target = self
            if DefaultsManager.shared.customMenuIconOption == .simple {
                let copyPathIcon = NSImage(named: "context_menu_icon_path")
                copyPathItem.image = copyPathIcon
            } else if DefaultsManager.shared.customMenuIconOption == .original {
                let copyPathIcon = NSImage(named: "context_menu_icon_color_path")
                copyPathItem.image = copyPathIcon
            }
            return copyPathItem
        }
    }
    
    /// Wraps the given items into a single "Open in..." submenu.
    func makeSubmenuItem(with itemsMenu: NSMenu) -> NSMenuItem {
        let submenuItem = NSMenuItem(title: NSLocalizedString("menu.submenu_title",
                                                              comment: "Open in..."),
                                     action: nil,
                                     keyEquivalent: "")
        submenuItem.submenu = itemsMenu
        return submenuItem
    }

    func createDefaultMenu(useSubmenu: Bool) -> NSMenu {
        let menu = NSMenu(title: "")

        // when submenu grouping is enabled, add the items into a separate
        // menu that will be attached under a single top level item
        let itemsMenu = useSubmenu ? NSMenu(title: "") : menu

        let terminal = DefaultsManager.shared.defaultTerminal ?? SupportedApps.terminal.app
        let terminalTitle = terminal.name
        let openInTerminalItem = NSMenuItem(title: terminalTitle,
                                            action: #selector(openDefaultTerminal),
                                            keyEquivalent: "")
        openInTerminalItem.target = self
        let terminalIcon = DefaultsManager.shared.getAppIcon(terminal)
        openInTerminalItem.image = terminalIcon
        itemsMenu.addItem(openInTerminalItem)

        let editor = DefaultsManager.shared.defaultEditor ?? SupportedApps.textEdit.app
        let editorTitle = editor.name
        let openInEditorItem = NSMenuItem(title: editorTitle,
                                            action: #selector(openDefaultEditor),
                                            keyEquivalent: "")
        openInEditorItem.target = self
        let editorIcon = DefaultsManager.shared.getAppIcon(editor)
        openInEditorItem.image = editorIcon
        itemsMenu.addItem(openInEditorItem)

        // add "Copy Path"
        itemsMenu.addItem(self.copyPathItem)

        // attach the items menu under a single top level item when needed
        if useSubmenu {
            menu.addItem(makeSubmenuItem(with: itemsMenu))
        }

        return menu
    }

    func createCustomMenu(useSubmenu: Bool) -> NSMenu {
        // Fall back to default menu if custom menu list is empty or not configured yet
        guard let customApps = DefaultsManager.shared.customMenuOptions, !customApps.isEmpty else {
            return createDefaultMenu(useSubmenu: useSubmenu)
        }

        let menu = NSMenu(title: "")

        // when submenu grouping is enabled, add the items into a separate
        // menu that will be attached under a single top level item
        let itemsMenu = useSubmenu ? NSMenu(title: "") : menu

        for (index, app) in customApps.enumerated() {
            let itemTitle = app.name
            let menuItem = NSMenuItem(title: itemTitle,
                                      action: #selector(customMenuItemClicked),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = index
            let appIcon = DefaultsManager.shared.getAppIcon(app)
            menuItem.image = appIcon
            itemsMenu.addItem(menuItem)
        }

        // add "Copy Path"
        itemsMenu.addItem(self.copyPathItem)

        // attach the items menu under a single top level item when needed
        if useSubmenu {
            menu.addItem(makeSubmenuItem(with: itemsMenu))
        }

        return menu
    }

    // MARK: - Actions
    
    func getSelectedPathsFromFinder() -> [URL] {
        var urls = [URL]()
        if let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty {
            urls.append(contentsOf: items)
        } else if let url = FIFinderSyncController.default().targetedURL() {
            urls.append(url)
        } else if let desktopPath = FinderManager.shared.getDesktopPath() {
            // Smart folders such as "Recents" report nil `targetedURL()`; fall back to Desktop
            urls.append(URL(fileURLWithPath: desktopPath, isDirectory: true))
        } else {
            urls.append(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        }
        return urls
    }
    
    func open(_ app: App) {
        let urls = getSelectedPathsFromFinder()
        do {
            try app.openInSandbox(urls)
        } catch {
            logw("Failed to open \(app.name) with \(urls)")
        }
    }
    
    // MARK: - Menu Actions
    
    @objc func openDefaultTerminal() {
        SharedPreferences.refreshExtension()
        let terminal = DefaultsManager.shared.defaultTerminal ?? SupportedApps.terminal.app
        open(terminal)
    }
    
    @objc func openDefaultEditor() {
        SharedPreferences.refreshExtension()
        let editor = DefaultsManager.shared.defaultEditor ?? SupportedApps.textEdit.app
        open(editor)
    }
    
    @objc func customMenuItemClicked(_ sender: NSMenuItem) {
        SharedPreferences.refreshExtension()
        guard let customApps = DefaultsManager.shared.customMenuOptions else { return }
        if sender.tag >= 0 && sender.tag < customApps.count,
           customApps[sender.tag].name == sender.title {
            open(customApps[sender.tag])
            return
        }
        let appName = sender.title
        for app in customApps where app.name == appName {
            open(app)
            break
        }
    }
    
    @objc func copyPathToClipboard() {
        SharedPreferences.refreshExtension()
        let urls = getSelectedPathsFromFinder().map { $0.resolvingFinderAlias() }
        var paths = urls.map { $0.path }
        if DefaultsManager.shared.isPathEscaped {
            paths = paths.map { $0.specialCharEscaped() }
        }
        let pathString = paths.joined(separator: "\n")
        // Set string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pathString, forType: .string)
    }
    
}

fileprivate extension String {
    
    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
         return String(self[start...])
    }
    
}
