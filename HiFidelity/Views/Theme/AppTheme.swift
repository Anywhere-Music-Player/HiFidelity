//
//  AppTheme.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Theme manager for the application
class AppTheme: ObservableObject {
    static let shared = AppTheme()
    
    @Published var currentTheme: Theme = .blue
    
    private init() {
        // Load saved theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = Theme(rawValue: savedTheme) {
            currentTheme = theme
        }
    }
    
    func setTheme(_ theme: Theme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
        
        // Update the accent color globally
        if let window = NSApplication.shared.windows.first {
            window.appearance = theme.appearance
        }
    }
}

/// Available themes for the app
enum Theme: String, CaseIterable, Identifiable {
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case mint = "mint"
    case teal = "teal"
    case cyan = "cyan"
    case indigo = "indigo"
    
    var id: String { rawValue }
    
    var name: String {
        rawValue.capitalized
    }
    
    var primaryColor: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return Color(hue: 0.15, saturation: 0.8, brightness: 0.9)
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .indigo: return .indigo
        }
    }
    
    var gradientColors: [Color] {
        [primaryColor, primaryColor.opacity(0.7)]
    }
    
    var appearance: NSAppearance? {
        return nil // Let system handle dark/light mode
    }
}

/// Extension to easily access theme colors in views
extension View {
    func themedAccentColor(_ theme: AppTheme) -> some View {
        self.accentColor(theme.currentTheme.primaryColor)
    }
}

/// Custom modifier for themed backgrounds
struct ThemedBackground: ViewModifier {
    @ObservedObject var theme: AppTheme
    var opacity: Double = 0.1
    
    func body(content: Content) -> some View {
        content
            .background(
                theme.currentTheme.primaryColor.opacity(opacity)
            )
    }
}

extension View {
    func themedBackground(_ theme: AppTheme, opacity: Double = 0.1) -> some View {
        modifier(ThemedBackground(theme: theme, opacity: opacity))
    }
}

