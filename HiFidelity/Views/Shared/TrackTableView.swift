//
//  TrackTableView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Optimized table view for displaying tracks with sortable columns
struct TrackTableView: View {
    let tracks: [Track]
    @Binding var selection: Track.ID?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    let onPlayTrack: (Track) -> Void
    let isCurrentTrack: (Track) -> Bool
    
    // Optional playlist context
    var playlistContext: TrackContextMenu.PlaylistContext?
    
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var playback = PlaybackController.shared
    
    // Column customization for right-click menu
    @State private var columnCustomization: TableColumnCustomization<Track> = {
        if let data = UserDefaults.standard.data(forKey: "trackTableColumnCustomizationData"),
           !data.isEmpty,
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<Track>.self, from: data) {
            return decoded
        }
        return TableColumnCustomization<Track>()
    }()
    
    @AppStorage("trackTableColumnCustomizationData")
    private var columnCustomizationData = Data()
    
    var body: some View {
        Table(tracks, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Title with Artwork
            TableColumn("Title", value: \.title) { track in
                titleCell(for: track)
                    .onAppear {
                        // Prefetch artwork for nearby tracks
                        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                            prefetchArtwork(startingAt: index)
                        }
                    }
            }
            .width(min: 200, ideal: 300, max: 500)
            .customizationID("title")
            .defaultVisibility(.visible)
            
            // Artist
            TableColumn("Artist", value: \.artist) { track in
                textCell(text: track.artist)
            }
            .width(min: 100, ideal: 180, max: 300)
            .customizationID("artist")
            .defaultVisibility(.visible)
            
            // Album
            TableColumn("Album", value: \.album) { track in
                textCell(text: track.album)
            }
            .width(min: 100, ideal: 180, max: 300)
            .customizationID("album")
            .defaultVisibility(.visible)
            
            // Genre
            TableColumn("Genre", value: \.genre) { track in
                textCell(text: track.genre)
            }
            .width(min: 80, ideal: 120, max: 200)
            .customizationID("genre")
            .defaultVisibility(.hidden)
            
            // Year
            TableColumn("Year", value: \.year) { track in
                textCell(text: track.year)
            }
            .width(min: 60, ideal: 80, max: 100)
            .customizationID("year")
            .defaultVisibility(.visible)
            
            // Duration
            TableColumn("Duration", value: \.duration) { track in
                durationCell(for: track)
            }
            .width(min: 70, ideal: 80, max: 100)
            .customizationID("duration")
            .defaultVisibility(.visible)
            
            // Play Count
            TableColumn("Play Count", value: \.sortablePlayCount) { track in
                numberCell(value: track.playCount)
            }
            .width(min: 60, ideal: 80, max: 100)
            .customizationID("playCount")
            .defaultVisibility(.hidden)
            
            // Codec
            TableColumn("Codec", value: \.sortableCodec) { track in
                optionalTextCell(text: track.codec)
            }
            .width(min: 60, ideal: 80, max: 120)
            .customizationID("codec")
            .defaultVisibility(.hidden)
            
            // Date Added
            TableColumn("Date Added", value: \.sortableDateAdded) { track in
                dateCell(date: track.dateAdded)
            }
            .width(min: 90, ideal: 120, max: 150)
            .customizationID("dateAdded")
            .defaultVisibility(.hidden)
            
            // Artist
            TableColumn("Filename", value: \.filename) { track in
                textCell(text: track.filename)
            }
            .width(min: 100, ideal: 180, max: 300)
            .customizationID("filename")
            .defaultVisibility(.visible)
            
        }
        .background(Color(NSColor.controlBackgroundColor))
        .textSelection(.enabled)
        .contextMenu(forSelectionType: Track.ID.self) { selectedIDs in
            if let trackId = selectedIDs.first,
               let track = tracks.first(where: { $0.id == trackId }) {
                contextMenu(for: track)
            }
        } primaryAction: { selectedIDs in
            if let trackId = selectedIDs.first,
               let track = tracks.first(where: { $0.id == trackId }) {
                onPlayTrack(track)
            }
        }
        .onChange(of: columnCustomization) { _, newValue in
            saveColumnCustomization(newValue)
        }
    }
    
    // MARK: - Cell Builders (Optimized for Performance)
    
    @ViewBuilder
    private func titleCell(for track: Track) -> some View {
        HStack(spacing: 10) {
            // Artwork with play/pause overlay for current track
            ZStack {
                TrackArtworkView(track: track, size: 40, cornerRadius: 4)
                
                // Play/Pause overlay for current track
                if isCurrentTrack(track) {
                    Color.black.opacity(0.5)
                        .cornerRadius(4)
                    
                    Button(action: {
                        if playback.isPlaying {
                            playback.pause()
                        } else {
                            playback.play()
                        }
                    }) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .frame(width: 40, height: 40)
            
            // Title and playing indicator
            HStack(spacing: 6) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrentTrack(track) ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func textCell(text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder
    private func optionalTextCell(text: String?) -> some View {
        if let text = text {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func numberCell(value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .monospacedDigit()
    }
    
    @ViewBuilder
    private func durationCell(for track: Track) -> some View {
        Text(track.formattedDuration)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .monospacedDigit()
    }
    
    @ViewBuilder
    private func dateCell(date: Date?) -> some View {
        if let date = date {
            Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none))
                .font(.system(size: 12))
                .foregroundColor(.primary)
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func contextMenu(for track: Track) -> some View {
        TrackContextMenu(
            track: track,
            playlistContext: playlistContext
        )
    }
    
    // MARK: - Column Customization Persistence

    private func saveColumnCustomization(_ newValue: TableColumnCustomization<Track>) {
        do {
            let data = try JSONEncoder().encode(newValue)
            columnCustomizationData = data
        } catch {
            Logger.warning("Failed to encode TableColumnCustomization: \(error)")
        }
    }
    
    // MARK: - Prefetching
    
    private func prefetchArtwork(startingAt index: Int) {
        // Prefetch next 20 tracks' artwork (table rows are smaller, so more fit on screen)
        let endIndex = min(index + 20, tracks.count)
        guard endIndex > index else { return }
        
        let trackIds = tracks[index..<endIndex].compactMap { $0.trackId }
        ArtworkCache.shared.preloadArtwork(for: trackIds, size: 40)
    }
}

// MARK: - Track Extension for Sorting

extension Track {
   // These provide non-optional values for Table sorting
   
   var sortableTrackNumber: Int {
       trackNumber ?? Int.max
   }
   
   var sortableDiscNumber: Int {
       discNumber ?? Int.max
   }
   
   var sortableBitrate: Int {
       bitrate ?? 0
   }
   
   var sortableSampleRate: Int {
       sampleRate ?? 0
   }
   
   var sortablePlayCount: Int {
       playCount
   }
   
   var sortableDateAdded: Date {
       dateAdded ?? Date.distantPast
   }
   
   var sortableAlbumArtist: String {
       albumArtist ?? ""
   }
   
   var sortableCodec: String {
       codec ?? ""
   }
}

// MARK: - Preview

#Preview {
    TrackTableView(
        tracks: [],
        selection: .constant(nil),
        sortOrder: .constant([KeyPathComparator(\Track.title)]),
        onPlayTrack: { _ in },
        isCurrentTrack: { _ in false }
    )
    .environmentObject(DatabaseManager.shared)
    .frame(width: 800, height: 600)
}

