// Sources/SimpletonAMQP/AMQPMetricsHistory.swift
import Foundation

/// One sampled point of a node's live metrics, taken on each auto-refresh. Values are optional
/// because a down node (or an older broker) omits them; the chart skips missing points.
public struct NodeMetricSample: Sendable, Equatable {
    /// Monotonic sample index (0, 1, 2, …) assigned on append — the chart's x-axis. Independent of
    /// wall-clock so gaps in refresh cadence don't distort spacing.
    public let sequence: Int
    public let memUsed: Int?
    public let fdUsed: Int?

    public init(sequence: Int, memUsed: Int?, fdUsed: Int?) {
        self.sequence = sequence
        self.memUsed = memUsed
        self.fdUsed = fdUsed
    }
}

/// A fixed-capacity ring buffer of recent `NodeMetricSample`s for a single node. Appending past
/// capacity drops the oldest sample (bounded memory for a long-running monitor). Pure value type —
/// no timers, no I/O — so it is fully testable from CoreChecks.
public struct NodeMetricRing: Sendable, Equatable {
    /// Maximum samples retained. Clamped to at least 1.
    public let capacity: Int
    private var storage: [NodeMetricSample]
    /// The next sequence number to assign (also the running total ever appended).
    private var nextSequence: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = []
        self.storage.reserveCapacity(self.capacity)
        self.nextSequence = 0
    }

    /// Samples currently retained, oldest→newest.
    public var samples: [NodeMetricSample] { storage }

    /// How many samples are retained (≤ capacity).
    public var count: Int { storage.count }

    /// Whether any samples have been recorded.
    public var isEmpty: Bool { storage.isEmpty }

    /// The most recently appended sample, if any.
    public var latest: NodeMetricSample? { storage.last }

    /// Append a reading; assigns the next sequence number and evicts the oldest sample if full.
    public mutating func append(memUsed: Int?, fdUsed: Int?) {
        let sample = NodeMetricSample(sequence: nextSequence, memUsed: memUsed, fdUsed: fdUsed)
        nextSequence += 1
        storage.append(sample)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    /// The most recent `window` samples, oldest→newest (all of them if fewer are retained). A
    /// non-positive window returns an empty array.
    public func window(_ window: Int) -> [NodeMetricSample] {
        guard window > 0 else { return [] }
        if window >= storage.count { return storage }
        return Array(storage.suffix(window))
    }
}

/// A collection of per-node metric rings, keyed by node name, with each node's history isolated from
/// the others. Populated on each panel auto-refresh from the `nodes()` response. In-memory only —
/// history resets when the panel is closed / the model is recreated, which is the intended behavior
/// for a live monitor (no persistence layer, no disk writes). Pure value type; testable.
public struct NodeMetricsHistory: Sendable, Equatable {
    /// Per-node retained-sample capacity (e.g. 60 samples ≈ 5 minutes at a 5 s refresh).
    public let capacity: Int
    private var rings: [String: NodeMetricRing]

    public init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
        self.rings = [:]
    }

    /// The set of node names that currently have history.
    public var nodeNames: [String] { Array(rings.keys) }

    /// The ring for a node, or nil if the node has no history yet.
    public func ring(for node: String) -> NodeMetricRing? { rings[node] }

    /// The retained samples for a node, oldest→newest (empty if unknown).
    public func samples(for node: String) -> [NodeMetricSample] {
        rings[node]?.samples ?? []
    }

    /// Record one reading for a node, creating its ring on first sight. Each node's ring advances its
    /// own sequence, so per-node series never interleave.
    public mutating func record(node: String, memUsed: Int?, fdUsed: Int?) {
        var ring = rings[node] ?? NodeMetricRing(capacity: capacity)
        ring.append(memUsed: memUsed, fdUsed: fdUsed)
        rings[node] = ring
    }
}
