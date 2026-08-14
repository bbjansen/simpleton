// Sources/Simpleton/Panels/AMQP/AMQPNodeMetricsChart.swift
import Charts
import SimpletonAMQP
import SwiftUI

/// A compact time-series view of one node's recent memory + file-descriptor usage, drawn from the
/// in-memory rolling history the panel accumulates on each refresh (`NodeMetricsHistory`). Memory is
/// a filled line chart; fd is a thin sparkline beneath it. The x-axis is the sample sequence number
/// (independent of wall-clock so uneven refresh cadence doesn't distort spacing). Renders nothing
/// until at least two samples exist — a single point isn't yet a trend.
struct AMQPNodeMetricsChart: View {
    let samples: [NodeMetricSample]

    /// Memory samples that actually carried a value (a down node reports nil).
    private var memPoints: [NodeMetricSample] { samples.filter { $0.memUsed != nil } }
    private var fdPoints: [NodeMetricSample] { samples.filter { $0.fdUsed != nil } }

    var body: some View {
        if memPoints.count >= 2 || fdPoints.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                if memPoints.count >= 2 {
                    HStack(spacing: 4) {
                        Text("mem").font(.system(size: 9)).foregroundColor(DT.textTertiary)
                        Text(byteString(memPoints.last?.memUsed ?? 0))
                            .font(DT.monoFont(size: 9)).foregroundColor(DT.textSecondary)
                    }
                    memoryChart
                }
                if fdPoints.count >= 2 {
                    HStack(spacing: 4) {
                        Text("fd").font(.system(size: 9)).foregroundColor(DT.textTertiary)
                        Text("\(fdPoints.last?.fdUsed ?? 0)")
                            .font(DT.monoFont(size: 9)).foregroundColor(DT.textSecondary)
                    }
                    fdChart
                }
            }
            .padding(.top, 4)
        }
    }

    private var memoryChart: some View {
        Chart(memPoints, id: \.sequence) { sample in
            LineMark(
                x: .value("sample", sample.sequence),
                y: .value("mem", Double(sample.memUsed ?? 0))
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(DT.accentBlue)
            AreaMark(
                x: .value("sample", sample.sequence),
                y: .value("mem", Double(sample.memUsed ?? 0))
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(DT.accentBlue.opacity(0.15))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 34)
    }

    private var fdChart: some View {
        Chart(fdPoints, id: \.sequence) { sample in
            LineMark(
                x: .value("sample", sample.sequence),
                y: .value("fd", Double(sample.fdUsed ?? 0))
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(DT.accentAmber)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 20)
    }

    private func byteString(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
