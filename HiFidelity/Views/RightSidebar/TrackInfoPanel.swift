//
//  TrackInfoPanel.swift
//  HiFidelity
//
//  Track information panel showing detailed metadata
//

import SwiftUI
import GRDB

/// Manages track info panel state
@MainActor
class TrackInfoManager: ObservableObject {
    @Published var selectedTrack: Track?
    @Published var isVisible: Bool = false
    
    func show(track: Track) {
        selectedTrack = track
        isVisible = true
    }
    
    func hide() {
        isVisible = false
        // Delay clearing to allow smooth animation
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            selectedTrack = nil
        }
    }
}

/// Panel showing detailed information about a selected track
struct TrackInfoPanel: View {
    @EnvironmentObject var trackInfoManager: TrackInfoManager
    @ObservedObject var theme = AppTheme.shared
    
    @State private var fullTrack: Track?
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            if let track = fullTrack ?? trackInfoManager.selectedTrack {
                trackDetails(track: track)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: trackInfoManager.selectedTrack?.trackId) {
            if let selectedTrack = trackInfoManager.selectedTrack {
                await loadFullTrackInfo(for: selectedTrack)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Track Info")
                .font(.system(size: 16, weight: .bold))
                .frame(height: 28)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                trackInfoManager.hide()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Data Loading
    
    private func loadFullTrackInfo(for track: Track) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch full track data from database including all metadata
            if let trackId = track.trackId {
                fullTrack = try await DatabaseManager.shared.dbQueue.read { db in
                    try Track
                        .filter(Track.Columns.trackId == trackId)
                        .fetchOne(db)
                }
                Logger.debug("Loaded full track info for: \(track.title)")
            } else {
                fullTrack = track
            }
        } catch {
            Logger.error("Failed to load full track info: \(error)")
            fullTrack = track
        }
    }
    
    // MARK: - Track Details
    
    private func trackDetails(track: Track) -> some View {
            ScrollView() {
                VStack(spacing: 24) {
                    // Large album artwork
                    TrackArtworkView(track: track, size: 280, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .padding(.top, 32)
                    
                    // Track info
                    VStack(spacing: 8) {
                        Text(track.title)
                            .font(AppFonts.trackTitle)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(track.artist)
                            .font(AppFonts.trackArtist)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(AppFonts.trackAlbum)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Track details
                    VStack(spacing: 12) {
                        // Basic info
                        DetailRow(icon: "clock", label: "Duration", value: track.formattedDuration)
                        
                        if !track.year.isEmpty {
                            DetailRow(icon: "calendar", label: "Year", value: track.year)
                        }
                        
                        if !track.genre.isEmpty {
                            DetailRow(icon: "guitars", label: "Genre", value: track.genre)
                        }
                        
                        if !track.composer.isEmpty {
                            DetailRow(icon: "music.note.list", label: "Composer", value: track.composer)
                        }
                        
                        // Album details
                        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
                            DetailRow(icon: "person.2", label: "Album Artist", value: albumArtist)
                        }
                        
                        // Track/Disc numbers
                        if let trackNumber = track.trackNumber {
                            let trackInfo = track.totalTracks != nil ? "\(trackNumber) of \(track.totalTracks!)" : "\(trackNumber)"
                            DetailRow(icon: "number", label: "Track Number", value: trackInfo)
                        }
                        
                        if let discNumber = track.discNumber {
                            let discInfo = track.totalDiscs != nil ? "\(discNumber) of \(track.totalDiscs!)" : "\(discNumber)"
                            DetailRow(icon: "opticaldisc", label: "Disc Number", value: discInfo)
                        }
                        
                        // Playback stats
                        DetailRow(icon: "play.circle", label: "Play Count", value: "\(track.playCount)")
                        
                        if let lastPlayed = track.lastPlayedDate {
                            DetailRow(icon: "clock.arrow.circlepath", label: "Last Played", value: formatDate(lastPlayed))
                        }
                        
                        // Audio quality
                        if let bitrate = track.bitrate {
                            DetailRow(icon: "waveform", label: "Bitrate", value: "\(bitrate) kbps")
                        }
                        
                        if let sampleRate = track.sampleRate {
                            let formattedRate = formatSampleRate(sampleRate)
                            DetailRow(icon: "dial.high", label: "Sample Rate", value: formattedRate)
                        }
                        
                        if let codec = track.codec {
                            DetailRow(icon: "waveform.circle", label: "Codec", value: codec)
                        }
                        
                        // File info
                        DetailRow(icon: "doc", label: "Format", value: track.format)
                        
                        if let fileSize = track.fileSize {
                            DetailRow(icon: "externaldrive", label: "File Size", value: formatFileSize(fileSize))
                        }
                        
                        // Additional metadata
                        if let dateAdded = track.dateAdded {
                            DetailRow(icon: "calendar.badge.plus", label: "Date Added", value: formatDate(dateAdded))
                        }
                        
                        if let bpm = track.bpm {
                            DetailRow(icon: "metronome", label: "BPM", value: "\(bpm)")
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Bottom spacer for playback bar clearance
                    Spacer()
                        .frame(height: 110)
                }
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "info.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.2))
            
            Text("No Track Selected")
                .font(AppFonts.heading2)
                .foregroundColor(.primary)
            
            Text("Right-click any track and select 'Get Info' to see detailed information.")
                .font(AppFonts.bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatSampleRate(_ rate: Int) -> String {
        if rate >= 1000 {
            let kHz = Double(rate) / 1000.0
            return String(format: "%.1f kHz", kHz)
        }
        return "\(rate) Hz"
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(AppFonts.captionLarge)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(AppFonts.trackMetadata)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(AppFonts.labelLarge)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(AppFonts.bodySmall)
                
                Text(label)
                    .font(AppFonts.buttonMedium)
                
                Spacer()
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? color.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

