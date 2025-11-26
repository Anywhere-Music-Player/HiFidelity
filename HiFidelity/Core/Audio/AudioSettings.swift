//
//  AudioSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 15/11/25.
//

import Foundation
import Combine

/// Audio settings manager with user-friendly options
/// Settings are applied at runtime without requiring restart
class AudioSettings: ObservableObject {
    static let shared = AudioSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Properties
    
    // Playback Settings (applied at runtime via BASS_ChannelSetAttribute)
    @Published var playbackVolume: Double {
        didSet { save(playbackVolume, forKey: .playbackVolume) }
    }
    
    // Audio Quality Settings (BASS_SetConfig - applied immediately)
    @Published var bufferLength: Int {
        didSet { 
            save(bufferLength, forKey: .bufferLength)
            postNotification()
        }
    }
    
    @Published var resamplingQuality: ResamplingQuality {
        didSet { 
            save(resamplingQuality.rawValue, forKey: .resamplingQuality)
            postNotification()
        }
    }
    
    @Published var sampleRate: Int {
        didSet { save(sampleRate, forKey: .sampleRate) }
    }
    
    // MARK: - Settings Keys
    
    private enum SettingsKey: String {
        case playbackVolume
        case gaplessPlayback
        case bufferLength
        case resamplingQuality
        case sampleRate
        
        var fullKey: String {
            return "audio.\(rawValue)"
        }
    }
    
    // MARK: - Enums
    
    enum ResamplingQuality: String, CaseIterable {
        case linear = "Linear"
        case good = "Good"
        case better = "Better"
        case best = "Best"
        
        var description: String {
            switch self {
            case .linear: return "Linear (Fastest)"
            case .good: return "Good (8-point Sinc)"
            case .better: return "Better (16-point Sinc)"
            case .best: return "Best (32-point Sinc)"
            }
        }
        
        var bassValue: Int {
            switch self {
            case .linear: return 0
            case .good: return 1
            case .better: return 2
            case .best: return 3
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize with default values
        self.playbackVolume = 0.7
        self.bufferLength = 500
        self.resamplingQuality = .better
        self.sampleRate = 44100
        
        // Load saved settings
        loadSettings()
    }
    
    private func loadSettings() {
        self.playbackVolume = defaults.object(forKey: SettingsKey.playbackVolume.fullKey) as? Double ?? 0.7
        self.bufferLength = defaults.object(forKey: SettingsKey.bufferLength.fullKey) as? Int ?? 500
        self.sampleRate = defaults.object(forKey: SettingsKey.sampleRate.fullKey) as? Int ?? 44100
        
        if let resamplingRaw = defaults.string(forKey: SettingsKey.resamplingQuality.fullKey),
           let quality = ResamplingQuality(rawValue: resamplingRaw) {
            self.resamplingQuality = quality
        }
    }
    
    // MARK: - UserDefaults Helpers
    
    private func save<T>(_ value: T, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.fullKey)
    }
    
    private func postNotification() {
        NotificationCenter.default.post(name: NSNotification.Name("AudioSettingsChanged"), object: nil)
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        playbackVolume = 0.7
        bufferLength = 500
        resamplingQuality = .better
        sampleRate = 44100
        
        Logger.info("Audio settings reset to defaults")
    }
    
    // MARK: - Sample Rate Options
    
    static let availableSampleRates = [44100, 48000, 88200, 96000, 176400, 192000]
    
    func getSampleRateDescription(_ rate: Int) -> String {
        return "\(rate / 1000) kHz"
    }
}
