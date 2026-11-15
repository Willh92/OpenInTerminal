//
//  AppDelegate.swift
//  OpenInTerminalHelper
//
//  Created by Jianing Wang on 2019/5/5.
//  Copyright © 2019 Jianing Wang. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    public func applicationDidFinishLaunching(_ aNotification: Notification) {
        let mainAppIdentifier = "wang.jianing.app.OpenInTerminal"
        let alreadyRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == mainAppIdentifier
        }
        
        if !alreadyRunning {
            LaunchNotifier.addObserver(observer: NSApp,
                                       selector: #selector(NSApplication.terminate(_:)),
                                       notification: .terminateApp,
                                       object: mainAppIdentifier)
            
            // .../OpenInTerminal.app/Contents/Library/LoginItems/OpenInTerminalHelper.app -> .../OpenInTerminal.app
            let mainAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: mainAppURL, configuration: config) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        } else {
            NSApp.terminate(self)
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("helper app terminated")
    }


}

