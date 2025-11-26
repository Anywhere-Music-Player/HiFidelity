//
//  LyricsPanel.swift
//  HiFidelity
//
//  Karaoke-style synchronized lyrics with LRC file support
//

import SwiftUI
import UniformTypeIdentifiers

/// Complete karaoke-style lyrics panel with LRC support
struct LyricsPanel: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var database = DatabaseManager.shared
    
    @State private var lyrics: Lyrics?
    @State private var currentLineIndex: Int? = nil
    @State private var isImportingLRC = false
    @State private var showImportSuccess = false
    @State private var isDraggingOver = false
    @State private var isAppActive = true
    
    // Timer for updating current line
    @State private var updateTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            header
            
            Divider()
            
            // Content
            if let track = playback.currentTrack {
                lyricsContent(track: track)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDraggingOver {
                dragOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $isImportingLRC,
            allowedContentTypes: [UTType(filenameExtension: "lrc")!],
            allowsMultipleSelection: false
        ) { result in
            handleLRCImport(result)
        }
        .alert("Lyrics Imported", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("LRC file has been imported successfully")
        }
        .onChange(of: playback.currentTrack) { _, newTrack in
            loadLyricsFor(track: newTrack)
        }
        .onChange(of: playback.currentTime) { _, _ in
            if isAppActive {
                updateCurrentLine()
            }
        }
        .onAppear {
            loadLyricsFor(track: playback.currentTrack)
            setupLifecycleObservers()
        }
        .onDisappear {
            removeLifecycleObservers()
        }
        .textSelection(.enabled)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Lyrics")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .frame(height: 28)
            
            Spacer()
            
            if playback.currentTrack != nil {
                Menu {
                    Button(action: { isImportingLRC = true }) {
                        Label("Import LRC File", systemImage: "doc.badge.plus")
                    }
                    
                    if lyrics != nil {
                        Button(action: exportLyrics) {
                            Label("Export LRC File", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: removeLyrics) {
                            Label("Remove Lyrics", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        
    }
    
    // MARK: - Lyrics Content
    
    private func lyricsContent(track: Track) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    // Track info
                    trackInfo(track: track)
                    
                    // Lyrics display
                    if let lyrics = lyrics, !lyrics.lines.isEmpty {
                        karaokeLyrics(lyrics: lyrics, proxy: proxy)
                    } else {
                        noLyricsView
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func trackInfo(track: Track) -> some View {
        VStack(spacing: 12) {
            // Album artwork
            TrackArtworkView(track: track, size: 120, cornerRadius: 12)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 4) {
                Text(track.title)
                    .font(AppFonts.heading3)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(track.artist)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 40)
    }
    
    private func karaokeLyrics(lyrics: Lyrics, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                let isCurrent = currentLineIndex == index
                let isPast = (currentLineIndex ?? -1) > index
                
                lyricLine(
                    text: line.text,
                    isCurrent: isCurrent,
                    isPast: isPast
                )
                .id(line.id)
                .padding(.vertical, 12)
                .background(
                    isCurrent ?
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.currentTheme.primaryColor.opacity(0.1))
                        .padding(.horizontal, -16)
                    : nil
                )
                .onChange(of: isCurrent) { _, newValue in
                    if newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(line.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
    
    private func lyricLine(text: String, isCurrent: Bool, isPast: Bool) -> some View {
        Text(text)
            .font(isCurrent ? .system(size: 20, weight: .semibold) : .system(size: 16))
            .foregroundColor(
                isCurrent ? theme.currentTheme.primaryColor :
                isPast ? .secondary :
                .primary.opacity(0.6)
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }
    
    private var noLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.2))
            
            Text("No lyrics available")
                .font(AppFonts.bodyLarge)
                .foregroundColor(.secondary)
            
            Button(action: { isImportingLRC = true }) {
                Label("Import LRC File", systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.currentTheme.primaryColor)
            
            Text("or drag and drop an LRC file here")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.quote")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.2))
            
            Text("Play a song to see the lyrics here.")
                .font(AppFonts.bodyLarge)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 90)
    }
    
    // MARK: - Drag Overlay
    
    private var dragOverlay: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
            
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(theme.currentTheme.primaryColor)
                
                Text("Drop LRC file here")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Release to import lyrics")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(theme.currentTheme.primaryColor, lineWidth: 3)
                    .padding(1)
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
    }
    
    // MARK: - Helper Methods
    
    private func loadLyricsFor(track: Track?) {
        guard let track = track,
              let trackId = track.trackId else {
            lyrics = nil
            currentLineIndex = nil
            return
        }
        
        Task {
            do {
                if let trackLyrics = try await database.getLyrics(forTrackId: trackId) {
                    await MainActor.run {
                        lyrics = Lyrics(lrcContent: trackLyrics.lrcContent)
                        updateCurrentLine()
                    }
                } else {
                    await MainActor.run {
                        lyrics = nil
                        currentLineIndex = nil
                    }
                }
            } catch {
                Logger.error("Failed to load lyrics: \(error)")
                await MainActor.run {
                    lyrics = nil
                    currentLineIndex = nil
                }
            }
        }
    }
    
    private func updateCurrentLine() {
        guard let lyrics = lyrics else {
            currentLineIndex = nil
            return
        }
        
        currentLineIndex = lyrics.currentLineIndex(at: playback.currentTime)
    }
    
    private func syncToCurrentPosition() {
        // Force update to current playback position
        updateCurrentLine()
        Logger.info("Lyrics synced to current playback position")
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.isAppActive = true
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.isAppActive = false
            }
        }
    }
    
    private func removeLifecycleObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard playback.currentTrack != nil else {
            Logger.warning("Cannot import lyrics: no track currently playing")
            return false
        }
        
        guard let provider = providers.first else {
            return false
        }
        
        // Check if provider has file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                if let error = error {
                    Logger.error("Failed to load dropped item: \(error)")
                    return
                }
                
                if let urlData = urlData as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    
                    // Check if it's an LRC file
                    guard url.pathExtension.lowercased() == "lrc" else {
                        Logger.warning("Dropped file is not an LRC file: \(url.lastPathComponent)")
                        return
                    }
                    
                    // Import the file
                    DispatchQueue.main.async {
                        self.importLRCFile(from: url)
                    }
                }
            }
            return true
        }
        
        return false
    }
    
    private func importLRCFile(from url: URL) {
        guard let track = playback.currentTrack else { return }
        
        // Try to access security-scoped resource (may not be needed for drag-and-drop)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        
        // Ensure we stop accessing when done (only if we successfully started)
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let lrcContent = try String(contentsOf: url, encoding: .utf8)
            
            // Parse to validate
            let parsedLyrics = Lyrics(lrcContent: lrcContent)
            guard !parsedLyrics.lines.isEmpty else {
                Logger.error("LRC file is empty or invalid")
                return
            }
            
            // Save to database
            Task {
                do {
                    try await saveLyricsToDatabase(track: track, lrcContent: lrcContent)
                    
                    await MainActor.run {
                        lyrics = parsedLyrics
                        showImportSuccess = true
                        Logger.info("LRC file imported successfully: \(parsedLyrics.lines.count) lines from \(url.lastPathComponent)")
                    }
                } catch {
                    Logger.error("Failed to save lyrics to database: \(error)")
                }
            }
        } catch {
            Logger.error("Failed to read LRC file '\(url.lastPathComponent)': \(error)")
        }
    }
    
    private func handleLRCImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importLRCFile(from: url)
            
        case .failure(let error):
            Logger.error("LRC import failed: \(error)")
        }
    }
    
    private func saveLyricsToDatabase(track: Track, lrcContent: String) async throws {
        guard let trackId = track.trackId else {
            throw DatabaseError.trackNotFound(id: 0)
        }
        
        // Check if lyrics already exist for this track
        if let existing = try await database.getLyrics(forTrackId: trackId) {
            // Update existing lyrics
            try await database.updateLyricsContent(id: existing.id!, lrcContent: lrcContent)
        } else {
            // Insert new lyrics
            _ = try await database.insertLyrics(
                trackId: trackId,
                lrcContent: lrcContent,
                source: "user"
            )
        }
    }
    
    private func exportLyrics() {
        guard let lyrics = lyrics,
              let track = playback.currentTrack else { return }
        
        let lrcContent = lyrics.toLRC()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(track.title) - \(track.artist).lrc"
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc")!]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Request access to security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    Logger.error("Failed to access security-scoped resource for export: \(url.path)")
                    return
                }
                
                defer {
                    url.stopAccessingSecurityScopedResource()
                }
                
                do {
                    try lrcContent.write(to: url, atomically: true, encoding: .utf8)
                    Logger.info("LRC file exported successfully to: \(url.path)")
                } catch {
                    Logger.error("Failed to export LRC file: \(error)")
                }
            }
        }
    }
    
    private func removeLyrics() {
        guard let track = playback.currentTrack,
              let trackId = track.trackId else { return }
        
        Task {
            do {
                try await database.deleteAllLyrics(forTrackId: trackId)
                
                await MainActor.run {
                    lyrics = nil
                    currentLineIndex = nil
                    Logger.info("Lyrics removed")
                }
            } catch {
                Logger.error("Failed to remove lyrics: \(error)")
            }
        }
    }
}

