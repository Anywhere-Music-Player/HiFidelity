//
//  ArtworkCache.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import Foundation
import AppKit
import GRDB

// MARK: - Artwork Cache

/// High-performance artwork cache with downsampling and prefetching
class ArtworkCache {
    // MARK: - Singleton
    static let shared = ArtworkCache()
    
    // MARK: - Cache Storage
    
    // Separate caches for different sizes to optimize memory usage
    private let thumbnailCache = NSCache<NSString, NSImage>()  // Small images for lists
    private let fullSizeCache = NSCache<NSString, NSImage>()   // Full size for detail views
    static let thumbnailImageSize: CGFloat = 40
    static let fullSizeImageSize: CGFloat = 160
    
    // Track IDs known to have no artwork (to avoid repeated DB queries)
    private let noArtworkSet = NSMutableSet()
    private let noArtworkQueue = DispatchQueue(label: "com.hifidelity.noArtworkSet", attributes: .concurrent)
    
    // Concurrent queue for image decoding (CPU-intensive)
    private let decodingQueue = DispatchQueue(label: "com.hifidelity.imageDecoding", qos: .userInitiated, attributes: .concurrent)
    
    // Serial queue for database operations
    private let dbQueue = DispatchQueue(label: "com.hifidelity.artworkCache", qos: .userInitiated)
    
    // Track in-flight requests to avoid duplicate loads
    private var inflightRequests = Set<String>()
    private let inflightQueue = DispatchQueue(label: "com.hifidelity.inflightRequests")
    
    // MARK: - Configuration
    
    private init() {
        // Load user's cache size preference (default 500 MB)
        let userCacheSizeMB = UserDefaults.standard.object(forKey: "artworkCacheSize") as? Int ?? 500
        configureCacheSize(sizeMB: userCacheSizeMB)
    }
    
    /// Update cache size limits dynamically
    /// - Parameter sizeMB: Total cache size in megabytes (minimum 100 MB)
    func updateCacheSize(sizeMB: Int) {
        let safeSizeMB = max(100, sizeMB)
        UserDefaults.standard.set(safeSizeMB, forKey: "artworkCacheSize")
        configureCacheSize(sizeMB: safeSizeMB)
        Logger.info("Updated artwork cache size to \(safeSizeMB) MB")
    }
    
    private func configureCacheSize(sizeMB: Int) {
        let totalBytes = sizeMB * 1024 * 1024
        
        // Allocate 40% to thumbnails, 60% to full-size images
        let thumbnailBytes = Int(Double(totalBytes) * 0.4)
        let fullSizeBytes = Int(Double(totalBytes) * 0.6)
        
        // Configure thumbnail cache (small images for grid/list views)
        thumbnailCache.countLimit = sizeMB * 2 // Roughly 2 thumbnails per MB
        thumbnailCache.totalCostLimit = thumbnailBytes
        thumbnailCache.name = "ArtworkThumbnailCache"
        
        // Configure full-size cache (detail views)
        fullSizeCache.countLimit = sizeMB / 2 // Roughly 1 full-size image per 2 MB
        fullSizeCache.totalCostLimit = fullSizeBytes
        fullSizeCache.name = "ArtworkFullSizeCache"
    }
    
    // MARK: - Public API
    
    /// Get artwork image for a track with fallback chain: album -> track -> nil
    /// Optimized with downsampling, prefetch deduplication, and off-main-thread decoding
    func getArtwork(for trackId: Int64, size: CGFloat = thumbnailImageSize, completion: @escaping (NSImage?) -> Void) {
        let trackKey = "track_\(trackId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        
        // Check appropriate cache first (extremely fast, thread-safe)
        if let cachedImage = cache.object(forKey: trackKey) {
            completion(cachedImage)
            return
        }
        
        // OPTIMIZATION: Check if we can get albumId from DatabaseCache
        if let cachedTrack = DatabaseCache.shared.track(trackId),
           let albumId = cachedTrack.albumId {
            let albumKey = "album_\(albumId)_\(Int(size))" as NSString
            if let albumArtwork = cache.object(forKey: albumKey) {
                // Found album artwork in cache! Use it for this track too
                let cost = calculateImageCost(albumArtwork)
                cache.setObject(albumArtwork, forKey: trackKey, cost: cost)
                completion(albumArtwork)
                return
            }
        }
        
        // Thread-safe check if we know this track has no artwork
        let noArtworkKey = "track_\(trackId)" as NSString
        var hasNoArtwork = false
        noArtworkQueue.sync {
            hasNoArtwork = noArtworkSet.contains(noArtworkKey)
        }
        
        if hasNoArtwork {
            completion(nil)
            return
        }
        
        // Check if already loading this image
        let requestKey = "track_\(trackId)_\(Int(size))"
        var isInflight = false
        inflightQueue.sync {
            isInflight = inflightRequests.contains(requestKey)
            if !isInflight {
                inflightRequests.insert(requestKey)
            }
        }
        
        if isInflight {
            // Already loading, just wait and check cache again shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if let cached = self?.cache(for: size).object(forKey: trackKey) {
                    completion(cached)
                } else {
                    completion(nil)
                }
            }
            return
        }
        
        // Load from database on background queue
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                _ = self.inflightQueue.sync {
                    self.inflightRequests.remove(requestKey)
                }
            }
            
            // Double-check cache
            if let cachedImage = cache.object(forKey: trackKey) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }
            
            // Load and decode artwork
            do {
                guard let result = try self.loadTrackArtworkWithFallback(trackId: trackId) else {
                    // Track exists but has no artwork
                    self.noArtworkQueue.async(flags: .barrier) {
                        self.noArtworkSet.add(noArtworkKey)
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Decode and downsample image OFF main thread
                self.decodingQueue.async {
                    guard let image = self.downsampleImage(data: result.data, targetSize: size) else {
                        self.noArtworkQueue.async(flags: .barrier) {
                            self.noArtworkSet.add(noArtworkKey)
                        }
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Cache the downsampled image
                    let cost = self.calculateImageCost(image)
                    cache.setObject(image, forKey: trackKey, cost: cost)
                
                // OPTIMIZATION: If artwork came from album, also cache under album key
                if let albumId = result.albumId {
                        let albumKey = "album_\(albumId)_\(Int(size))" as NSString
                        cache.setObject(image, forKey: albumKey, cost: cost)
                }
                
                // Return on main thread
                DispatchQueue.main.async {
                    completion(image)
                    }
                }
            } catch {
                Logger.warning("Failed to load artwork for track \(trackId): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    /// Get artwork for an album with downsampling
    func getAlbumArtwork(for albumId: Int64, size: CGFloat = 160, completion: @escaping (NSImage?) -> Void) {
        let key = "album_\(albumId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        
        // Check cache first
        if let cachedImage = cache.object(forKey: key) {
            completion(cachedImage)
            return
        }
        
        // Thread-safe check if we know this album has no artwork
        let noArtworkKey = "album_\(albumId)" as NSString
        var hasNoArtwork = false
        noArtworkQueue.sync {
            hasNoArtwork = noArtworkSet.contains(noArtworkKey)
        }
        
        if hasNoArtwork {
            completion(nil)
            return
        }
        
        // Check if already loading
        let requestKey = "album_\(albumId)_\(Int(size))"
        var isInflight = false
        inflightQueue.sync {
            isInflight = inflightRequests.contains(requestKey)
            if !isInflight {
                inflightRequests.insert(requestKey)
            }
        }
        
        if isInflight {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if let cached = self?.cache(for: size).object(forKey: key) {
                    completion(cached)
                } else {
                    completion(nil)
                }
            }
            return
        }
        
        // Load from database on background queue
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                _ = self.inflightQueue.sync {
                    self.inflightRequests.remove(requestKey)
                }
            }
            
            // Double-check cache
            if let cachedImage = cache.object(forKey: key) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }
            
            // Load and decode artwork
            do {
                guard let artworkData = try self.loadAlbumArtworkWithFallback(albumId: albumId),
                      !artworkData.isEmpty else {
                    self.noArtworkQueue.async(flags: .barrier) {
                        self.noArtworkSet.add(noArtworkKey)
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Decode and downsample OFF main thread
                self.decodingQueue.async {
                    guard let image = self.downsampleImage(data: artworkData, targetSize: size) else {
                        self.noArtworkQueue.async(flags: .barrier) {
                            self.noArtworkSet.add(noArtworkKey)
                        }
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Cache the downsampled image
                    let cost = self.calculateImageCost(image)
                    cache.setObject(image, forKey: key, cost: cost)
                
                DispatchQueue.main.async {
                    completion(image)
                    }
                }
            } catch {
                Logger.warning("Failed to load artwork for album \(albumId): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    /// Get artwork for an artist with downsampling
    func getArtistArtwork(for artistId: Int64, size: CGFloat = 160, completion: @escaping (NSImage?) -> Void) {
        let key = "artist_\(artistId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        
        // Check cache first
        if let cachedImage = cache.object(forKey: key) {
            completion(cachedImage)
            return
        }
        
        // Thread-safe check if we know this artist has no artwork
        let noArtworkKey = "artist_\(artistId)" as NSString
        var hasNoArtwork = false
        noArtworkQueue.sync {
            hasNoArtwork = noArtworkSet.contains(noArtworkKey)
        }
        
        if hasNoArtwork {
            completion(nil)
            return
        }
        
        // Check if already loading
        let requestKey = "artist_\(artistId)_\(Int(size))"
        var isInflight = false
        inflightQueue.sync {
            isInflight = inflightRequests.contains(requestKey)
            if !isInflight {
                inflightRequests.insert(requestKey)
            }
        }
        
        if isInflight {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if let cached = self?.cache(for: size).object(forKey: key) {
                    completion(cached)
                } else {
                    completion(nil)
                }
            }
            return
        }
        
        // Load from database on background queue
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                _ = self.inflightQueue.sync {
                    self.inflightRequests.remove(requestKey)
                }
            }
            
            // Double-check cache
            if let cachedImage = cache.object(forKey: key) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }
            
            // Load and decode artwork
            do {
                guard let artworkData = try self.loadArtistArtworkWithFallback(artistId: artistId),
                      !artworkData.isEmpty else {
                    self.noArtworkQueue.async(flags: .barrier) {
                        self.noArtworkSet.add(noArtworkKey)
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Decode and downsample OFF main thread
                self.decodingQueue.async {
                    guard let image = self.downsampleImage(data: artworkData, targetSize: size) else {
                        self.noArtworkQueue.async(flags: .barrier) {
                            self.noArtworkSet.add(noArtworkKey)
                        }
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Cache the downsampled image
                    let cost = self.calculateImageCost(image)
                    cache.setObject(image, forKey: key, cost: cost)
                
                DispatchQueue.main.async {
                    completion(image)
                    }
                }
            } catch {
                Logger.warning("Failed to load artwork for artist \(artistId): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    /// Synchronous version for when you already know the image should be cached
    func getCachedArtwork(for trackId: Int64, size: CGFloat = 40) -> NSImage? {
        let key = "track_\(trackId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        return cache.object(forKey: key)
    }
    
    func getCachedAlbumArtwork(for albumId: Int64, size: CGFloat = 160) -> NSImage? {
        let key = "album_\(albumId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        return cache.object(forKey: key)
    }
    
    func getCachedArtistArtwork(for artistId: Int64, size: CGFloat = 160) -> NSImage? {
        let key = "artist_\(artistId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        return cache.object(forKey: key)
    }
    
    /// Preload artwork for visible tracks (call from ScrollView)
    /// Limits concurrent loads to prevent overwhelming the system
    func preloadArtwork(for trackIds: [Int64], size: CGFloat = 40, maxConcurrent: Int = 10) {
        let uncached = trackIds.filter { trackId in
            let key = "track_\(trackId)_\(Int(size))" as NSString
            let cache = size <= 200 ? thumbnailCache : fullSizeCache
            
            if cache.object(forKey: key) != nil {
                return false
            }
            
            // Thread-safe check
            let noArtworkKey = "track_\(trackId)" as NSString
            var hasNoArtwork = false
            noArtworkQueue.sync {
                hasNoArtwork = noArtworkSet.contains(noArtworkKey)
            }
            return !hasNoArtwork
        }
        
        // Limit to prevent too many concurrent loads
        let limited = Array(uncached.prefix(maxConcurrent))
        
        for trackId in limited {
            getArtwork(for: trackId, size: size) { _ in }
        }

    }
    
    /// Preload artwork for albums (call from grid views)
    func preloadAlbumArtwork(for albumIds: [Int64], size: CGFloat = 160, maxConcurrent: Int = 10) {
        let uncached = albumIds.filter { albumId in
            let key = "album_\(albumId)_\(Int(size))" as NSString
            let cache = size <= 200 ? thumbnailCache : fullSizeCache
            
            if cache.object(forKey: key) != nil {
                return false
            }
            
            let noArtworkKey = "album_\(albumId)" as NSString
            var hasNoArtwork = false
            noArtworkQueue.sync {
                hasNoArtwork = noArtworkSet.contains(noArtworkKey)
            }
            return !hasNoArtwork
        }
        
        let limited = Array(uncached.prefix(maxConcurrent))
        
        for albumId in limited {
            getAlbumArtwork(for: albumId, size: size) { _ in }
        }
    }
    
    /// Clear specific track's artwork (when updated)
    func invalidate(trackId: Int64) {
        // Remove all size variants
        for size in [40, 56, 140, 160, 200, 300] {
            let key = "track_\(trackId)_\(size)" as NSString
            thumbnailCache.removeObject(forKey: key)
            fullSizeCache.removeObject(forKey: key)
        }
        
        // Thread-safe removal from no-artwork set
        let noArtworkKey = "track_\(trackId)" as NSString
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.remove(noArtworkKey)
        }
    }
    
    /// Clear specific album's artwork (when updated)
    func invalidateAlbum(albumId: Int64) {
        // Remove all size variants
        for size in [40, 56, 140, 160, 200, 300] {
            let key = "album_\(albumId)_\(size)" as NSString
            thumbnailCache.removeObject(forKey: key)
            fullSizeCache.removeObject(forKey: key)
        }
        
        let noArtworkKey = "album_\(albumId)" as NSString
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.remove(noArtworkKey)
        }
    }
    
    /// Clear specific artist's artwork (when updated)
    func invalidateArtist(artistId: Int64) {
        // Remove all size variants
        for size in [40, 56, 140, 160, 200, 300] {
            let key = "artist_\(artistId)_\(size)" as NSString
            thumbnailCache.removeObject(forKey: key)
            fullSizeCache.removeObject(forKey: key)
        }
        
        let noArtworkKey = "artist_\(artistId)" as NSString
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.remove(noArtworkKey)
        }
    }
    
    /// Clear all cached artwork
    func clearAll() {
        thumbnailCache.removeAllObjects()
        fullSizeCache.removeAllObjects()
        
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.removeAllObjects()
        }
        
        inflightQueue.sync {
            inflightRequests.removeAll()
        }
        
        Logger.info("Cleared all artwork cache")
    }
    
    /// Get cache statistics
    func getStats() -> ArtworkCacheStats {
        ArtworkCacheStats(
            thumbnailCount: thumbnailCache.countLimit,
            thumbnailCost: thumbnailCache.totalCostLimit,
            fullSizeCount: fullSizeCache.countLimit,
            fullSizeCost: fullSizeCache.totalCostLimit,
            noArtworkCount: noArtworkSet.count
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Get the appropriate cache for a given size
    private func cache(for size: CGFloat) -> NSCache<NSString, NSImage> {
        size <= 200 ? thumbnailCache : fullSizeCache
    }
    
    /// Downsample image to target size for memory efficiency
    /// Uses high-quality Lanczos resampling for best visual quality
    private func downsampleImage(data: Data, targetSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        // Get original image dimensions
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = imageProperties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = imageProperties[kCGImagePropertyPixelHeight] as? CGFloat else {
            // Fallback to regular decoding if we can't get properties
            return NSImage(data: data)
        }
        
        // Calculate actual scale needed (use 2x for Retina displays)
        let scale: CGFloat = 2.0
        let maxDimension = max(pixelWidth, pixelHeight)
        let targetPixelSize = targetSize * scale
        
        // Only downsample if source is significantly larger
        if maxDimension <= targetPixelSize * 1.5 {
            // Image is already small enough, just decode it
            return NSImage(data: data)
        }
        
        // Create thumbnail with downsampling
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize,
            kCGImageSourceShouldCache: false  // We're doing our own caching
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback to regular decoding
            return NSImage(data: data)
        }
        
        // Convert CGImage to NSImage
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)
        
        return image
    }
    
    /// Calculate memory cost for an image
    private func calculateImageCost(_ image: NSImage) -> Int {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        // 4 bytes per pixel (RGBA)
        return width * height * 4
    }
    
    // MARK: - Private Methods (Fallback Chain Logic)
    
    /// Result type that includes album ID for cache optimization
    private struct TrackArtworkResult {
        let data: Data
        let albumId: Int64?  // Set if artwork came from album
    }
    
    /// Load track artwork with fallback: album artwork -> track artwork
    /// Returns both artwork data and album ID for efficient cross-caching
    /// OPTIMIZED: Uses DatabaseCache to get albumId when available (avoids extra query)
    private func loadTrackArtworkWithFallback(trackId: Int64) throws -> TrackArtworkResult? {
        // OPTIMIZATION: Try to get albumId from DatabaseCache first (zero DB queries!)
        let cachedAlbumId = DatabaseCache.shared.track(trackId)?.albumId
        
        return try DatabaseManager.shared.dbQueue.read { db in
            var trackArtwork: Data?
            var albumId: Int64? = cachedAlbumId
            
            // If we don't have albumId from cache, query database
            if albumId == nil {
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT artwork_data, album_id
                    FROM tracks
                    WHERE id = ?
                    LIMIT 1
                    """, arguments: [trackId]) else {
                    return nil
                }
                trackArtwork = row["artwork_data"]
                albumId = row["album_id"]
            }
            
            // Try album artwork from database (most tracks use album artwork)
            if let albumId = albumId {
                if let row = try Row.fetchOne(db, sql: """
                    SELECT artwork_data
                    FROM albums
                    WHERE id = ?
                    LIMIT 1
                    """, arguments: [albumId]),
                   let albumArtwork = row["artwork_data"] as Data?,
                   !albumArtwork.isEmpty {
                    return TrackArtworkResult(data: albumArtwork, albumId: albumId)
                }
            }
            
            // If we haven't loaded track artwork yet, do it now
            if trackArtwork == nil {
                if let row = try Row.fetchOne(db, sql: """
                    SELECT artwork_data
                    FROM tracks
                    WHERE id = ?
                    LIMIT 1
                    """, arguments: [trackId]) {
                    trackArtwork = row["artwork_data"]
                }
            }
            
            // Fallback to track-specific artwork
            if let trackArtwork = trackArtwork, !trackArtwork.isEmpty {
                return TrackArtworkResult(data: trackArtwork, albumId: nil)
            }
            
            return nil
        }
    }
    
    /// Load album artwork with fallback: album artwork -> first track in album
    private func loadAlbumArtworkWithFallback(albumId: Int64) throws -> Data? {
        try DatabaseManager.shared.dbQueue.read { db in
            // Try album artwork first - use Row to avoid column requirement issues
            if let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM albums
                WHERE id = ?
                LIMIT 1
                """, arguments: [albumId]),
               let albumArtwork = row["artwork_data"] as Data?,
               !albumArtwork.isEmpty {
                return albumArtwork
            }
            
            // Fallback: get artwork from first track in album
            if let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM tracks
                WHERE album_id = ? AND artwork_data IS NOT NULL
                LIMIT 1
                """, arguments: [albumId]),
               let trackArtwork = row["artwork_data"] as Data? {
                return trackArtwork
            }
            
            return nil
        }
    }
    
    /// Load artist artwork with fallback: artist artwork -> album artwork -> track artwork
    private func loadArtistArtworkWithFallback(artistId: Int64) throws -> Data? {
        try DatabaseManager.shared.dbQueue.read { db in
            // First, try artist's own artwork - use Row to avoid column requirement issues
            if let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM artists
                WHERE id = ?
                LIMIT 1
                """, arguments: [artistId]),
               let artistArtwork = row["artwork_data"] as Data?,
               !artistArtwork.isEmpty {
                return artistArtwork
            }
            
            return nil
        }
    }
    
}

// MARK: - Artwork Cache Statistics

struct ArtworkCacheStats {
    let thumbnailCount: Int
    let thumbnailCost: Int
    let fullSizeCount: Int
    let fullSizeCost: Int
    let noArtworkCount: Int
    
    var description: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .memory
        
        let thumbnailMemory = formatter.string(fromByteCount: Int64(thumbnailCost))
        let fullSizeMemory = formatter.string(fromByteCount: Int64(fullSizeCost))
        let totalMemory = formatter.string(fromByteCount: Int64(thumbnailCost + fullSizeCost))
        
        return """
        Artwork Cache Statistics:
        - Thumbnail Cache: \(thumbnailCount) images, \(thumbnailMemory) limit
        - Full-Size Cache: \(fullSizeCount) images, \(fullSizeMemory) limit
        - Total Memory Limit: \(totalMemory)
        - Items Without Artwork: \(noArtworkCount)
        """
    }
}

// MARK: - SwiftUI Image View

import SwiftUI

/// High-performance SwiftUI view for displaying track artwork
/// Optimized with size-specific caching and prefetching
struct TrackArtworkView: View, Equatable {
    let track: Track
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(track: Track, size: CGFloat = 40, cornerRadius: CGFloat = 4) {
        self.track = track
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: TrackArtworkView, rhs: TrackArtworkView) -> Bool {
        lhs.track.trackId == rhs.track.trackId &&
        lhs.size == rhs.size &&
        lhs.cornerRadius == rhs.cornerRadius
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: track.trackId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
    
    private func loadArtwork() async {
        guard let trackId = track.trackId else {
            artwork = nil
            return
        }
        
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedArtwork(for: trackId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
        
        await withCheckedContinuation { continuation in
                ArtworkCache.shared.getArtwork(for: trackId, size: size) { image in
                Task { @MainActor in
                        guard !Task.isCancelled,
                              self.track.trackId == trackId else {
                            continuation.resume()
                            return
                        }
                        self.artwork = image
                    continuation.resume()
                }
            }
        }
        }
        
        await loadTask?.value
    }
}

/// High-performance SwiftUI view for displaying album artwork
struct AlbumArtworkView: View, Equatable {
    let albumId: Int64
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(albumId: Int64, size: CGFloat = 160, cornerRadius: CGFloat = 8) {
        self.albumId = albumId
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: AlbumArtworkView, rhs: AlbumArtworkView) -> Bool {
        lhs.albumId == rhs.albumId &&
        lhs.size == rhs.size &&
        lhs.cornerRadius == rhs.cornerRadius
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: albumId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundColor(.white)
        }
    }
    
    private func loadArtwork() async {
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedAlbumArtwork(for: albumId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
        
        await withCheckedContinuation { continuation in
                ArtworkCache.shared.getAlbumArtwork(for: albumId, size: size) { image in
                Task { @MainActor in
                        guard !Task.isCancelled else {
                            continuation.resume()
                            return
                        }
                    self.artwork = image
                    continuation.resume()
                }
            }
        }
        }
        
        await loadTask?.value
    }
}

/// High-performance SwiftUI view for displaying artist artwork (circular)
struct ArtistArtworkView: View, Equatable {
    let artistId: Int64
    let size: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(artistId: Int64, size: CGFloat = 160) {
        self.artistId = artistId
        self.size = size
    }
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: ArtistArtworkView, rhs: ArtistArtworkView) -> Bool {
        lhs.artistId == rhs.artistId &&
        lhs.size == rhs.size
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artistId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundColor(.white)
        }
    }
    
    private func loadArtwork() async {
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedArtistArtwork(for: artistId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
        
        await withCheckedContinuation { continuation in
                ArtworkCache.shared.getArtistArtwork(for: artistId, size: size) { image in
                Task { @MainActor in
                        guard !Task.isCancelled else {
                            continuation.resume()
                            return
                        }
                    self.artwork = image
                    continuation.resume()
                }
            }
        }
        }
        
        await loadTask?.value
    }
}

