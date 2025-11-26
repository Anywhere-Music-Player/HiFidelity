//
//  DBSearch.swift
//  HiFidelity
//
//  Full-text search operations across all entities
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Search Mode
    
    enum SearchMode {
        case or   // Match ANY word (broader results)
        case and  // Match ALL words (exact/strict results)
    }
    
    // MARK: - Unified Search Results
    
    struct SearchResults {
        var tracks: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var genres: [Genre] = []
        var playlists: [Playlist] = []
        
        var isEmpty: Bool {
            tracks.isEmpty && albums.isEmpty && artists.isEmpty && genres.isEmpty && playlists.isEmpty
        }
        
        var totalCount: Int {
            tracks.count + albums.count + artists.count + genres.count + playlists.count
        }
    }
    
    // MARK: - Full-Text Search (FTS5)
    
    /// Perform full-text search across all entities using FTS5
    /// - Parameters:
    ///   - query: Search query string (supports FTS5 syntax)
    ///   - limit: Maximum results per category (default: 50)
    ///   - mode: Search mode - .or (match any word) or .and (match all words)
    /// - Returns: SearchResults containing matches from all categories
    func search(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults()
        }
        
        // Prepare FTS5 query (escape special characters and add wildcards for prefix matching)
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            var results = SearchResults()
            
            // Search tracks using FTS5
            let trackIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM tracks_fts
                WHERE tracks_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            if !trackIds.isEmpty {
                results.tracks = try Track
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
            }
            
            // Search albums using FTS5
            let albumIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM albums_fts
                WHERE albums_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            if !albumIds.isEmpty {
                results.albums = try Album
                    .filter(albumIds.contains(Album.Columns.id))
                    .fetchAll(db)
            }
            
            // Search artists using FTS5
            let artistIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM artists_fts
                WHERE artists_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            if !artistIds.isEmpty {
                results.artists = try Artist
                    .filter(artistIds.contains(Artist.Columns.id))
                    .fetchAll(db)
            }
            
            // Search genres using FTS5
            let genreIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM genres_fts
                WHERE genres_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            if !genreIds.isEmpty {
                results.genres = try Genre
                    .filter(genreIds.contains(Genre.Columns.id))
                    .fetchAll(db)
            }
            
            // Search playlists using FTS5 (user playlists only)
            let playlistIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM playlists_fts
                WHERE playlists_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            if !playlistIds.isEmpty {
                results.playlists = try Playlist
                    .filter(playlistIds.contains(Playlist.Columns.id))
                    .filter(Playlist.Columns.isSmart == false)
                    .fetchAll(db)
            }
            
            return results
        }
    }
    
    /// Prepare query string for FTS5
    /// Escapes special characters and adds prefix matching
    /// - Parameters:
    ///   - query: Raw search query from user
    ///   - mode: Search mode - .or (match any word) or .and (match all words)
    /// - Returns: FTS5-formatted query string
    private func prepareFTSQuery(_ query: String, mode: SearchMode = .and) -> String {
        // Remove special FTS5 characters that can cause errors
        let sanitized = query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split into terms
        let terms = sanitized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        guard !terms.isEmpty else {
            // Return a safe default that won't match anything
            return "\"__no_match__\""
        }
        
        // For very short queries (less than 3 chars), be more careful
        let ftsTerms = terms.map { term -> String in
            if term.count < 3 {
                // For very short terms, use exact match or quoted prefix
                // This prevents FTS5 errors with ambiguous short prefixes
                return "\"\(term)\"*"
            } else {
                // For longer terms, use standard prefix matching
                return "\(term)*"
            }
        }
        
        // Join based on search mode
        switch mode {
        case .or:
            // Match ANY word (broader results)
            // Example: "tate mace" → "tate* OR mace*"
            return ftsTerms.joined(separator: " OR ")
        case .and:
            // Match ALL words (exact/strict results)
            // Example: "tate mace" → "tate* AND mace*"
            return ftsTerms.joined(separator: " AND ")
        }
    }
    
    // MARK: - Category-Specific Search (FTS5)
    
    /// Search tracks only using FTS5
    func searchTracks(query: String, limit: Int = 100, mode: SearchMode = .and) async throws -> [Track] {
        guard !query.isEmpty else { return [] }
        
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            let trackIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM tracks_fts
                WHERE tracks_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            guard !trackIds.isEmpty else { return [] }
            
            return try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .order(Track.Columns.title)
                .fetchAll(db)
        }
    }
    
    /// Search albums only using FTS5
    func searchAlbums(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Album] {
        guard !query.isEmpty else { return [] }
        
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            let albumIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM albums_fts
                WHERE albums_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            guard !albumIds.isEmpty else { return [] }
            
            return try Album
                .filter(albumIds.contains(Album.Columns.id))
                .order(Album.Columns.title)
                .fetchAll(db)
        }
    }
    
    /// Search artists only using FTS5
    func searchArtists(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Artist] {
        guard !query.isEmpty else { return [] }
        
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            let artistIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM artists_fts
                WHERE artists_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            guard !artistIds.isEmpty else { return [] }
            
            return try Artist
                .filter(artistIds.contains(Artist.Columns.id))
                .order(Artist.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Search genres only using FTS5
    func searchGenres(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Genre] {
        guard !query.isEmpty else { return [] }
        
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            let genreIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM genres_fts
                WHERE genres_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            guard !genreIds.isEmpty else { return [] }
            
            return try Genre
                .filter(genreIds.contains(Genre.Columns.id))
                .order(Genre.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Search playlists only using FTS5
    func searchPlaylists(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Playlist] {
        guard !query.isEmpty else { return [] }
        
        let ftsQuery = prepareFTSQuery(query, mode: mode)
        
        return try await dbQueue.read { db in
            let playlistIds = try Int64.fetchAll(db, sql: """
                SELECT id FROM playlists_fts
                WHERE playlists_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            
            guard !playlistIds.isEmpty else { return [] }
            
            return try Playlist
                .filter(playlistIds.contains(Playlist.Columns.id))
                .filter(Playlist.Columns.isSmart == false)
                .order(Playlist.Columns.name)
                .fetchAll(db)
        }
    }
}

