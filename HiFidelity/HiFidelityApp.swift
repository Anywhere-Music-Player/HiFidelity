//
//  HiFidelityApp.swift
//  HiFidelity
//
//  Created by Varun Rathod on 21/10/25.
//

import SwiftUI
import SwiftData
import AppKit

/// Main SwiftUI App entry point for HiFidelity
/// AppDelegate is defined in Core/AppDelegate.swift
@main
struct HiFidelityApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
 
            
    
        }
        .commands {
            // Playback Control Commands
            playbackCommands()
            
            // App Menu Commands
            appMenuCommands()
            
            // View Menu Commands
            viewMenuCommands()
            
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)

        
        equalizerWindowContentView()
        
    }
    
    init() {
        // Install crash handlers and configure logger
        Logger.installCrashHandler()
        
        #if DEBUG
        Logger.setMinimumLogLevel(.debug)
        #else
        Logger.setMinimumLogLevel(.info)
        #endif
        
        Logger.info("HiFidelity SwiftUI app initialized")

    }
    
    // MARK: - Window Configuration
    
    private func configureWindow() {
        // Configure window for custom title bar with native controls
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            
            // Set toolbar background for better contrast
            window.toolbar?.insertItem(withItemIdentifier: .init("separator"), at: 0)
            
            // Configure toolbar appearance
            if let toolbar = window.toolbar {
                toolbar.displayMode = .iconOnly
            }
        }
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            Logger.debug("Scene entered background")
            // Save queue when app goes to background
            Task {
              
            }
        case .inactive:
            Logger.debug("Scene became inactive")
        case .active:
            Logger.debug("Scene became active")
        @unknown default:
            break
        }
    }
    
    private func equalizerWindowContentView() -> some Scene {
        // Separate window for Equalizer (single instance only)
        Window("Equalizer", id: "audio-effects") {
    
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    
    @CommandsBuilder
    private func appMenuCommands() -> some Commands {
        CommandGroup(replacing: .appSettings) {}
        
        CommandGroup(replacing: .appInfo) {

        }
        
        CommandGroup(after: .appInfo) {
            Divider()
            checkForUpdatesMenuItem()
        }
    }
    
    // MARK: - View Menu Commands
    
    @CommandsBuilder
    private func viewMenuCommands() -> some Commands {
        CommandGroup(after: .toolbar) {
            miniPlayerCommand()
            audioEffects()
//            visualEffects()
        }
    }
    
    private func checkForUpdatesMenuItem() -> some View {
        Button {
    
        } label: {
            Text("Check for Updates...")
        }
    }
    
    
    
//    private func visualEffects() -> some View {
//        Menu("Visualizer") {
//            Button("Toggle Visualizer") {
//                openWindow(id: "visualizer")
//            }
//            .keyboardShortcut("v", modifiers: .command)
//        }
//    }
    
    private func miniPlayerCommand() -> some View {
        Button {
           
        } label: {
            Text("Mini Player")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
    
    private func audioEffects() -> some View {
        Button {
            openWindow(id: "audio-effects")
        } label: {
            Text("Equalizer")
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
    }
    
    // MARK: - Playback Commands
    
    @CommandsBuilder
    private func playbackCommands() -> some Commands {
   
    }

}
