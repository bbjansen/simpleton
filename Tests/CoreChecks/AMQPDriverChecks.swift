// Tests/CoreChecks/AMQPDriverChecks.swift
import Foundation
import SimpletonAMQP
import SimpletonCore

func runAMQPDriverChecks(_ t: TestRunner) async {
    // MARK: vhost / name percent-encoding — the load-bearing correctness point.
    t.suite("RabbitMQ path encoding") {
        t.expectEqual(RabbitMQManagementDriver.encodeSegment("/"), "%2F", "default vhost / → %2F")
        t.expectEqual(RabbitMQManagementDriver.encodeSegment("my-vhost"), "my-vhost", "plain name unchanged")
        t.expectEqual(
            RabbitMQManagementDriver.encodeSegment("a/b"), "a%2Fb", "slash inside a name is encoded")
        t.expectEqual(
            RabbitMQManagementDriver.encodeSegment("with space"), "with%20space", "space → %20")
        t.expectEqual(
            RabbitMQManagementDriver.encodeSegment("q.name_1~-"), "q.name_1~-",
            "unreserved set (- . _ ~) is preserved")
        t.expectEqual(
            RabbitMQManagementDriver.encodeSegment("q&x=1?y"), "q%26x%3D1%3Fy",
            "reserved chars & = ? are encoded")
        t.expectEqual(RabbitMQManagementDriver.encodeSegment(""), "", "empty stays empty")
    }

    // MARK: Basic auth header — Basic base64("user:password").
    t.suite("Basic auth header") {
        // "guest:guest" → base64 "Z3Vlc3Q6Z3Vlc3Q=".
        t.expectEqual(
            RabbitMQManagementDriver.basicAuthHeader(user: "guest", password: "guest"),
            "Basic Z3Vlc3Q6Z3Vlc3Q=", "guest:guest header")
        // Round-trip: decode the base64 back to "user:pass".
        let header = RabbitMQManagementDriver.basicAuthHeader(user: "user", password: "p@ss:word")
        t.expect(header.hasPrefix("Basic "), "has Basic prefix")
        let b64 = String(header.dropFirst("Basic ".count))
        if let data = Data(base64Encoded: b64), let decoded = String(data: data, encoding: .utf8) {
            t.expectEqual(decoded, "user:p@ss:word", "round-trips (colon in password kept)")
        } else {
            t.expect(false, "auth header base64 should decode")
        }
    }

    // MARK: Codable decode of sample /api/queues JSON.
    t.suite("QueueInfo decode") {
        let json = """
            [{
              "name": "orders", "vhost": "/", "messages": 42, "messages_ready": 40,
              "messages_unacknowledged": 2, "consumers": 3, "state": "running",
              "node": "rabbit@node1",
              "message_stats": {
                "publish_details": {"rate": 12.5},
                "deliver_get_details": {"rate": 8.0}
              }
            }]
            """
        do {
            let queues = try JSONDecoder().decode([QueueInfo].self, from: Data(json.utf8))
            t.expectEqual(queues.count, 1, "one queue")
            let q = queues[0]
            t.expectEqual(q.name, "orders", "name")
            t.expectEqual(q.vhost, "/", "vhost")
            t.expectEqual(q.messages, 42, "messages")
            t.expectEqual(q.messagesReady, 40, "messages_ready")
            t.expectEqual(q.messagesUnacked, 2, "messages_unacknowledged")
            t.expectEqual(q.consumers, 3, "consumers")
            t.expectEqual(q.state, "running", "state")
            t.expectEqual(q.node, "rabbit@node1", "node")
            t.expectEqual(q.publishRate, 12.5, "publish rate from message_stats")
            t.expectEqual(q.deliverRate, 8.0, "deliver rate from message_stats")
            t.expectEqual(q.id, "//orders", "id = vhost/name")
        } catch {
            t.expect(false, "QueueInfo decode failed: \(error)")
        }

        // A queue with no message_stats (idle) still decodes; rates are nil.
        let idle = """
            [{"name":"idle","vhost":"prod","messages":0,"messages_ready":0,
              "messages_unacknowledged":0,"consumers":0,"state":"idle","node":"rabbit@n"}]
            """
        do {
            let q = try JSONDecoder().decode([QueueInfo].self, from: Data(idle.utf8))[0]
            t.expect(q.publishRate == nil, "no stats → nil publish rate")
            t.expect(q.deliverRate == nil, "no stats → nil deliver rate")
        } catch {
            t.expect(false, "idle QueueInfo decode failed: \(error)")
        }
    }

    // MARK: Codable decode of sample /api/exchanges JSON.
    t.suite("ExchangeInfo decode") {
        let json = """
            [
              {"name":"","type":"direct","durable":true,"auto_delete":false,"vhost":"/"},
              {"name":"amq.topic","type":"topic","durable":true,"auto_delete":false,"vhost":"/"}
            ]
            """
        do {
            let exchanges = try JSONDecoder().decode([ExchangeInfo].self, from: Data(json.utf8))
            t.expectEqual(exchanges.count, 2, "two exchanges")
            t.expectEqual(exchanges[0].name, "", "default exchange has empty name")
            t.expectEqual(exchanges[0].type, "direct", "type direct")
            t.expect(exchanges[0].durable, "durable true")
            t.expect(!exchanges[0].autoDelete, "auto_delete false")
            t.expectEqual(exchanges[0].id, "//(default)", "empty name → (default) id (vhost / + name)")
            t.expectEqual(exchanges[1].name, "amq.topic", "second name")
            t.expectEqual(exchanges[1].type, "topic", "second type")
        } catch {
            t.expect(false, "ExchangeInfo decode failed: \(error)")
        }
    }

    // MARK: Codable decode of /api/connections and /api/channels JSON.
    t.suite("ConnectionInfo / ChannelInfo decode") {
        let conns = """
            [{"name":"127.0.0.1:52000 -> 127.0.0.1:5672","user":"guest","state":"running",
              "channels":2,"recv_oct":1024,"send_oct":2048}]
            """
        do {
            let c = try JSONDecoder().decode([ConnectionInfo].self, from: Data(conns.utf8))[0]
            t.expectEqual(c.user, "guest", "connection user")
            t.expectEqual(c.state, "running", "connection state")
            t.expectEqual(c.channels, 2, "connection channels")
            t.expectEqual(c.recvOct, 1024, "recv_oct")
            t.expectEqual(c.sendOct, 2048, "send_oct")
        } catch {
            t.expect(false, "ConnectionInfo decode failed: \(error)")
        }

        let chans = """
            [{"name":"127.0.0.1:52000 (1)","number":1,"consumer_count":1,
              "messages_unacknowledged":5,"prefetch_count":10,"state":"running"}]
            """
        do {
            let ch = try JSONDecoder().decode([ChannelInfo].self, from: Data(chans.utf8))[0]
            t.expectEqual(ch.number, 1, "channel number")
            t.expectEqual(ch.consumerCount, 1, "consumer_count")
            t.expectEqual(ch.unacked, 5, "messages_unacknowledged")
            t.expectEqual(ch.prefetch, 10, "prefetch_count")
            t.expectEqual(ch.state, "running", "channel state")
        } catch {
            t.expect(false, "ChannelInfo decode failed: \(error)")
        }
    }

    // MARK: Overview decode (nested queue_totals + object_totals).
    t.suite("Overview decode") {
        let json = """
            {"rabbitmq_version":"3.13.0","erlang_version":"26.2",
             "queue_totals":{"messages":100,"messages_ready":80,"messages_unacknowledged":20},
             "object_totals":{"connections":4,"queues":7}}
            """
        do {
            let o = try JSONDecoder().decode(Overview.self, from: Data(json.utf8))
            t.expectEqual(o.rabbitmqVersion, "3.13.0", "rabbitmq_version")
            t.expectEqual(o.erlangVersion, "26.2", "erlang_version")
            t.expectEqual(o.totalMessages, 100, "queue_totals.messages")
            t.expectEqual(o.totalMessagesReady, 80, "queue_totals.messages_ready")
            t.expectEqual(o.totalMessagesUnacked, 20, "queue_totals.messages_unacknowledged")
            t.expectEqual(o.totalConnections, 4, "object_totals.connections")
            t.expectEqual(o.totalQueues, 7, "object_totals.queues")
        } catch {
            t.expect(false, "Overview decode failed: \(error)")
        }
    }

    // MARK: MessagePreview decode + base64 payload decode.
    t.suite("MessagePreview decode + base64") {
        // "string" payload passes through unchanged; properties flatten to strings.
        let stringMsg = """
            [{"payload":"hello world","payload_bytes":11,"payload_encoding":"string",
              "routing_key":"rk","redelivered":false,
              "properties":{"content_type":"text/plain","delivery_mode":2,"priority":5}}]
            """
        do {
            let m = try JSONDecoder().decode([MessagePreview].self, from: Data(stringMsg.utf8))[0]
            t.expectEqual(m.payload, "hello world", "string payload passthrough")
            t.expectEqual(m.payloadBytes, 11, "payload_bytes")
            t.expectEqual(m.routingKey, "rk", "routing_key")
            t.expect(!m.redelivered, "redelivered false")
            t.expectEqual(m.properties["content_type"], "text/plain", "string property")
            t.expectEqual(m.properties["delivery_mode"], "2", "int property flattened")
            t.expectEqual(m.properties["priority"], "5", "int property flattened")
        } catch {
            t.expect(false, "string MessagePreview decode failed: \(error)")
        }

        // base64-encoded "hello world" → "aGVsbG8gd29ybGQ=" must decode to text.
        let b64Msg = """
            [{"payload":"aGVsbG8gd29ybGQ=","payload_bytes":11,"payload_encoding":"base64",
              "routing_key":"","redelivered":true,"properties":{}}]
            """
        do {
            let m = try JSONDecoder().decode([MessagePreview].self, from: Data(b64Msg.utf8))[0]
            t.expectEqual(m.payload, "hello world", "base64 payload decoded to UTF-8")
            t.expect(m.redelivered, "redelivered true")
        } catch {
            t.expect(false, "base64 MessagePreview decode failed: \(error)")
        }

        // Direct unit check of the decode helper (binary base64 → byte-count placeholder).
        t.expectEqual(
            MessagePreview.decodePayload("aGk=", encoding: "base64"), "hi", "helper: base64 hi → hi")
        t.expectEqual(
            MessagePreview.decodePayload("plain", encoding: "string"), "plain",
            "helper: string passthrough")
        // 0xFF 0xFE is invalid UTF-8 → placeholder.
        let binaryB64 = Data([0xFF, 0xFE]).base64EncodedString()
        t.expectEqual(
            MessagePreview.decodePayload(binaryB64, encoding: "base64"), "<2 bytes binary>",
            "helper: non-UTF-8 base64 → byte-count placeholder")
    }

    // MARK: HTTP status → AMQPError mapping.
    t.suite("AMQPError status mapping") {
        func mapError(_ status: Int) -> AMQPError? {
            do {
                try RabbitMQManagementDriver.mapStatus(status, body: Data("boom".utf8))
                return nil
            } catch let e as AMQPError {
                return e
            } catch {
                return nil
            }
        }
        t.expect(mapError(200) == nil, "200 → no error")
        t.expect(mapError(204) == nil, "204 → no error")
        if case .auth = mapError(401) { t.expect(true, "401 → auth") } else { t.expect(false, "401 should be auth") }
        if case .auth = mapError(403) { t.expect(true, "403 → auth") } else { t.expect(false, "403 should be auth") }
        if case .notFound = mapError(404) {
            t.expect(true, "404 → notFound")
        } else {
            t.expect(false, "404 should be notFound")
        }
        if case .requestFailed(let status, let body) = mapError(500) {
            t.expectEqual(status, 500, "requestFailed carries status")
            t.expectEqual(body, "boom", "requestFailed carries body")
        } else {
            t.expect(false, "500 should be requestFailed")
        }
    }

    // MARK: AMQPError.message user-facing text.
    t.suite("AMQPError.message") {
        t.expectEqual(AMQPError.connectionFailed("down").message, "down", "connectionFailed message")
        t.expectEqual(
            AMQPError.requestFailed(status: 418, body: "teapot").message, "HTTP 418: teapot",
            "requestFailed message")
        t.expectEqual(AMQPError.requestFailed(status: 502, body: "").message, "HTTP 502", "empty body")
    }

    // MARK: Factory mapping — .amqp → driver, others → .unsupported.
    t.suite("AMQPBackendFactory mapping") {
        do {
            let conn = Connection(
                name: "rmq", kind: .amqp, host: "localhost", port: 15672, username: "guest",
                params: ["vhost": "/", "useTLS": "false"])
            let backend = try AMQPBackendFactory.make(conn, secret: ConnectionSecret(password: "guest"))
            t.expect(backend is RabbitMQManagementDriver, "amqp → RabbitMQManagementDriver")
        } catch {
            t.expect(false, "amqp factory should not throw: \(error)")
        }
        do {
            _ = try AMQPBackendFactory.make(Connection(name: "pg", kind: .postgres), secret: nil)
            t.expect(false, "postgres should throw unsupported")
        } catch let e as AMQPError {
            if case .unsupported = e {
                t.expect(true, "postgres → unsupported")
            } else {
                t.expect(false, "wrong error \(e)")
            }
        } catch {
            t.expect(false, "wrong error type: \(error)")
        }
    }

    // MARK: Env-gated live integration — hit /api/overview against a real broker.
    if let base = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_URL"] {
        let user = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_USER"] ?? "guest"
        let password = ProcessInfo.processInfo.environment["SIMPLETON_AMQP_TEST_PASSWORD"] ?? "guest"
        await t.suite("RabbitMQ /api/overview (integration)") {
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
                let backend = try AMQPBackendFactory.make(conn, secret: ConnectionSecret(password: password))
                let overview = try await backend.overview()
                t.expect(!overview.rabbitmqVersion.isEmpty, "overview returns a rabbitmq_version")
                _ = try await backend.queues(vhost: "/")  // smoke: queues list decodes
                _ = try await backend.exchanges(vhost: "/")  // smoke: exchanges list decodes
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    } else {
        print("  … AMQP live checks skipped (set SIMPLETON_AMQP_TEST_URL/USER/PASSWORD to run)")
    }
}
