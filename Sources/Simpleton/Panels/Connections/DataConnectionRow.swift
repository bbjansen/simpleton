// Sources/Simpleton/Panels/Connections/DataConnectionRow.swift
import SimpletonCore
import SwiftUI

struct DataConnectionRow: View {
    let connection: Connection
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle().fill(ConnectionColor.swatch(connection.color)).frame(width: 8, height: 8)
                Image(systemName: connection.kind.icon)
                    .font(.system(size: 10)).foregroundColor(DT.textMuted).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(connection.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isHovered ? DT.textPrimary : DT.textSecondary).lineLimit(1)
                        if connection.pinned {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(DT.accentAmber)
                        }
                    }
                    Text(subtitle).font(DT.monoFont(size: 10)).foregroundColor(DT.textMuted).lineLimit(1)
                }
                Spacer()
                if let tag = connection.tags.first {
                    Text(tag)
                        .font(.system(size: 8, weight: .medium)).foregroundColor(DT.textFaint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(DT.textFaint.opacity(0.15)).cornerRadius(DT.radiusPill)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusButton, style: .continuous)
                    .fill(isHovered ? DT.hover : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DT.hoverAnimation) { isHovered = h } }
    }

    private var subtitle: String {
        if let host = connection.host { return host }
        if connection.kind == .sqlite, let p = connection.params["path"] {
            return (p as NSString).lastPathComponent
        }
        return connection.kind.displayName
    }
}
