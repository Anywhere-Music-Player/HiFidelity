//
//  AudioSettingsView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 15/11/25.
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @State private var showDeviceChangeAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Audio Effects
            settingsSection(title: "Audio Effects", icon: "waveform.badge.magnifyingglass") {
                effectsSettings
            }
            
            Divider()
            
            // Audio Quality
            settingsSection(title: "Audio Quality", icon: "waveform") {
                qualitySettings
            }
            
            Divider()
            
            // Output Device
            settingsSection(title: "Output Device", icon: "speaker.wave.3") {
                deviceSettings
            }
            
            Divider()
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .alert("Device Change Requires Restart", isPresented: $showDeviceChangeAlert) {
            Button("OK") { }
        } message: {
            Text("Changing audio device or sample rate will take effect when you restart the application.")
        }
    }
    
    // MARK: - Settings Sections
    
    private var effectsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reverb Toggle
            settingRow(
                label: "Reverb",
                description: "Add spatial depth and ambience to audio"
            ) {
                Toggle("", isOn: Binding(
                    get: { effectsManager.isReverbEnabled },
                    set: { effectsManager.setReverbEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
            
            // Reverb Mix
            if effectsManager.isReverbEnabled {
            settingRow(
                    label: "Reverb Mix",
                    description: "Amount of reverb effect to apply"
            ) {
                HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(effectsManager.reverbMix) },
                            set: { effectsManager.setReverbMix(Float($0)) }
                        ), in: -96...0, step: 1)
                        .frame(width: 150)
                    
                        Text("\(Int(effectsManager.reverbMix)) dB")
                            .frame(width: 60, alignment: .trailing)
                        .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
    
    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Resampling Quality
            settingRow(
                label: "Resampling Quality",
                description: "Quality of sample rate conversion"
            ) {
                Picker("", selection: $settings.resamplingQuality) {
                    ForEach(AudioSettings.ResamplingQuality.allCases, id: \.self) { quality in
                        Text(quality.description).tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            
            // Buffer Length
            settingRow(
                label: "Audio Buffer",
                description: "Larger buffer = more stable, but higher latency"
            ) {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(settings.bufferLength) },
                        set: { settings.bufferLength = Int($0) }
                    ), in: 100...2000, step: 100)
                    .frame(width: 150)
                    
                    Text("\(settings.bufferLength) ms")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sample Rate
            settingRow(
                label: "Sample Rate",
                description: "Audio output sample rate (restart required)"
            ) {
                Picker("", selection: $settings.sampleRate) {
                    ForEach(AudioSettings.availableSampleRates, id: \.self) { rate in
                        Text(settings.getSampleRateDescription(rate)).tag(rate)
                    }
                }
                .onChange(of: settings.sampleRate) { _, _ in
                    showDeviceChangeAlert = true
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
        }
    }
    
    // MARK: - Helper Views
    
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.headline)
            }
            
            content()
        }
    }
    
    private func settingRow<Content: View>(
        label: String,
        description: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            control()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AudioSettingsView()
        .frame(width: 700, height: 600)
}
