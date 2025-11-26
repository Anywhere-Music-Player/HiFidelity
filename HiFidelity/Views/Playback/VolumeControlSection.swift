//
//  VolumeControlSection.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Volume control with mute button and slider
struct VolumeControlSection: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Mute button
            Button {
                playback.toggleMute()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainHoverButtonStyle())
            
            // Volume slider
            Slider(
                value: volumeBinding,
                in: 0...1
            )
            .frame(width: 100)
            .accentColor(theme.currentTheme.primaryColor)
        }
    }
    
    // MARK: - Computed Properties
    
    private var volumeIcon: String {
        if playback.isMuted || playback.volume == 0 {
            return "speaker.slash.fill"
        } else if playback.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playback.volume < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { playback.isMuted ? 0 : playback.volume },
            set: { newValue in
                if playback.isMuted {
                    playback.toggleMute()
                }
                playback.setVolume(newValue)
            }
        )
    }
}

// MARK: - Preview

#Preview {
    VolumeControlSection()
        .frame(width: 150, height: 40)
        .padding()
}

