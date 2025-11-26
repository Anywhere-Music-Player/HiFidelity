//
//  AppFonts.swift
//  HiFidelity
//
//  Created by Varun Rathod on 19/11/25.
//

import SwiftUI

/// Centralized font system for consistent typography across the app
struct AppFonts {
    
    // MARK: - Display Fonts (Large Headers)
    
    static let displayLarge = Font.system(size: 32, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let displaySmall = Font.system(size: 24, weight: .bold)
    
    // MARK: - Heading Fonts
    
    static let heading1 = Font.system(size: 22, weight: .bold)
    static let heading2 = Font.system(size: 20, weight: .bold)
    static let heading3 = Font.system(size: 18, weight: .semibold)
    static let heading4 = Font.system(size: 16, weight: .semibold)
    static let heading5 = Font.system(size: 14, weight: .semibold)
    
    // MARK: - Body Fonts
    
    static let bodyLarge = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 14, weight: .regular)
    
    // MARK: - Label Fonts
    
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 13, weight: .medium)
    static let labelSmall = Font.system(size: 12, weight: .medium)
    
    // MARK: - Caption Fonts
    
    static let captionLarge = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .regular)
    static let captionSmall = Font.system(size: 10, weight: .regular)
    
    // MARK: - Button Fonts
    
    static let buttonLarge = Font.system(size: 16, weight: .semibold)
    static let buttonMedium = Font.system(size: 14, weight: .semibold)
    static let buttonSmall = Font.system(size: 12, weight: .semibold)
    
    // MARK: - Specialized Fonts
    
    static let trackTitle = Font.system(size: 20, weight: .bold)
    static let trackArtist = Font.system(size: 16, weight: .regular)
    static let trackAlbum = Font.system(size: 14, weight: .regular)
    static let trackMetadata = Font.system(size: 14, weight: .regular)
    static let trackDuration = Font.system(size: 13, weight: .regular)
    
    static let sidebarItem = Font.system(size: 14, weight: .medium)
    static let sidebarHeader = Font.system(size: 16, weight: .bold)
    
    static let playbackTime = Font.system(size: 11, weight: .medium)
    static let playbackControl = Font.system(size: 16, weight: .regular)
    
    static let tabBarItem = Font.system(size: 10, weight: .medium)
    static let tabBarIcon = Font.system(size: 16, weight: .regular)
}

/// Extension for easy access to consistent font sizing
extension View {
    func appFont(_ font: Font) -> some View {
        self.font(font)
    }
}
