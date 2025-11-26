//
//  TrackInfoDisplay.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Display current playing track information with artwork and favorite button
struct TrackInfoDisplay: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Album artwork
            artworkView
            
            // Track details and favorite
            if let track = playback.currentTrack {
                trackDetails(for: track)
                favoriteButton(for: track)
            } else {
                placeholderDetails
            }
        }
        .frame(minWidth: 200, maxWidth: 320, alignment: .leading)
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private var artworkView: some View {
        if let track = playback.currentTrack {
            TrackArtworkView(track: track, size: 56, cornerRadius: 6)
        } else {
            placeholderArtwork
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(width: 56, height: 56)
    }
    
    // MARK: - Track Details
    
    private func trackDetails(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(AppFonts.sidebarItem)
                .lineLimit(1)
                .foregroundColor(.primary)
            
            Text(track.artist)
                .font(AppFonts.captionLarge)
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
    }
    
    private var placeholderDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not Playing")
                .font(AppFonts.sidebarItem)
                .foregroundColor(.secondary)
            
            Text("Select a track to play")
                .font(AppFonts.captionLarge)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    // MARK: - Favorite Button
    
    private func favoriteButton(for track: Track) -> some View {
        Button {
            playback.toggleFavorite()
        } label: {
            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                .font(AppFonts.bodySmall)
                .foregroundColor(track.isFavorite ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    TrackInfoDisplay()
        .frame(width: 320, height: 80)
        .padding()
}

