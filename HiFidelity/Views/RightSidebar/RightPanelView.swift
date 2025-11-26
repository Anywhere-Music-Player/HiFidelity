//
//  RightPanelView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 19/11/25.
//

import SwiftUI

/// Enum representing the tabs in the right panel
enum RightPanelTab {
    case trackInfo
    case queue
    case lyrics
}

/// Main container for the right panel with tabs
struct RightPanelView: View {
    @Binding var selectedTab: RightPanelTab
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            Group {
                switch selectedTab {
                case .trackInfo:
                    TrackInfoPanel()
                case .queue:
                    QueuePanel()
                case .lyrics:
                    LyricsPanel()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    
}


