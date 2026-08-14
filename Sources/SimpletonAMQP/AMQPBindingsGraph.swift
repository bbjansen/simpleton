// Sources/SimpletonAMQP/AMQPBindingsGraph.swift
import Foundation

/// Pure, deterministic layout math for the bindings topology graph. No SwiftUI / geometry framework
/// dependency so the whole thing is testable from CoreChecks: given the exchanges, queues and
/// bindings for a vhost, it produces node positions in a normalized `[0, 1] × [0, 1]` space and the
/// list of edges between them. The view multiplies the normalized coordinates by the canvas size.
///
/// Layout is a two-column bipartite arrangement: exchanges in a left column, queues in a right
/// column, each ordered by name so the output is stable across refreshes. The nameless default
/// exchange is rendered as `(default)` and kept as a real node (bindings whose `source` is empty edge
/// from it). To stay readable for large topologies the builder caps how many nodes it draws per side
/// and reports the totals so the view can show a "showing N of M" note — never a silent truncation.
public enum AMQPBindingsGraph {
    /// A node in the topology (an exchange or a queue) with a normalized centre position.
    public struct Node: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            case exchange
            case queue
        }
        /// Stable identity: kind + name (unique within a vhost's two columns).
        public let id: String
        public let name: String
        public let kind: Kind
        /// Normalized centre in `[0, 1] × [0, 1]` (x grows left→right, y grows top→bottom).
        public let x: Double
        public let y: Double

        public init(name: String, kind: Kind, x: Double, y: Double) {
            self.id = "\(kind == .exchange ? "e" : "q"):\(name)"
            self.name = name
            self.kind = kind
            self.x = x
            self.y = y
        }
    }

    /// A labeled edge (a binding) between two laid-out nodes, referenced by node id.
    public struct Edge: Sendable, Equatable, Identifiable {
        public let id: String
        public let fromID: String
        public let toID: String
        /// The routing key drawn on the edge (empty for fanout / default-exchange bindings).
        public let label: String

        public init(id: String, fromID: String, toID: String, label: String) {
            self.id = id
            self.fromID = fromID
            self.toID = toID
            self.label = label
        }
    }

    /// The complete laid-out graph plus the pre-cap totals so the view can annotate truncation.
    public struct Layout: Sendable, Equatable {
        public let nodes: [Node]
        public let edges: [Edge]
        /// Total exchanges before the per-column cap (for the "showing N of M" note).
        public let totalExchanges: Int
        /// Total queues before the per-column cap.
        public let totalQueues: Int
        /// How many exchanges are drawn (== totalExchanges unless capped).
        public let shownExchanges: Int
        /// How many queues are drawn (== totalQueues unless capped).
        public let shownQueues: Int

        /// Whether either column was capped, so the view knows to show the truncation note.
        public var isTruncated: Bool {
            shownExchanges < totalExchanges || shownQueues < totalQueues
        }

        public init(
            nodes: [Node], edges: [Edge], totalExchanges: Int, totalQueues: Int,
            shownExchanges: Int, shownQueues: Int
        ) {
            self.nodes = nodes
            self.edges = edges
            self.totalExchanges = totalExchanges
            self.totalQueues = totalQueues
            self.shownExchanges = shownExchanges
            self.shownQueues = shownQueues
        }
    }

    /// The display name for the nameless default exchange.
    public static let defaultExchangeLabel = "(default)"

    /// The `x` of the exchange (left) column and the queue (right) column, in normalized space. Nodes
    /// sit inset from the canvas edges so labels have room.
    public static let exchangeColumnX = 0.16
    public static let queueColumnX = 0.84

    /// Evenly spaced `y` centres for `count` nodes stacked in a column, in normalized `[0, 1]`. One
    /// node centres at 0.5; N nodes are spread with equal top/bottom margin so the column is balanced.
    /// Returns an empty array for `count <= 0`.
    public static func columnYPositions(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [0.5] }
        // Slot i (0-based) centres at (i + 0.5) / count → equal margins, no node on the very edge.
        return (0..<count).map { (Double($0) + 0.5) / Double(count) }
    }

    /// Build the full deterministic layout. `exchangeNames` / `queueNames` are the raw names (the
    /// default exchange is an empty string in `exchangeNames`); `bindings` are `(source, destination,
    /// destinationType, routingKey)` tuples. `maxPerColumn` caps how many nodes are drawn per side
    /// (default 24); pass a larger value to draw everything.
    ///
    /// Ordering is by name (case-insensitive, with the default exchange sorted first) so the picture
    /// is stable across refreshes. Only edges whose *both* endpoints survive the cap are emitted, and
    /// only queue-destination bindings are drawn (exchange-to-exchange bindings are rare and would
    /// clutter the two-column picture — they are excluded and do not affect the queue count).
    public static func build(
        exchangeNames: [String], queueNames: [String],
        bindings: [(source: String, destination: String, destinationType: String, routingKey: String)],
        maxPerColumn: Int = 24
    ) -> Layout {
        let cap = max(1, maxPerColumn)

        // Sort exchanges by name, default ("") first; queues by name. Case-insensitive, stable.
        let sortedExchanges = exchangeNames.sorted { lhs, rhs in
            if lhs.isEmpty != rhs.isEmpty { return lhs.isEmpty }  // default exchange first
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        let sortedQueues = queueNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let shownExchangeNames = Array(sortedExchanges.prefix(cap))
        let shownQueueNames = Array(sortedQueues.prefix(cap))

        // Position each column.
        let exchangeY = columnYPositions(count: shownExchangeNames.count)
        let queueY = columnYPositions(count: shownQueueNames.count)

        var nodes: [Node] = []
        nodes.reserveCapacity(shownExchangeNames.count + shownQueueNames.count)
        for (i, name) in shownExchangeNames.enumerated() {
            nodes.append(Node(name: name, kind: .exchange, x: exchangeColumnX, y: exchangeY[i]))
        }
        for (i, name) in shownQueueNames.enumerated() {
            nodes.append(Node(name: name, kind: .queue, x: queueColumnX, y: queueY[i]))
        }

        // Index the drawn nodes so edges reference existing endpoints only.
        let exchangeIDs = Set(shownExchangeNames.map { Node(name: $0, kind: .exchange, x: 0, y: 0).id })
        let queueIDs = Set(shownQueueNames.map { Node(name: $0, kind: .queue, x: 0, y: 0).id })

        var edges: [Edge] = []
        var seen = Set<String>()
        for b in bindings {
            // Only draw exchange→queue edges in the two-column picture.
            guard b.destinationType == "queue" else { continue }
            let fromID = Node(name: b.source, kind: .exchange, x: 0, y: 0).id
            let toID = Node(name: b.destination, kind: .queue, x: 0, y: 0).id
            guard exchangeIDs.contains(fromID), queueIDs.contains(toID) else { continue }
            // Collapse duplicate source→dest→routingKey edges (RabbitMQ can report several).
            let key = "\(fromID)->\(toID)#\(b.routingKey)"
            guard seen.insert(key).inserted else { continue }
            edges.append(Edge(id: key, fromID: fromID, toID: toID, label: b.routingKey))
        }

        return Layout(
            nodes: nodes, edges: edges,
            totalExchanges: sortedExchanges.count, totalQueues: sortedQueues.count,
            shownExchanges: shownExchangeNames.count, shownQueues: shownQueueNames.count)
    }
}
