//
//  TrackContextMenu.swift
//  HiFidelity
//
//  Context menu for track operations
//

import SwiftUI
import AppKit

// MARK: - Track Context Menu

struct TrackContextMenu: View {
    let track: Track
    
    // Optional playlist context - if provided, shows "Remove from Playlist" option
    var playlistContext: PlaylistContext?
    
    @EnvironmentObject private var trackInfoManager: TrackInfoManager
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject private var cache = DatabaseCache.shared
    
    // Filter to only show user playlists (exclude smart playlists)
    private var userPlaylists: [Playlist] {
        cache.allPlaylists.filter { !$0.isSmart }
    }
    
    // MARK: - Playlist Context
    
    struct PlaylistContext {
        let playlist: PlaylistItem
        let onRemove: () -> Void
    }
    
    var body: some View {
        Group {
            // Playback actions
            Button("Play") {
                playback.playTracks([track], startingAt: 0)
            }
            
            Button("Play Next") {
                playback.playNext(track)
            }
            
            Button("Add to Queue") {
                playback.addToQueue(track)
            }
            
            Divider()
            
            // Playlist actions
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    appCoordinator.showCreatePlaylist(with: track)
                }
                
                if !userPlaylists.isEmpty {
                    Divider()
                    
                    ForEach(userPlaylists) { playlist in
                        Button(playlist.name) {
                            Task {
                                await addToPlaylist(playlist)
                            }
                        }
                    }
                } else {
                    Divider()
                    
                    Text("No playlists")
                        .foregroundColor(.secondary)
                }
            }
            
            // Remove from playlist (only shown in playlist context)
            if let context = playlistContext, !context.playlist.isSmart {
                Button("Remove from Playlist") {
                    Task {
                        await removeFromPlaylist(context)
                    }
                }
            }
            
            Divider()
            
            // File system actions
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            }
            
            Button("Get Info") {
                trackInfoManager.show(track: track)
            }
            
            Divider()
            
            // Favorite toggle
            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                Task {
                    await toggleFavorite()
                }
            }
        }
    }
    
    private func addToPlaylist(_ playlist: Playlist) async {
        guard let playlistId = playlist.id,
              let trackId = track.trackId else {
            return
        }
        
        do {
            try await DatabaseManager.shared.addTrackToPlaylist(trackId: trackId, playlistId: playlistId)
            Logger.info("Added '\(track.title)' to playlist '\(playlist.name)'")
            
            // Show success notification
            await MainActor.run {
                NotificationManager.shared.addMessage(.info, "'\(track.title)' was added to '\(playlist.name)'")
            }
        } catch DatabaseError.duplicateTrackInPlaylist {
            Logger.info("Track '\(track.title)' already exists in playlist '\(playlist.name)'")
            
            // Show info notification (not an error, just informational)
            await MainActor.run {
                NotificationManager.shared.addMessage(.warning, "'\(track.title)' is already in '\(playlist.name)'")
            }
        } catch {
            Logger.error("Failed to add track to playlist: \(error)")
            
            // Show error notification
            await MainActor.run {
                NotificationManager.shared.addMessage(.error, "Failed to add track to playlist")
            }
        }
    }
    
    private func toggleFavorite() async {
        var updatedTrack = track
        updatedTrack.isFavorite.toggle()
        
        do {
            try await DatabaseManager.shared.updateTrackFavoriteStatus(updatedTrack)
            Logger.info("Updated favorite status for: \(track.title)")
        } catch {
            Logger.error("Failed to update favorite: \(error)")
        }
    }
    
    private func removeFromPlaylist(_ context: PlaylistContext) async {
        guard case .user(let playlist) = context.playlist.type,
              let playlistId = playlist.id,
              let trackId = track.trackId else {
            return
        }
        
        do {
            try await DatabaseManager.shared.removeTrackFromPlaylist(trackId: trackId, playlistId: playlistId)
            Logger.info("Removed '\(track.title)' from playlist '\(context.playlist.name)'")
            
            // Show success notification
            await MainActor.run {
                NotificationManager.shared.addMessage(.info, "'\(track.title)' was removed from '\(context.playlist.name)'")
            }
            
            // Trigger the callback to refresh the view
            await MainActor.run {
                context.onRemove()
            }
        } catch {
            Logger.error("Failed to remove track from playlist: \(error)")
            
            // Show error notification
            await MainActor.run {
                NotificationManager.shared.addMessage(.error, "Failed to remove track from playlist")
            }
        }
    }
    
}

// MARK: - Create Playlist With Track View

struct CreatePlaylistWithTrackView: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        CreatePlaylistView()
            .onReceive(NotificationCenter.default.publisher(for: .playlistCreated)) { notification in
                // Auto-add track to newly created playlist
                if let playlist = notification.object as? Playlist,
                   let playlistId = playlist.id,
                   let trackId = track.trackId {
                    Task {
                        try? await DatabaseManager.shared.addTrackToPlaylist(trackId: trackId, playlistId: playlistId)
                    }
                }
                dismiss()
            }
    }
}

