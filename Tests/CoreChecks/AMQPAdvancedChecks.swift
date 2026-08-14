// Tests/CoreChecks/AMQPAdvancedChecks.swift
import Foundation
import SimpletonAMQP
import SimpletonCore

func runAMQPAdvancedChecks(_ t: TestRunner) async {
    // MARK: Policy request-path construction — /api/policies/{vhost}/{name} with %2F.
    t.suite("RabbitMQ policy paths") {
        t.expectEqual(
            RabbitMQManagementDriver.policyPath(vhost: "/", name: "ttl"),
            "/api/policies/%2F/ttl", "policy path: default vhost encoded")
        t.expectEqual(
            RabbitMQManagementDriver.policyPath(vhost: "prod", name: "a/b"),
            "/api/policies/prod/a%2Fb", "policy path: slash in name encoded")
        t.expectEqual(
            RabbitMQManagementDriver.policyPath(vhost: "my vhost", name: "dlx.policy"),
            "/api/policies/my%20vhost/dlx.policy", "policy path: space in vhost, dot preserved")
    }

    // MARK: putPolicy JSON body — pattern/apply-to/priority + typed definition values.
    t.suite("putPolicy JSON body") {
        // Mirror the driver's body so the shape is asserted without a live broker.
        struct PolicyBody: Encodable {
            let pattern: String
            let applyTo: String
            let definition: [String: PolicyValue]
            let priority: Int
            enum CodingKeys: String, CodingKey {
                case pattern
                case applyTo = "apply-to"
                case definition
                case priority
            }
        }
        let body = PolicyBody(
            pattern: "^orders\\.", applyTo: "queues",
            definition: [
                "message-ttl": .int(60000),
                "dead-letter-exchange": .string("dlx"),
                "max-length": .int(10000),
            ], priority: 5)
        do {
            let data = try JSONEncoder().encode(body)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                t.expect(false, "policy body should be a JSON object")
                return
            }
            t.expectEqual(obj["pattern"] as? String, "^orders\\.", "pattern")
            t.expectEqual(obj["apply-to"] as? String, "queues", "apply-to (hyphenated key)")
            t.expectEqual(obj["priority"] as? Int, 5, "priority")
            guard let def = obj["definition"] as? [String: Any] else {
                t.expect(false, "definition should be a nested object")
                return
            }
            // message-ttl must serialize as an integer, not a string — a common serialization bug.
            t.expectEqual(def["message-ttl"] as? Int, 60000, "message-ttl is an Int")
            t.expect(!(def["message-ttl"] is String), "message-ttl not a String")
            t.expectEqual(def["max-length"] as? Int, 10000, "max-length is an Int")
            t.expectEqual(def["dead-letter-exchange"] as? String, "dlx", "dead-letter-exchange is a String")
        } catch {
            t.expect(false, "putPolicy body encode failed: \(error)")
        }

        // An empty definition still serializes an object (broker treats it as a no-op policy).
        do {
            let data = try JSONEncoder().encode(
                PolicyBody(pattern: ".*", applyTo: "all", definition: [:], priority: 0))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let def = obj["definition"] as? [String: Any]
            else {
                t.expect(false, "empty-definition body should still carry a definition object")
                return
            }
            t.expectEqual(def.count, 0, "no definition entries → empty object")
        } catch {
            t.expect(false, "empty-definition body encode failed: \(error)")
        }
    }

    // MARK: Codable decode of sample /api/policies JSON.
    t.suite("PolicyInfo decode") {
        let json = """
            [
              {"vhost":"/","name":"ttl-orders","pattern":"^orders\\\\.","apply-to":"queues",
               "definition":{"message-ttl":60000,"dead-letter-exchange":"dlx"},"priority":5},
              {"vhost":"prod","name":"cap","pattern":".*","apply-to":"all",
               "definition":{"max-length":1000},"priority":0}
            ]
            """
        do {
            let policies = try JSONDecoder().decode([PolicyInfo].self, from: Data(json.utf8))
            t.expectEqual(policies.count, 2, "two policies")
            let p = policies[0]
            t.expectEqual(p.vhost, "/", "vhost")
            t.expectEqual(p.name, "ttl-orders", "name")
            t.expectEqual(p.pattern, "^orders\\.", "pattern")
            t.expectEqual(p.applyTo, "queues", "apply-to → applyTo")
            t.expectEqual(p.priority, 5, "priority")
            t.expectEqual(p.definition["message-ttl"], .int(60000), "definition message-ttl Int")
            t.expectEqual(
                p.definition["dead-letter-exchange"], .string("dlx"),
                "definition dead-letter-exchange String")
            t.expectEqual(p.id, "//ttl-orders", "id = vhost/name")
            t.expectEqual(policies[1].definition["max-length"], .int(1000), "second policy max-length Int")
        } catch {
            t.expect(false, "PolicyInfo decode failed: \(error)")
        }

        // A policy with missing optional fields decodes with tolerant defaults.
        let sparse = """
            [{"name":"minimal"}]
            """
        do {
            let p = try JSONDecoder().decode([PolicyInfo].self, from: Data(sparse.utf8))[0]
            t.expectEqual(p.vhost, "/", "missing vhost → /")
            t.expectEqual(p.pattern, "", "missing pattern → empty")
            t.expectEqual(p.applyTo, "all", "missing apply-to → all")
            t.expectEqual(p.priority, 0, "missing priority → 0")
            t.expect(p.definition.isEmpty, "missing definition → empty map")
        } catch {
            t.expect(false, "sparse PolicyInfo decode failed: \(error)")
        }
    }

    // MARK: PolicyValue round-trips (Int stays Int; String stays String; bool → 0/1).
    t.suite("PolicyValue coding") {
        do {
            let intData = try JSONEncoder().encode(PolicyValue.int(42))
            t.expectEqual(String(data: intData, encoding: .utf8), "42", "int encodes bare")
            let strData = try JSONEncoder().encode(PolicyValue.string("dlx"))
            t.expectEqual(String(data: strData, encoding: .utf8), "\"dlx\"", "string encodes quoted")
        } catch {
            t.expect(false, "PolicyValue encode failed: \(error)")
        }
        // Decode: whole number → .int; quoted → .string; true → .int(1); 2.0 → .int(2). A JSON array
        // of PolicyValue exercises the singleValueContainer decode path directly.
        do {
            let decoded = try JSONDecoder().decode(
                [PolicyValue].self, from: Data("[100,\"x\",true,2.0]".utf8))
            t.expectEqual(decoded.count, 4, "four values decode")
            t.expectEqual(decoded[0], .int(100), "100 → .int")
            t.expectEqual(decoded[1], .string("x"), "\"x\" → .string")
            t.expectEqual(decoded[2], .int(1), "true → .int(1)")
            t.expectEqual(decoded[3], .int(2), "2.0 → .int(2)")
        } catch {
            t.expect(false, "PolicyValue decode failed: \(error)")
        }
    }

    // MARK: Graph layout math — pure column positions + build().
    t.suite("Bindings graph layout") {
        // columnYPositions: even spacing, one centred, none on the edges.
        t.expect(AMQPBindingsGraph.columnYPositions(count: 0).isEmpty, "0 → empty")
        t.expectEqual(AMQPBindingsGraph.columnYPositions(count: 1), [0.5], "1 → centred")
        let two = AMQPBindingsGraph.columnYPositions(count: 2)
        t.expectEqual(two.count, 2, "2 → two slots")
        t.expectEqual(two[0], 0.25, "2 → first at 0.25")
        t.expectEqual(two[1], 0.75, "2 → second at 0.75")
        let four = AMQPBindingsGraph.columnYPositions(count: 4)
        t.expectEqual(four, [0.125, 0.375, 0.625, 0.875], "4 → even eighths")
        // All strictly inside (0, 1) and monotonically increasing.
        t.expect(four.allSatisfy { $0 > 0 && $0 < 1 }, "4 → all strictly inside (0,1)")
        t.expect(zip(four, four.dropFirst()).allSatisfy { $0 < $1 }, "4 → increasing")

        // build(): exchanges left, queues right, ordered by name (default exchange first).
        let layout = AMQPBindingsGraph.build(
            exchangeNames: ["events", "", "amq.direct"],
            queueNames: ["orders", "audit"],
            bindings: [
                (source: "", destination: "orders", destinationType: "queue", routingKey: "orders"),
                (source: "events", destination: "audit", destinationType: "queue", routingKey: "e.#"),
                // exchange→exchange binding is excluded from the two-column picture.
                (source: "events", destination: "amq.direct", destinationType: "exchange", routingKey: "x"),
            ])
        let exchangeNodes = layout.nodes.filter { $0.kind == .exchange }
        let queueNodes = layout.nodes.filter { $0.kind == .queue }
        t.expectEqual(exchangeNodes.count, 3, "three exchange nodes")
        t.expectEqual(queueNodes.count, 2, "two queue nodes")
        t.expectEqual(exchangeNodes.first?.name, "", "default (empty) exchange sorts first")
        t.expectEqual(exchangeNodes.map(\.name), ["", "amq.direct", "events"], "exchanges name-sorted")
        t.expectEqual(queueNodes.map(\.name), ["audit", "orders"], "queues name-sorted")
        // Exchanges pinned to the left column, queues to the right.
        t.expect(exchangeNodes.allSatisfy { $0.x == AMQPBindingsGraph.exchangeColumnX }, "exchanges left column")
        t.expect(queueNodes.allSatisfy { $0.x == AMQPBindingsGraph.queueColumnX }, "queues right column")
        // Only the two queue-destination bindings become edges (exchange→exchange dropped).
        t.expectEqual(layout.edges.count, 2, "two queue-destination edges")
        t.expect(layout.edges.contains { $0.label == "orders" }, "default→orders edge with routing key")
        t.expect(layout.edges.contains { $0.label == "e.#" }, "events→audit edge with routing key")
        t.expect(!layout.isTruncated, "small topology not truncated")

        // Layout is deterministic: same inputs → identical output.
        let again = AMQPBindingsGraph.build(
            exchangeNames: ["amq.direct", "", "events"],  // different input order
            queueNames: ["audit", "orders"],
            bindings: [
                (source: "", destination: "orders", destinationType: "queue", routingKey: "orders"),
                (source: "events", destination: "audit", destinationType: "queue", routingKey: "e.#"),
            ])
        t.expectEqual(again.nodes, layout.nodes, "layout is deterministic regardless of input order")

        // Cap: more nodes than maxPerColumn are drawn up to the cap, totals reported, no silent drop.
        let manyExchanges = (0..<10).map { "ex-\($0)" }
        let manyQueues = (0..<10).map { "q-\($0)" }
        let capped = AMQPBindingsGraph.build(
            exchangeNames: manyExchanges, queueNames: manyQueues, bindings: [], maxPerColumn: 3)
        t.expectEqual(capped.shownExchanges, 3, "capped to 3 exchanges")
        t.expectEqual(capped.shownQueues, 3, "capped to 3 queues")
        t.expectEqual(capped.totalExchanges, 10, "reports 10 total exchanges")
        t.expectEqual(capped.totalQueues, 10, "reports 10 total queues")
        t.expect(capped.isTruncated, "capped layout is flagged truncated")
        // An edge whose endpoint was dropped by the cap is not drawn.
        let cappedEdges = AMQPBindingsGraph.build(
            exchangeNames: manyExchanges, queueNames: manyQueues,
            bindings: [
                (source: "ex-9", destination: "q-9", destinationType: "queue", routingKey: "k")
            ], maxPerColumn: 3)
        t.expect(cappedEdges.edges.isEmpty, "edge to a capped-out node is not drawn")

        // Empty inputs → empty layout.
        let empty = AMQPBindingsGraph.build(exchangeNames: [], queueNames: [], bindings: [])
        t.expect(empty.nodes.isEmpty, "no nodes → empty node list")
        t.expect(empty.edges.isEmpty, "no nodes → empty edge list")
    }

    // MARK: Metrics ring buffer — append/cap, windowed read, per-node isolation.
    t.suite("Node metrics ring") {
        var ring = NodeMetricRing(capacity: 3)
        t.expect(ring.isEmpty, "new ring is empty")
        t.expectEqual(ring.count, 0, "new ring count 0")
        ring.append(memUsed: 100, fdUsed: 1)
        ring.append(memUsed: 200, fdUsed: 2)
        ring.append(memUsed: 300, fdUsed: 3)
        t.expectEqual(ring.count, 3, "at capacity")
        t.expectEqual(ring.samples.map(\.sequence), [0, 1, 2], "sequences assigned in order")
        t.expectEqual(ring.latest?.memUsed, 300, "latest is newest")
        // Append past capacity drops the oldest.
        ring.append(memUsed: 400, fdUsed: 4)
        t.expectEqual(ring.count, 3, "still at capacity after overflow")
        t.expectEqual(ring.samples.map(\.memUsed), [200, 300, 400], "oldest (100) dropped")
        t.expectEqual(
            ring.samples.map(\.sequence), [1, 2, 3], "sequence numbers keep advancing (monotonic)")
        // Windowed read returns the most recent N, oldest→newest.
        t.expectEqual(ring.window(2).map(\.memUsed), [300, 400], "window(2) → last two")
        t.expectEqual(ring.window(10).map(\.memUsed), [200, 300, 400], "window ≥ count → all")
        t.expect(ring.window(0).isEmpty, "window(0) → empty")
        t.expect(ring.window(-1).isEmpty, "negative window → empty")

        // Capacity is clamped to at least 1.
        var tiny = NodeMetricRing(capacity: 0)
        tiny.append(memUsed: 5, fdUsed: 5)
        tiny.append(memUsed: 6, fdUsed: 6)
        t.expectEqual(tiny.count, 1, "capacity 0 clamped to 1")
        t.expectEqual(tiny.latest?.memUsed, 6, "clamped ring keeps newest")

        // Nil readings (a down node) are retained as nil, not coerced.
        var withNil = NodeMetricRing(capacity: 2)
        withNil.append(memUsed: nil, fdUsed: nil)
        t.expect(withNil.latest?.memUsed == nil, "nil mem retained")
        t.expect(withNil.latest?.fdUsed == nil, "nil fd retained")
    }

    // MARK: Per-node history isolation — one node's samples never bleed into another's.
    t.suite("Node metrics history isolation") {
        var history = NodeMetricsHistory(capacity: 4)
        history.record(node: "rabbit@a", memUsed: 10, fdUsed: 1)
        history.record(node: "rabbit@b", memUsed: 999, fdUsed: 9)
        history.record(node: "rabbit@a", memUsed: 20, fdUsed: 2)
        let a = history.samples(for: "rabbit@a")
        let b = history.samples(for: "rabbit@b")
        t.expectEqual(a.map(\.memUsed), [10, 20], "node a has only its own samples")
        t.expectEqual(b.map(\.memUsed), [999], "node b has only its own samples")
        // Each node advances its own sequence independently (no interleaving).
        t.expectEqual(a.map(\.sequence), [0, 1], "node a sequences are its own")
        t.expectEqual(b.map(\.sequence), [0], "node b sequences are its own")
        t.expect(history.samples(for: "unknown").isEmpty, "unknown node → empty")
        t.expect(history.ring(for: "unknown") == nil, "unknown node → nil ring")
        t.expectEqual(Set(history.nodeNames), Set(["rabbit@a", "rabbit@b"]), "tracks both node names")

        // Per-node capacity applies independently.
        for i in 0..<10 { history.record(node: "rabbit@a", memUsed: i, fdUsed: i) }
        t.expectEqual(history.samples(for: "rabbit@a").count, 4, "node a capped at capacity 4")
        t.expectEqual(history.samples(for: "rabbit@b").count, 1, "node b unaffected by node a's churn")
    }

    // MARK: Env-gated live integration — put a policy, list it, delete it.
    if let base = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_URL"] {
        let user = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_USER"] ?? "guest"
        let password = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_PASSWORD"] ?? "guest"
        await t.suite("RabbitMQ policies (integration)") {
            guard let components = URLComponents(string: base), let host = components.host else {
                t.expect(false, "SIMPLETON_AMQP_TEST_URL must be a URL like http://host:15672")
                return
            }
            let useTLS = components.scheme == "https"
            let conn = Connection(
                name: "live", kind: .amqp, host: host,
                port: components.port ?? (useTLS ? 15671 : 15672), username: user,
                params: ["vhost": "/", "useTLS": useTLS ? "true" : "false"])
            do {
                let backend = try AMQPBackendFactory.make(
                    conn, secret: ConnectionSecret(password: password))
                let name = "simpleton-policy-\(UUID().uuidString.prefix(8))"
                try await backend.putPolicy(
                    vhost: "/", name: name, pattern: "^simpleton-check\\.", applyTo: "queues",
                    definition: ["message-ttl": .int(60000), "dead-letter-exchange": .string("amq.direct")],
                    priority: 1)
                let listed = try await backend.policies(vhost: "/")
                let created = listed.first { $0.name == name }
                t.expect(created != nil, "created policy appears in the listing")
                t.expectEqual(created?.applyTo, "queues", "listed policy apply-to round-trips")
                t.expectEqual(created?.definition["message-ttl"], .int(60000), "listed message-ttl round-trips")
                try await backend.deletePolicy(vhost: "/", name: name)
                let afterDelete = try await backend.policies(vhost: "/")
                t.expect(!afterDelete.contains { $0.name == name }, "policy is gone after delete")
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    }
}
