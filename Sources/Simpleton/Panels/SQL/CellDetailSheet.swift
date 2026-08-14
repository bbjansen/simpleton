// Sources/Simpleton/Panels/SQL/CellDetailSheet.swift
import AppKit
import SimpletonSQL
import SwiftUI

/// One cell's value, surfaced for inspection (double-click in the grid).
struct InspectedCell: Identifiable {
    let id = UUID()
    let column: String
    let value: SQLValue
}

/// A detail sheet for a single cell value: full (untruncated) text, JSON
/// pretty-printed when the value is JSON, and a hex dump for blobs. The grid
/// truncates cells to one line, so this is how long text / JSON / binary is read.
struct CellDetailSheet: View {
    let cell: InspectedCell
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(cell.column)
                    .font(DT.monoFont(size: 12, weight: .semibold)).foregroundColor(DT.textPrimary)
                if isJSON {
                    Text("JSON").font(.system(size: 9, weight: .semibold)).foregroundColor(DT.accentGreen)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(DT.accentGreen.opacity(0.15)).cornerRadius(DT.radiusPill)
                }
                Spacer()
                Text(typeLabel).font(.system(size: 10)).foregroundColor(DT.textTertiary)
            }
            ScrollView {
                Text(rendered)
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .background(DT.elevated).cornerRadius(DT.radiusCard)
            HStack {
                Text("\(byteCount) bytes").font(.system(size: 10)).foregroundColor(DT.textFaint)
                Spacer()
                Button("Copy") { copy() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 540, height: 440)
        .background(DT.base)
    }

    private var isJSON: Bool {
        if case .text(let s) = cell.value { return SQLCellFormatting.prettyJSON(s) != nil }
        return false
    }

    private var typeLabel: String {
        switch cell.value {
        case .null: return "null"
        case .integer: return "integer"
        case .double: return "double"
        case .text: return "text"
        case .bool: return "bool"
        case .blob(let d): return "blob (\(d.count) bytes)"
        }
    }

    private var byteCount: Int { rawString.utf8.count }

    /// What is shown in the scroll area: pretty JSON for JSON text, hex for blobs, raw otherwise.
    private var rendered: String {
        switch cell.value {
        case .null: return "NULL"
        case .blob(let d): return SQLCellFormatting.hexDump(d)
        case .text(let s): return SQLCellFormatting.prettyJSON(s) ?? s
        default: return cell.value.displayString
        }
    }

    /// What Copy puts on the pasteboard: the raw text (not pretty), hex for blobs.
    private var rawString: String {
        switch cell.value {
        case .null: return ""
        case .blob(let d): return SQLCellFormatting.hexDump(d)
        case .text(let s): return s
        default: return cell.value.displayString
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawString, forType: .string)
    }
}
