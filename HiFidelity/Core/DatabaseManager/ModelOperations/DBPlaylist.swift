//
//  DBPlaylist.swift
//  HiFidelity
//
//  Database operations for playlists and smart playlists
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Get Tracks for Playlist
    
    func getTracksForPlaylist(playlistId: Int64) async throws -> [Track] {
        try await dbQueue.read { db in
            // Get playlist track entries
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position.asc)
                .fetchAll(db)
            
            // Get actual tracks
            var tracks: [Track] = []
            for playlistTrack in playlistTracks {
                if let track = try Track
                    .filter(Track.Columns.trackId == playlistTrack.trackId)
                    .fetchOne(db) {
                    tracks.append(track)
                }
            }
            
            return tracks
        }
    }
    
    // MARK: - Smart Playlists
    
    /// Get all favorite tracks
    func getFavoriteTracks() async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.isFavorite == true)
                .order(Track.Columns.dateAdded.desc)
                .fetchAll(db)
        }
    }
    
    /// Get top played tracks
    func getTopPlayedTracks(limit: Int = 25) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.playCount > 5)
                .order(Track.Columns.playCount.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Get recently played tracks
    func getRecentlyPlayedTracks(limit: Int = 25) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.lastPlayedDate != nil)
                .order(Track.Columns.lastPlayedDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // MARK: - Update Playlist
    
    func updatePlaylist(_ playlist: Playlist) async throws {
        try await dbQueue.write { db in
            let mutable = playlist
            try mutable.update(db)
        }
        
        Logger.info("Updated playlist: \(playlist.name)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }

    // MARK: - Create Playlist
    
    func createPlaylist(_ playlist: Playlist) async throws -> Playlist {
        let result = try await dbQueue.write { db in
            var mutable = playlist
            try mutable.insert(db)
            return mutable
        }
        
        Logger.info("Created playlist: \(result.name) with ID: \(result.id ?? -1)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
        
        return result
    }
    
    // MARK: - Delete Playlist
    
    func deletePlaylist(_ playlist: PlaylistItem) async throws {
        guard case .user(let playlistModel) = playlist.type else { return }
        
        let playlistId = playlistModel.id
        
        try await dbQueue.write { db in
            // Delete playlist tracks first (cascade)
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .deleteAll(db)
            
            // Delete playlist
            try Playlist
                .filter(Playlist.Columns.id == playlistId)
                .deleteAll(db)
        }
        
        Logger.info("Deleted playlist: \(playlist.name)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    // MARK: - Add Track to Playlist
    
    func addTrackToPlaylist(trackId: Int64, playlistId: Int64) async throws {
        try await dbQueue.write { db in
            // Check if track already exists in playlist
            let existingCount = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .fetchCount(db)
            
            if existingCount > 0 {
                Logger.info("Track \(trackId) already exists in playlist \(playlistId), skipping")
                throw DatabaseError.duplicateTrackInPlaylist
            }
            
            // Get current max position
            let maxPosition = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .select(max(PlaylistTrack.Columns.position))
                .fetchOne(db) ?? -1
            
            // Create playlist track entry
            var playlistTrack = PlaylistTrack(
                playlistId: playlistId,
                trackId: trackId,
                position: maxPosition + 1,
                dateAdded: Date()
            )
            
            try playlistTrack.insert(db)
            
            // Update playlist track count and duration
            if var playlist = try Playlist.fetchOne(db, id: playlistId),
               let track = try Track
                    .filter(Track.Columns.trackId == trackId)
                    .fetchOne(db) {
                playlist.trackCount += 1
                playlist.totalDuration += track.duration
                playlist.modifiedDate = Date()
                try playlist.update(db)
            }
        }
        
        Logger.info("Added track \(trackId) to playlist \(playlistId)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
    
    // MARK: - Remove Track from Playlist
    
    func removeTrackFromPlaylist(trackId: Int64, playlistId: Int64) async throws {
        try await dbQueue.write { db in
            // Delete playlist track entry
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .deleteAll(db)
            
            // Update playlist track count and duration
            
            if var playlist = try Playlist.fetchOne(db, id: playlistId),
               let track = try Track
                .filter(Track.Columns.trackId == trackId)
                .fetchOne(db) {
                playlist.trackCount = max(0, playlist.trackCount - 1)
                playlist.totalDuration = max(0, playlist.totalDuration - (track.duration))
                playlist.modifiedDate = Date()
                try playlist.update(db)
            }
            
            // Reorder positions
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position.asc)
                .fetchAll(db)
            
            for (index, var pt) in playlistTracks.enumerated() {
                pt.position = index
                try pt.update(db)
            }
        }
        
        Logger.info("Removed track \(trackId) from playlist \(playlistId)")
        
        // Post notification (cache will auto-invalidate via notification observer)
        await MainActor.run {
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }
    }
}

