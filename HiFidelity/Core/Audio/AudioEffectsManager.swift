//
//  AudioEffectsManager.swift
//  HiFidelity
//
//  Manages DSP effects and custom processing for audio playback
//

import Foundation
import Bass
import Combine

/// Manages audio effects (DSP) for the current audio stream
/// Supports built-in BASS FX and custom DSP processing
class AudioEffectsManager: ObservableObject {
    static let shared = AudioEffectsManager()
    
    private let defaults = UserDefaults.standard
    private var isLoadingSettings = false
    
    // MARK: - Properties
    
    @Published var isEqualizerEnabled = false {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    // Equalizer bands (10-band graphic equalizer)
    // Frequencies: 32, 64, 125, 250, 500, 1K, 2K, 4K, 8K, 16K Hz
    @Published var equalizerBands: [Float] = Array(repeating: 0.0, count: 10) {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    @Published var preampGain: Double = 0.0 {
        didSet { 
            if !isLoadingSettings { 
                applyPreamp()
                saveSettings() 
            } 
        }
    }
    
    // Reverb settings
    @Published var isReverbEnabled = false {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    @Published var reverbMix: Float = -12.0 {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    // Effect handles (for removing effects later)
    private var activeEffects: [String: HFX] = [:]
    
    private var currentStream: HSTREAM = 0
    
    // Equalizer frequencies (Hz) - matching common EQ frequencies
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    
    // Settings keys
    enum SettingsKey: String, CaseIterable {
        case isEqualizerEnabled = "effects.equalizer.enabled"
        case equalizerBands = "effects.equalizer.bands"
        case preampGain = "effects.equalizer.preamp"
        case isReverbEnabled = "effects.reverb.enabled"
        case reverbMix = "effects.reverb.mix"
    }
    
    // MARK: - Initialization
    
    private init() {
        Logger.info("AudioEffectsManager initialized")
        loadSettings()
    }
    
    // MARK: - Stream Management
    
    /// Update the current stream to apply effects to
    func setStream(_ stream: HSTREAM) {
        guard stream != currentStream else { return }
        
        Logger.debug("AudioEffectsManager: Setting new stream \(stream)")
        
        // Remove all effects from old stream
        removeAllEffects()
        
        // Update current stream
        currentStream = stream
        
        // Reapply enabled effects to new stream
        reapplyEffects()
    }
    
    /// Remove all effects (called when stream changes or is stopped)
    func clearStream() {
        removeAllEffects()
        currentStream = 0
    }
    
    // MARK: - Equalizer
    
    /// Enable/disable 10-band parametric equalizer
    func setEqualizerEnabled(_ enabled: Bool) {
        isEqualizerEnabled = enabled
        
        if enabled {
            applyEqualizer()
            applyPreamp()
        } else {
            removeEffect("equalizer")
            removeEffect("preamp")
        }
        
        Logger.info("Equalizer: \(enabled ? "Enabled" : "Disabled")")
    }
    
    /// Apply preamp gain to boost or reduce overall volume
    /// Preamp works independently of whether EQ bands are enabled
    func applyPreamp() {
        guard currentStream != 0 else { return }
        
        // Remove previous preamp FX
        removeEffect("preamp")
        
        // Skip if gain = 0 dB
        guard preampGain != 0 else { return }
        
        // Convert dB to linear: linear = pow(10, dB / 20)
        let linearGain = powf(10.0, Float(preampGain) / 20.0)
        
        // Add the effect
        let fx = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_VOLUME), 0)
        
        if fx != 0 {
            // Prepare parameters
            var params = BASS_FX_VOLUME_PARAM()
            params.fTarget  = linearGain  // target volume multiplier
            params.fCurrent = linearGain  // instant change (no ramp)
            params.fTime    = 0.0         // time in seconds (0 = immediate)
            params.lCurve   = 0           // linear curve
            
            // Apply
            BASS_FXSetParameters(fx, &params)
            
            // Track it
            activeEffects["preamp"] = fx
            
            Logger.debug("Applied preamp \(preampGain) dB (linear=\(linearGain))")
        } else {
            Logger.error("Preamp failed. Error: \(BASS_ErrorGetCode())")
        }
    }
    
    
    /// Update equalizer band gain
    /// - Parameters:
    ///   - band: Band index (0-9)
    ///   - gain: Gain in dB (-15 to +15)
    func setEqualizerBand(_ band: Int, gain: Float) {
        guard band >= 0 && band < 10 else { return }
        
        equalizerBands[band] = gain
        
        if isEqualizerEnabled {
            applyEqualizer()
        }
    }
    
    /// Reset all equalizer bands to 0 dB
    func resetEqualizer() {
        equalizerBands = Array(repeating: 0.0, count: 10)
        preampGain = 0.0
        
        if isEqualizerEnabled {
            applyEqualizer()
            applyPreamp()
        }
        
        Logger.info("Equalizer reset to flat (0 dB)")
    }
    
    // MARK: - Reverb
    
    /// Enable/disable reverb effect
    func setReverbEnabled(_ enabled: Bool) {
        isReverbEnabled = enabled
        
        if enabled {
            applyReverb()
        } else {
            removeEffect("reverb")
        }
        
        Logger.info("Reverb: \(enabled ? "Enabled" : "Disabled")")
    }
    
    /// Update reverb mix level
    /// - Parameter mix: Mix level in dB (-96 to 0, where -96 is none and 0 is max)
    func setReverbMix(_ mix: Float) {
        reverbMix = max(-96.0, min(0.0, mix))
        
        if isReverbEnabled {
            applyReverb()
        }
    }
    
    /// Apply reverb effect to current stream
    private func applyReverb() {
        guard currentStream != 0, isReverbEnabled else { return }
        
        // Remove existing reverb
        removeEffect("reverb")
        
        // Add reverb effect
        let fx = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_DX8_REVERB), 0)
        
        if fx != 0 {
            var params = BASS_DX8_REVERB()
            params.fInGain = 0.0                    // Input gain (dB)
            params.fReverbMix = reverbMix           // Reverb mix (-96 to 0 dB)
            params.fReverbTime = 1500.0             // Reverb time (ms)
            params.fHighFreqRTRatio = 0.5           // High-frequency RT ratio
            
            BASS_FXSetParameters(fx, &params)
            
            activeEffects["reverb"] = fx
            Logger.debug("Applied reverb: mix=\(reverbMix) dB")
        } else {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to apply reverb, error: \(errorCode)")
        }
    }
    
    func applyEqualizer() {
        guard currentStream != 0 else { return }
        
        // Remove existing EQ effects
        removeEffect("equalizer")
        
        // Add parametric EQ for each band
        for (index, gain) in equalizerBands.enumerated() {
            guard gain != 0.0 else { continue }
            
            let fx = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_DX8_PARAMEQ), 0)
            
            if fx != 0 {
                var params = BASS_DX8_PARAMEQ()
                params.fCenter = eqFrequencies[index]
                params.fBandwidth = 12.0 // Octave width
                params.fGain = gain
                
                BASS_FXSetParameters(fx, &params)
                
                activeEffects["equalizer_\(index)"] = fx
            }
        }
        
        Logger.debug("Applied equalizer: \(equalizerBands)")
    }
    
    
    // MARK: - Effect Management
    
    private func removeEffect(_ key: String) {
        // Remove specific effect
        if let fx = activeEffects[key] {
            BASS_ChannelRemoveFX(currentStream, fx)
            activeEffects.removeValue(forKey: key)
            Logger.debug("Removed effect: \(key)")
        }
        
        // For equalizer, remove all bands
        if key == "equalizer" {
            for band in 0..<10 {
                if let fx = activeEffects["equalizer_\(band)"] {
                    BASS_ChannelRemoveFX(currentStream, fx)
                    activeEffects.removeValue(forKey: "equalizer_\(band)")
                }
            }
        }
    }
    
    private func removeAllEffects() {
        guard currentStream != 0 else {
            activeEffects.removeAll()
            return
        }
        
        for (key, fx) in activeEffects {
            BASS_ChannelRemoveFX(currentStream, fx)
            Logger.debug("Removed effect: \(key)")
        }
        
        activeEffects.removeAll()
    }
    
    private func reapplyEffects() {
        guard currentStream != 0 else { return }
        
        Logger.debug("Reapplying effects to new stream")
        
        if isEqualizerEnabled {
            applyEqualizer()
            applyPreamp()
        }
        
        if isReverbEnabled {
            applyReverb()
        }
    }
    
    // MARK: - Presets & Reset
    
    func disableEqualizer() {
        // Batch all changes to avoid multiple saves
        isLoadingSettings = true
        
        isEqualizerEnabled = false
        preampGain = 0.0
        equalizerBands = Array(repeating: 0.0, count: 10)
        
        isLoadingSettings = false
        
        removeAllEffects()
        saveSettings() // Single save after all changes
        
        Logger.info("Equalizer disabled and reset")
    }
    
    // MARK: - Persistence
    
    /// Load equalizer settings from UserDefaults
    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        
        // Load equalizer state
        isEqualizerEnabled = defaults.bool(forKey: SettingsKey.isEqualizerEnabled.rawValue)
        
        // Load preamp gain
        preampGain = defaults.object(forKey: SettingsKey.preampGain.rawValue) as? Double ?? 0.0
        
        // Load equalizer bands
        if let savedBands = defaults.array(forKey: SettingsKey.equalizerBands.rawValue) as? [Float] {
            if savedBands.count == 10 {
                equalizerBands = savedBands
        }
    }
    
        // Load reverb settings
        isReverbEnabled = defaults.bool(forKey: SettingsKey.isReverbEnabled.rawValue)
        reverbMix = defaults.object(forKey: SettingsKey.reverbMix.rawValue) as? Float ?? -12.0
        
        Logger.info("Loaded audio effects settings from UserDefaults")
        Logger.debug("EQ Enabled: \(isEqualizerEnabled), Bands: \(equalizerBands), Preamp: \(preampGain) dB")
        Logger.debug("Reverb Enabled: \(isReverbEnabled), Mix: \(reverbMix) dB")
        }
    
    /// Save equalizer settings to UserDefaults
    private func saveSettings() {
        // Save equalizer state
        defaults.set(isEqualizerEnabled, forKey: SettingsKey.isEqualizerEnabled.rawValue)
        
        // Save preamp gain
        defaults.set(preampGain, forKey: SettingsKey.preampGain.rawValue)
        
        // Save equalizer bands
        defaults.set(equalizerBands, forKey: SettingsKey.equalizerBands.rawValue)
        
        // Save reverb settings
        defaults.set(isReverbEnabled, forKey: SettingsKey.isReverbEnabled.rawValue)
        defaults.set(reverbMix, forKey: SettingsKey.reverbMix.rawValue)
        
        Logger.debug("Saved audio effects settings to UserDefaults")
    }
    
    /// Reset equalizer settings to defaults
    func resetAllSettings() {
        disableEqualizer()
        Logger.info("Reset equalizer settings to defaults")
        }
    }
