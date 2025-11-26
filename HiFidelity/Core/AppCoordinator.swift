//
//  AppCoordinator.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/10/25.
//

import SwiftUI

class AppCoordinator: ObservableObject {
    private(set) static var shared: AppCoordinator?
    
    // Security-scoped bookmark manager
    let bookmarkManager = SecurityScopedBookmarkManager()
    
    // Sheet presentation
    @Published var showCreatePlaylist = false
    @Published var trackForNewPlaylist: Track?
    
    init() {
        Self.shared = self
    }
    
    // MARK: - Lifecycle Management
    
    /// Initialize security scopes and load library
    func initializeApp() async {
        Logger.info("Initializing HiFidelity application...")
        
        // Initialize security-scoped bookmarks for all folders
        await bookmarkManager.initializeSecurityScopes()
        
        // Start queue persistence manager
        await QueuePersistenceManager.shared.start()
        
        Logger.info("Application initialization complete")
    }
    
    /// Cleanup on app termination
    func cleanup() async {
        Logger.info("Cleaning up application resources...")
        
        // Stop queue persistence and save final state
        await QueuePersistenceManager.shared.stop()
        
        // Release all security-scoped resources
        await bookmarkManager.stopAccessingAllFolders()
        
        Logger.info("Application cleanup complete")
    }
    
    // MARK: - Sheet Presentation
    
    /// Show create playlist sheet with optional track to add
    func showCreatePlaylist(with track: Track? = nil) {
        trackForNewPlaylist = track
        showCreatePlaylist = true
    }
}
