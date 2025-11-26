//
//  NotificationType.swift
//  HiFidelity
//
//  Created by Varun Rathod on 28/10/25.
//


import SwiftUI

// MARK: - Notification Types

enum NotificationType {
    case info
    case warning
    case error
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

extension NotificationType: Codable {}

struct NotificationMessage: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let timestamp: Date
    
    init(type: NotificationType, title: String) {
        self.type = type
        self.title = title
        self.timestamp = Date()
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var unreadCount = 0
    @Published var messages: [NotificationMessage] = []
    
    private let messagesKey = "NotificationTrayMessages"
    private let unreadCountKey = "NotificationTrayUnreadCount"
    
    private init() {
        loadPersistedMessages()
        loadUnreadCount()
    }
    
    
    // MARK: - Message Management
    
    func addMessage(_ type: NotificationType, _ title: String) {
        DispatchQueue.main.async {
            let message = NotificationMessage(type: type, title: title)
            self.messages.append(message)
            self.unreadCount += 1
            self.saveMessages()
            self.saveUnreadCount()
        }
    }
    
    func clearMessages() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.unreadCount = 0
            self.saveMessages()
            self.saveUnreadCount()
        }
    }
    
    func removeMessage(_ message: NotificationMessage) {
        DispatchQueue.main.async {
            self.messages.removeAll { $0.id == message.id }
            self.saveMessages()
        }
    }
    
    func markAllAsRead() {
        DispatchQueue.main.async {
            self.unreadCount = 0
            self.saveUnreadCount()
        }
    }
    
    
    // MARK: - Persistence
    
    private func saveMessages() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(messages) {
            UserDefaults.standard.set(encoded, forKey: messagesKey)
        }
    }
    
    private func loadPersistedMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesKey) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let decoded = try? decoder.decode([NotificationMessage].self, from: data) {
            messages = decoded
        }
    }
    
    private func saveUnreadCount() {
        UserDefaults.standard.set(unreadCount, forKey: unreadCountKey)
    }
    
    private func loadUnreadCount() {
        unreadCount = UserDefaults.standard.integer(forKey: unreadCountKey)
    }
}

// Make NotificationMessage conform to Codable for persistence
extension NotificationMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case type, title, timestamp
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(NotificationType.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}


// MARK: - Notification Tray View

struct NotificationTray: View {
    @StateObject private var manager = NotificationManager.shared
    @State private var showingPopover = false
    
    var body: some View {
        Button(action: {
            showingPopover.toggle()
            // Mark all as read when user opens the popover
            if showingPopover {
                manager.markAllAsRead()
            }
        }) {
            ZStack(alignment: .topTrailing) {
                // Notification icon
                Image(systemName: notificationIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.clear)
                    )
                
                // Unread count badge
                if manager.unreadCount > 0 {
                    Text("\(manager.unreadCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PlainHoverButtonStyle())
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            NotificationPopover(isPresented: $showingPopover)
        }
    }
    
    // MARK: - Computed Properties
    
    private var notificationIcon: String {
        if hasNotifications {
            "bell.fill"
        } else {
            "bell"
        }
    }
    
    private var hasNotifications: Bool {
        !manager.messages.isEmpty
    }
    
    
}

// MARK: - Notification Popover

struct NotificationPopover: View {
    @StateObject private var manager = NotificationManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notifications")
                    .font(.headline)
                
                if manager.unreadCount > 0 {
                    Text("(\(manager.unreadCount) new)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !manager.messages.isEmpty {
                    Button("Clear") {
                        manager.clearMessages()
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear all notifications")
                }
            }
            .padding(10)
            
            Divider()
            
            // Messages
            if manager.messages.isEmpty {
                emptyState
            } else {
                messagesList
            }
        }
        .frame(width: 350)
        .frame(maxHeight: 400)
        .onAppear {
            // Mark as read when popover appears
            manager.markAllAsRead()
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No notifications")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private var messagesList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(manager.messages.reversed()) { message in
                    NotificationRow(message: message) {
                        manager.removeMessage(message)
                    }
                    
                    if message.id != manager.messages.first?.id {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let message: NotificationMessage
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    
    private var timeAgoText: String {
        let now = Date()
        let interval = now.timeIntervalSince(message.timestamp)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.type.icon)
                .font(.system(size: 14))
                .foregroundColor(message.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(timeAgoText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isHovered {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}


// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        
        // With notifications
        NotificationTray()
            .onAppear {
                NotificationManager.shared.addMessage(.info, "2 folders refreshed for changes")
                NotificationManager.shared.addMessage(.warning, "1 folder couldn't be accessed")
                NotificationManager.shared.addMessage(.error, "Failed to scan Downloads folder")
            }
    }
    .padding()
}
