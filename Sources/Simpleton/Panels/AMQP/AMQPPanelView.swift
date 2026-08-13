// Sources/Simpleton/Panels/AMQP/AMQPPanelView.swift
import SimpletonAMQP
import SimpletonCore
import SwiftUI

/// The AMQP (RabbitMQ) management panel: connection picker + a segmented view over Queues,
/// Exchanges, Connections and Channels, with peek/publish/purge actions on a queue. Hosted in the
/// shared client-panel chrome and mirrors the SQL client's lifecycle.
struct AMQPPanelView: View {
    @StateObject private var model: AMQPPanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    init(appSupportDir: URL) {
        _model = StateObject(wrappedValue: AMQPPanelModel(appSupportDir: appSupportDir))
    }

    var body: some View {
        ClientPanelScaffold(
            title: "AMQP",
            availability: model.availability,
            autoRefresh: model.isConnected ? 5 : nil,
            onRefresh: { await model.isConnected ? model.refresh() : model.reload() }
        ) {
            content
        }
        .sheet(isPresented: $model.showingEditor) {
            DataConnectionEditor(
                bookmarks: [], existingGroups: [], existing: nil,
                onSave: { connection, secret in
                    Task { await model.saveConnection(connection, secret: secret) }
                })
        }
        .sheet(isPresented: messagePreviewBinding) {
            AMQPMessagePreviewSheet(
                queue: model.messagePreviewQueue ?? "",
                messages: model.messagePreview ?? [])
        }
        .sheet(item: $model.publishTarget) { queue in
            AMQPPublishSheet(
                defaultRoutingKey: queue.name,
                onPublish: { exchange, routingKey, payload in
                    Task { await model.publish(exchange: exchange, routingKey: routingKey, payload: payload) }
                })
        }
        .alert(item: $model.purgeTarget) { queue in
            Alert(
                title: Text("Purge \(queue.name)?"),
                message: Text("This permanently deletes all \(queue.messages) message(s) in the queue."),
                primaryButton: .destructive(Text("Purge")) { Task { await model.purge(queue) } },
                secondaryButton: .cancel())
        }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonOpenConnectionGUI)) { _ in
            Task { await model.consumePendingOpen() }  // warm: panel already mounted
        }
        .task {
            await model.consumePendingOpen()  // cold: panel just mounted via reveal
        }
        .themedGlass(DT.surface)
    }

    /// The message-preview sheet has no `Identifiable` item, so drive it with a presence binding.
    private var messagePreviewBinding: Binding<Bool> {
        Binding(
            get: { model.messagePreview != nil },
            set: { if !$0 { model.messagePreview = nil } })
    }

    private var content: some View {
        VStack(spacing: 0) {
            connectionBar
            ThemedDivider()
            overviewBar
            tabPicker
            ThemedDivider()
            table
            if let err = model.errorMessage, model.isConnected {
                ThemedDivider()
                Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $model.selectedID) {
                Text("Select…").tag(UUID?.none)
                ForEach(model.connections, id: \.id) { c in
                    Text("\(c.name) (\(c.kind.displayName))").tag(UUID?.some(c.id))
                }
            }
            .labelsHidden()
            .onChange(of: model.selectedID) { Task { await model.connectSelected() } }
            Button(model.isConnected ? "Disconnect" : "Connect") {
                Task { model.isConnected ? await model.disconnect() : await model.connect() }
            }
            .disabled(model.selectedID == nil || model.isConnecting)
            Button {
                model.showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain).help("New connection")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    @ViewBuilder
    private var overviewBar: some View {
        if let o = model.overview {
            HStack(spacing: 10) {
                statChip("RabbitMQ", o.rabbitmqVersion)
                statChip("msgs", "\(o.totalMessages)")
                statChip("ready", "\(o.totalMessagesReady)")
                statChip("unacked", "\(o.totalMessagesUnacked)")
                statChip("conns", "\(o.totalConnections)")
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundColor(DT.textTertiary)
            Text(value).font(DT.monoFont(size: 10)).foregroundColor(DT.textSecondary)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $model.tab) {
            ForEach(AMQPTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    @ViewBuilder
    private var table: some View {
        switch model.tab {
        case .queues: queuesTable
        case .exchanges: exchangesTable
        case .connections: connectionsTable
        case .channels: channelsTable
        }
    }

    // MARK: - Tables

    private var queuesTable: some View {
        listOrEmpty(model.queues, empty: "No queues in this vhost.") { queue in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Circle().fill(queue.state == "running" ? DT.accentGreen : DT.textFaint)
                        .frame(width: 7, height: 7)
                    Text(queue.name.isEmpty ? "(unnamed)" : queue.name)
                        .font(DT.monoFont(size: 11)).fontWeight(.semibold)
                        .foregroundColor(DT.textPrimary).lineLimit(1)
                    Spacer()
                    queueActions(queue)
                }
                HStack(spacing: 8) {
                    metric("ready", "\(queue.messagesReady)")
                    metric("unacked", "\(queue.messagesUnacked)")
                    metric("total", "\(queue.messages)")
                    metric("consumers", "\(queue.consumers)")
                    if let pr = queue.publishRate { metric("in/s", String(format: "%.1f", pr)) }
                    if let dr = queue.deliverRate { metric("out/s", String(format: "%.1f", dr)) }
                }
            }
        }
    }

    private func queueActions(_ queue: QueueInfo) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.getMessages(for: queue) }
            } label: {
                Image(systemName: "eye").foregroundColor(DT.textSecondary)
            }
            .buttonStyle(.plain).help("Get messages (peek)")
            Button {
                model.publishTarget = queue
            } label: {
                Image(systemName: "paperplane").foregroundColor(DT.textSecondary)
            }
            .buttonStyle(.plain).help("Publish a message")
            Button {
                model.purgeTarget = queue
            } label: {
                Image(systemName: "trash").foregroundColor(DT.accentRed)
            }
            .buttonStyle(.plain).help("Purge queue")
        }
    }

    private var exchangesTable: some View {
        listOrEmpty(model.exchanges, empty: "No exchanges in this vhost.") { ex in
            HStack {
                Text(ex.name.isEmpty ? "(default)" : ex.name)
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textPrimary).lineLimit(1)
                Spacer()
                metric("type", ex.type)
                if ex.durable { tag("durable") }
                if ex.autoDelete { tag("auto-delete") }
            }
        }
    }

    private var connectionsTable: some View {
        listOrEmpty(model.brokerConnections, empty: "No client connections.") { conn in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Circle().fill(conn.state == "running" ? DT.accentGreen : DT.textFaint)
                        .frame(width: 7, height: 7)
                    Text(conn.name).font(DT.monoFont(size: 10)).foregroundColor(DT.textPrimary).lineLimit(1)
                    Spacer()
                }
                HStack(spacing: 8) {
                    metric("user", conn.user)
                    metric("channels", "\(conn.channels)")
                    if let r = conn.recvOct { metric("recv", byteString(r)) }
                    if let s = conn.sendOct { metric("send", byteString(s)) }
                }
            }
        }
    }

    private var channelsTable: some View {
        listOrEmpty(model.channels, empty: "No channels.") { ch in
            VStack(alignment: .leading, spacing: 3) {
                Text(ch.name).font(DT.monoFont(size: 10)).foregroundColor(DT.textPrimary).lineLimit(1)
                HStack(spacing: 8) {
                    metric("#", "\(ch.number)")
                    metric("consumers", "\(ch.consumerCount)")
                    metric("unacked", "\(ch.unacked)")
                    metric("prefetch", "\(ch.prefetch)")
                    metric("state", ch.state)
                }
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], empty: String, @ViewBuilder row: @escaping (T) -> Row
    ) -> some View {
        if items.isEmpty {
            PanelEmptyStateView(icon: "arrow.left.arrow.right", title: "Nothing here", message: empty)
        } else {
            List(items) { item in
                row(item).listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundColor(DT.textTertiary)
            Text(value).font(DT.monoFont(size: 10)).foregroundColor(DT.textSecondary).lineLimit(1)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9)).foregroundColor(DT.textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(DT.elevated).cornerRadius(4)
    }

    private func byteString(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Sheets

/// Read-only preview of peeked messages (non-destructive: they were requeued).
struct AMQPMessagePreviewSheet: View {
    let queue: String
    let messages: [MessagePreview]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages — \(queue)").font(.headline).foregroundColor(DT.textPrimary)
                Spacer()
                Button("Close") { dismiss() }.tint(DT.accent)
            }
            .padding()
            ThemedDivider()
            if messages.isEmpty {
                PanelEmptyStateView(
                    icon: "tray", title: "No messages",
                    message: "The queue is empty (nothing was consumed — this is a peek)."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages.indices, id: \.self) { i in
                            messageCard(messages[i], index: i)
                        }
                    }
                    .padding(8)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 560, height: 420)
        .background(DT.surface)
    }

    private func messageCard(_ m: MessagePreview, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(index + 1)").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.textTertiary)
                if !m.routingKey.isEmpty {
                    Text("rk: \(m.routingKey)").font(DT.monoFont(size: 10)).foregroundColor(DT.textSecondary)
                }
                if m.redelivered {
                    Text("redelivered").font(.system(size: 9)).foregroundColor(DT.accentAmber)
                }
                Spacer()
                Text("\(m.payloadBytes) B").font(.system(size: 9)).foregroundColor(DT.textTertiary)
            }
            Text(m.payload)
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !m.properties.isEmpty {
                Text(m.properties.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
                    .font(DT.monoFont(size: 9)).foregroundColor(DT.textTertiary)
            }
        }
        .padding(8)
        .background(DT.elevated).cornerRadius(DT.radiusCard)
    }
}

/// Compose + publish a message to an exchange with a routing key.
struct AMQPPublishSheet: View {
    let defaultRoutingKey: String
    let onPublish: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var exchange = ""
    @State private var routingKey = ""
    @State private var payload = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish message").font(.headline).foregroundColor(DT.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Exchange (blank = default exchange)").font(.system(size: 11))
                    .foregroundColor(DT.textSecondary)
                TextField("exchange", text: $exchange).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Routing key").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                TextField("routing key", text: $routingKey).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Payload").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                TextEditor(text: $payload)
                    .font(DT.monoFont(size: 12)).frame(height: 100)
                    .scrollContentBackground(.hidden)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(DT.border, lineWidth: 1))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Publish") {
                    onPublish(exchange, routingKey, payload)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).tint(DT.accent)
                .disabled(payload.isEmpty)
            }
        }
        .padding(16).frame(width: 420)
        .background(DT.base)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Default routing key to the queue name so a direct-exchange publish reaches it.
            routingKey = defaultRoutingKey
        }
    }
}
