//
//  Track.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/10/25.
//

import Foundation


struct Track: Identifiable, Equatable, Hashable {
    let id = UUID()
    var trackId: Int64?
    let url: URL
    
    // Core metadata for display
    var title: String
    var artist: String
    var album: String
    var duration: Double
    
    // File properties
    let format: String
    var folderId: Int64?
    
    // Navigation fields (for "Go to" functionality)
    var albumArtist: String?
    var composer: String
    var genre: String
    var year: String
    
    // User interaction state
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date?
    var rating: Int?
    
    // Sorting fields
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    
    // Additional metadata
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    
    // Sort fields
    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?
    
    // Audio properties
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    
    // File properties
    var fileSize: Int64?
    var dateModified: Date?
    
    // State tracking
    var isMetadataLoaded: Bool = false
    var isDuplicate: Bool = false
    var dateAdded: Date?
    var primaryTrackId: Int64?
    var duplicateGroupId: String?
    
    // Foreign key references to normalized entities
    var albumId: Int64?
    var artistId: Int64?
    var genreId: Int64?
    
    var artworkData: Data?
    private static var artworkCache = NSCache<NSString, NSData>()
    
    
    // Extended metadata stored as JSON
    var extendedMetadata: ExtendedMetadata?
    
    // R128 Loudness Analysis (for volume normalization)
    var r128IntegratedLoudness: Double? // in LUFS
    
    var filename: String {
        url.lastPathComponent
    }
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        
        // Default values - these will be overridden by metadata
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.composer = "Unknown Composer"
        self.genre = "Unknown Genre"
        self.year = "Unknown Year"
        self.duration = 0
        self.format = url.pathExtension
    }
    
    // MARK: - DB Configuration
    
    static let databaseTableName = "tracks"
    
    enum Columns {
        static let trackId = Column("id")
        static let folderId = Column("folder_id")
        static let path = Column("path")
        static let filename = Column("filename")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let rating = Column("rating")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let totalTracks = Column("total_tracks")
        static let discNumber = Column("disc_number")
        static let totalDiscs = Column("total_discs")
        static let compilation = Column("compilation")
        static let releaseDate = Column("release_date")
        static let originalReleaseDate = Column("original_release_date")
        static let bpm = Column("bpm")
        static let mediaType = Column("media_type")
        static let sortTitle = Column("sort_title")
        static let sortArtist = Column("sort_artist")
        static let sortAlbum = Column("sort_album")
        static let sortAlbumArtist = Column("sort_album_artist")
        static let bitrate = Column("bitrate")
        static let sampleRate = Column("sample_rate")
        static let channels = Column("channels")
        static let codec = Column("codec")
        static let bitDepth = Column("bit_depth")
        static let fileSize = Column("file_size")
        static let isDuplicate = Column("is_duplicate")
        static let primaryTrackId = Column("primary_track_id")
        static let duplicateGroupId = Column("duplicate_group_id")
        static let artworkData = Column("artwork_data")
        static let extendedMetadata = Column("extended_metadata")
        static let albumId = Column("album_id")
        static let artistId = Column("artist_id")
        static let genreId = Column("genre_id")
        static let r128IntegratedLoudness = Column("r128_integrated_loudness")
    }
    
    static let columnMap: [String: Column] = [
        "artist": Columns.artist,
        "album": Columns.album,
        "album_artist": Columns.albumArtist,
        "composer": Columns.composer,
        "genre": Columns.genre,
        "year": Columns.year
    ]
    

    
    // MARK: - PersistableRecord

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}



// MARK: - Helper Methods

extension Track {
    /// Get a display-friendly artist name
    var displayArtist: String {
        albumArtist ?? artist
    }
    
    /// Get formatted duration string
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if this track has album artwork
    var hasArtwork: Bool {
        artworkData != nil
    }
}

// MARK: - Update Helpers

extension Track {
    /// Create a copy with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> Track {
        var copy = self
        copy.isFavorite = isFavorite
        return copy
    }
    
    /// Create a copy with updated play stats
    func withPlayStats(playCount: Int, lastPlayedDate: Date?) -> Track {
        var copy = self
        copy.playCount = playCount
        copy.lastPlayedDate = lastPlayedDate
        return copy
    }
}

// MARK: - Duplicate Detection

extension Track {
    /// Generate a key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
}


// MARK: - Database Query Helpers

extension Track {
    /// Fetch only the columns needed for lightweight Track
    /// NOTE: Excludes artworkData to avoid loading large blobs into memory
    /// Use ArtworkCache to load artwork on-demand
    static var lightweightSelection: [Column] {
        [
            Columns.trackId,
            Columns.folderId,
            Columns.path,
            Columns.filename,
            Columns.title,
            Columns.artist,
            Columns.album,
            Columns.composer,
            Columns.genre,
            Columns.year,
            Columns.duration,
            Columns.format,
            Columns.dateAdded,
            Columns.dateModified,
            Columns.isFavorite,
            Columns.playCount,
            Columns.lastPlayedDate,
            Columns.trackNumber,
            Columns.discNumber,
            Columns.isDuplicate,
            Columns.fileSize,
            Columns.codec,
            Columns.albumId,
            Columns.artistId,
            Columns.r128IntegratedLoudness
        ]
    }
    
}
