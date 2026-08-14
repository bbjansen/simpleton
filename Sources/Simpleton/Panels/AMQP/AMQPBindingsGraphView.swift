// Sources/Simpleton/Panels/AMQP/AMQPBindingsGraphView.swift
import SimpletonAMQP
import SwiftUI

/// Topology visualization of a vhost's bindings: exchanges (left) and queues (right) as nodes, with
/// each binding drawn as a labeled edge (routing key). The layout math is pure and lives in
/// `AMQPBindingsGraph`; this view is a thin renderer that scales the normalized `[0, 1]` coordinates
/// into the available canvas and draws edges (behind), nodes, and labels. When the layout capped a
/// column it shows a "showing N of M" note rather than silently dropping nodes.
struct AMQPBindingsGraphView: View {
    let layout: AMQPBindingsGraph.Layout

    /// Inset so node pills + labels don't clip against the panel edges.
    private let inset: CGFloat = 40
    private let nodeWidth: CGFloat = 108
    private let nodeHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            if layout.nodes.isEmpty {
                PanelEmptyStateView(
                    icon: "point.3.connected.trianglepath.dotted", title: "No topology",
                    message: "This vhost has no exchanges or queues to graph.")
            } else {
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        edgesCanvas(size: size)
                        ForEach(layout.nodes) { node in
                            nodeView(node)
                                .position(point(node.x, node.y, in: size))
                        }
                    }
                }
                if layout.isTruncated {
                    truncationNote
                }
            }
        }
    }

    /// The edges layer: straight lines from each exchange node to each queue node, with the routing
    /// key drawn at the midpoint. Drawn first so nodes sit on top.
    private func edgesCanvas(size: CGSize) -> some View {
        // Map node id → its scaled centre so edges can look up endpoints.
        let centres = Dictionary(
            uniqueKeysWithValues: layout.nodes.map { ($0.id, point($0.x, $0.y, in: size)) })
        return Canvas { context, _ in
            for edge in layout.edges {
                guard let from = centres[edge.fromID], let to = centres[edge.toID] else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(
                    path, with: .color(DT.border),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round))
                if !edge.label.isEmpty {
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    let text = Text(edge.label).font(DT.monoFont(size: 9)).foregroundColor(DT.textTertiary)
                    context.draw(context.resolve(text), at: mid, anchor: .center)
                }
            }
        }
    }

    private func nodeView(_ node: AMQPBindingsGraph.Node) -> some View {
        let isExchange = node.kind == .exchange
        let label = node.name.isEmpty ? AMQPBindingsGraph.defaultExchangeLabel : node.name
        let fill = isExchange ? DT.accentBlue.opacity(0.18) : DT.accentGreen.opacity(0.18)
        let stroke = isExchange ? DT.accentBlue : DT.accentGreen
        return Text(label)
            .font(DT.monoFont(size: 10, weight: .medium))
            .foregroundColor(DT.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .frame(width: nodeWidth, height: nodeHeight)
            .background(RoundedRectangle(cornerRadius: DT.radiusButton).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: DT.radiusButton).stroke(stroke, lineWidth: 1)
            )
            .help(isExchange ? "exchange: \(label)" : "queue: \(label)")
    }

    private var truncationNote: some View {
        Text(
            "showing \(layout.shownExchanges) of \(layout.totalExchanges) exchanges, "
                + "\(layout.shownQueues) of \(layout.totalQueues) queues"
        )
        .font(.system(size: 9)).foregroundColor(DT.textTertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    /// Scale a normalized `[0, 1]` point into the inset canvas rect.
    private func point(_ nx: Double, _ ny: Double, in size: CGSize) -> CGPoint {
        let w = max(size.width - inset * 2, 1)
        let h = max(size.height - inset * 2, 1)
        return CGPoint(x: inset + CGFloat(nx) * w, y: inset + CGFloat(ny) * h)
    }
}
