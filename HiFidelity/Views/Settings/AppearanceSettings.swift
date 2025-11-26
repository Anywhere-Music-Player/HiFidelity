//
//  AppearanceSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Advanced appearance settings including theme customization
struct AppearanceSettings: View {
    @ObservedObject var theme: AppTheme
    @AppStorage("accentOpacity") private var accentOpacity: Double = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Theme Selection
            themeSection
            
            Divider()
            
            // Advanced Options
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            
        }
    }
    
    // MARK: - Theme Section
    
    private var themeSection: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Theme")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Choose your preferred color theme")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 16)
                ], spacing: 16) {
                    ForEach(Theme.allCases) { themeOption in
                        ThemeCard(
                            theme: theme,
                            themeOption: themeOption,
                            opacity: accentOpacity
                        )
                    }
                }
            }
        
            
            
            // Accent opacity
            VStack(spacing: 8) {
                HStack {
                    Text("Accent Color Intensity")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(accentOpacity * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $accentOpacity, in: 0.5...1.0, step: 0.1)
                    .accentColor(theme.currentTheme.primaryColor)
            }
        }
    }
    
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Reset button
            Button {
                resetToDefaults()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                }
                .font(.subheadline)
                .foregroundColor(theme.currentTheme.primaryColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.currentTheme.primaryColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helpers

    
    private func resetToDefaults() {
        accentOpacity = 1.0
        theme.setTheme(.blue)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    @ObservedObject var theme: AppTheme
    let themeOption: Theme
    let opacity: Double
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                theme.setTheme(themeOption)
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: themeOption.gradientColors.map { $0.opacity(opacity) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    theme.currentTheme == themeOption ? themeOption.primaryColor : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .shadow(
                            color: isHovered ? themeOption.primaryColor.opacity(0.3) : Color.clear,
                            radius: 8
                        )
                    
                    if theme.currentTheme == themeOption {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                
                Text(themeOption.name)
                    .font(.subheadline)
                    .fontWeight(theme.currentTheme == themeOption ? .semibold : .regular)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AppearanceSettings(theme: AppTheme.shared)
            .padding()
    }
    .frame(width: 600, height: 800)
}

