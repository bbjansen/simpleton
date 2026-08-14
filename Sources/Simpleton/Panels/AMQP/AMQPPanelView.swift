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
            // Constant interval: the scaffold schedules its timer once at .onAppear, and a dynamic
            // value would never re-arm on connect. refresh()/reload() no-op while disconnected.
            autoRefresh: 5,
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
        .alert(item: $model.deleteQueueTarget) { queue in
            Alert(
                title: Text("Delete queue \(queue.name)?"),
                message: Text("This permanently deletes the queue and all \(queue.messages) message(s) in it."),
                primaryButton: .destructive(Text("Delete")) { Task { await model.deleteQueue(queue) } },
                secondaryButton: .cancel())
        }
        .alert(item: $model.deleteExchangeTarget) { exchange in
            Alert(
                title: Text("Delete exchange \(exchange.name.isEmpty ? "(default)" : exchange.name)?"),
                message: Text("This permanently deletes the exchange. Bindings to it are removed."),
                primaryButton: .destructive(Text("Delete")) { Task { await model.deleteExchange(exchange) } },
                secondaryButton: .cancel())
        }
        .sheet(isPresented: $model.showingNewQueue) {
            AMQPNewQueueSheet(onCreate: { spec in Task { await model.createQueue(spec) } })
        }
        .sheet(isPresented: $model.showingNewExchange) {
            AMQPNewExchangeSheet(onCreate: { spec in Task { await model.createExchange(spec) } })
        }
        .sheet(isPresented: $model.showingNewBinding) {
            AMQPNewBindingSheet(
                exchanges: model.exchanges.map(\.name), queues: model.queues.map(\.name),
                onCreate: { spec in Task { await model.createBinding(spec) } })
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
        HStack(spacing: 6) {
            Picker("", selection: $model.tab) {
                ForEach(AMQPTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            addButton
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    /// A contextual "+" for the create-capable tabs (Queues, Exchanges, Bindings). Hidden while
    /// disconnected or on read-only tabs.
    @ViewBuilder
    private var addButton: some View {
        if model.isConnected, let action = addAction {
            Button {
                action.perform()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain).help(action.help)
        }
    }

    private struct AddAction {
        let help: String
        let perform: () -> Void
    }

    private var addAction: AddAction? {
        switch model.tab {
        case .queues:
            return AddAction(help: "New queue") { model.showingNewQueue = true }
        case .exchanges:
            return AddAction(help: "New exchange") { model.showingNewExchange = true }
        case .bindings:
            return AddAction(help: "New binding") { model.showingNewBinding = true }
        case .connections, .channels, .nodes:
            return nil
        }
    }

    @ViewBuilder
    private var table: some View {
        switch model.tab {
        case .queues: queuesTable
        case .exchanges: exchangesTable
        case .bindings: bindingsTable
        case .connections: connectionsTable
        case .channels: channelsTable
        case .nodes: nodesTable
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
            .contextMenu {
                Button {
                    Task { await model.getMessages(for: queue) }
                } label: {
                    Label("Peek messages", systemImage: "eye")
                }
                Button {
                    model.publishTarget = queue
                } label: {
                    Label("Publish…", systemImage: "paperplane")
                }
                Button {
                    model.purgeTarget = queue
                } label: {
                    Label("Purge", systemImage: "trash")
                }
                Divider()
                Button(role: .destructive) {
                    model.deleteQueueTarget = queue
                } label: {
                    Label("Delete queue", systemImage: "trash.slash")
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
            Button {
                model.deleteQueueTarget = queue
            } label: {
                Image(systemName: "trash.slash").foregroundColor(DT.accentRed)
            }
            .buttonStyle(.plain).help("Delete queue")
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
                // The default and reserved amq.* exchanges cannot be deleted; hide the affordance.
                if isDeletableExchange(ex) {
                    Button {
                        model.deleteExchangeTarget = ex
                    } label: {
                        Image(systemName: "trash").foregroundColor(DT.accentRed)
                    }
                    .buttonStyle(.plain).help("Delete exchange")
                }
            }
            .contextMenu {
                if isDeletableExchange(ex) {
                    Button(role: .destructive) {
                        model.deleteExchangeTarget = ex
                    } label: {
                        Label("Delete exchange", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// The nameless default exchange and the broker-reserved `amq.*` exchanges are not user-deletable.
    private func isDeletableExchange(_ ex: ExchangeInfo) -> Bool {
        !ex.name.isEmpty && !ex.name.hasPrefix("amq.")
    }

    private var bindingsTable: some View {
        listOrEmpty(model.bindings, empty: "No bindings in this vhost.") { b in
            HStack(spacing: 8) {
                Text(b.source.isEmpty ? "(default)" : b.source)
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textPrimary).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundColor(DT.textTertiary)
                Text(b.destination).font(DT.monoFont(size: 11)).foregroundColor(DT.textPrimary).lineLimit(1)
                tag(b.destinationType)
                Spacer()
                if !b.routingKey.isEmpty { metric("rk", b.routingKey) }
            }
        }
    }

    private var nodesTable: some View {
        listOrEmpty(model.nodes, empty: "No nodes reported.") { n in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Circle().fill(n.running ? DT.accentGreen : DT.textFaint).frame(width: 7, height: 7)
                    Text(n.name).font(DT.monoFont(size: 11)).fontWeight(.semibold)
                        .foregroundColor(DT.textPrimary).lineLimit(1)
                    Spacer()
                    if let up = n.uptime { metric("uptime", uptimeString(up)) }
                }
                HStack(spacing: 8) {
                    if let used = n.memUsed { metric("mem", byteString(used)) }
                    if let used = n.memUsed, let limit = n.memLimit, limit > 0 {
                        metric("mem %", String(format: "%.0f%%", Double(used) / Double(limit) * 100))
                    }
                    if let free = n.diskFree { metric("disk free", byteString(free)) }
                    if let used = n.fdUsed, let total = n.fdTotal { metric("fd", "\(used)/\(total)") }
                    if let sockets = n.socketsUsed { metric("sockets", "\(sockets)") }
                    if let procs = n.procUsed { metric("procs", "\(procs)") }
                }
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
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }

    /// Format an uptime given in milliseconds as a compact `Nd Nh` / `Nh Nm` / `Nm` string.
    private func uptimeString(_ millis: Int) -> String {
        let seconds = millis / 1000
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
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

/// Declare a new queue, with optional message-TTL and dead-letter (DLX) policy arguments.
struct AMQPNewQueueSheet: View {
    let onCreate: (NewQueueSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var spec = NewQueueSpec()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New queue").font(.headline).foregroundColor(DT.textPrimary)
            field("Name") {
                TextField("queue name", text: $spec.name).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 16) {
                Toggle("Durable", isOn: $spec.durable)
                Toggle("Auto-delete", isOn: $spec.autoDelete)
                Spacer()
            }
            .toggleStyle(.checkbox).font(.system(size: 11)).foregroundColor(DT.textSecondary)
            ThemedDivider()
            Text("Arguments (optional)").font(.system(size: 11, weight: .semibold))
                .foregroundColor(DT.textSecondary)
            field("Message TTL (ms) — x-message-ttl") {
                TextField("e.g. 60000", text: $spec.messageTTL).textFieldStyle(.roundedBorder)
            }
            field("Dead-letter exchange — x-dead-letter-exchange") {
                TextField("exchange name", text: $spec.deadLetterExchange).textFieldStyle(.roundedBorder)
            }
            field("Dead-letter routing key — x-dead-letter-routing-key") {
                TextField("routing key", text: $spec.deadLetterRoutingKey).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(spec)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).tint(DT.accent)
                .disabled(spec.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16).frame(width: 440)
        .background(DT.base)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundColor(DT.textSecondary)
            content()
        }
    }
}

/// Declare a new exchange of a chosen type.
struct AMQPNewExchangeSheet: View {
    let onCreate: (NewExchangeSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var spec = NewExchangeSpec()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New exchange").font(.headline).foregroundColor(DT.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                TextField("exchange name", text: $spec.name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Type").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                Picker("", selection: $spec.type) {
                    ForEach(NewExchangeSpec.types, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            HStack(spacing: 16) {
                Toggle("Durable", isOn: $spec.durable)
                Toggle("Auto-delete", isOn: $spec.autoDelete)
                Spacer()
            }
            .toggleStyle(.checkbox).font(.system(size: 11)).foregroundColor(DT.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(spec)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).tint(DT.accent)
                .disabled(spec.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16).frame(width: 420)
        .background(DT.base)
    }
}

/// Bind a queue to a source exchange with a routing key.
struct AMQPNewBindingSheet: View {
    let exchanges: [String]
    let queues: [String]
    let onCreate: (NewBindingSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var spec = NewBindingSpec()

    /// Source exchanges excluding the nameless default (a binding to the default exchange is implicit).
    private var bindableExchanges: [String] { exchanges.filter { !$0.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New binding").font(.headline).foregroundColor(DT.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Source exchange").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                if bindableExchanges.isEmpty {
                    TextField("exchange name", text: $spec.source).textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $spec.source) {
                        Text("Select…").tag("")
                        ForEach(bindableExchanges, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination queue").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                if queues.isEmpty {
                    TextField("queue name", text: $spec.destination).textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $spec.destination) {
                        Text("Select…").tag("")
                        ForEach(queues, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Routing key").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                TextField("routing key", text: $spec.routingKey).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(spec)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).tint(DT.accent)
                .disabled(
                    spec.source.trimmingCharacters(in: .whitespaces).isEmpty
                        || spec.destination.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16).frame(width: 420)
        .background(DT.base)
    }
}
