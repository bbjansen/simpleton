// Sources/SimpletonSQL/SQLResultExporter.swift
import Foundation

/// Serializes a row result to portable text for "export" / "copy". Pure and headless so the escaping
/// rules are unit-tested without a UI. CSV follows RFC 4180; JSON (RFC 8259) emits an array of objects
/// keyed by column name, preserving column order, mapping SQL types to native JSON where possible.
public enum SQLResultExporter {

    /// RFC 4180 CSV: a header row of column names, then one line per row, CRLF-separated. NULL renders
    /// as an empty field; blobs as base64 so binary data survives the round-trip.
    public static func csv(columns: [Column], rows: [[SQLValue]]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(columns.map { csvField($0.name) }.joined(separator: ","))
        for row in rows {
            lines.append(row.map { csvField(cellText($0)) }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    /// JSON array of objects (`[{"col": value, …}, …]`), column order preserved. Integers/doubles
    /// become JSON numbers (non-finite doubles fall back to strings, which JSON cannot represent),
    /// bools become `true`/`false`, NULL becomes `null`, text/blob become strings (blob base64).
    public static func json(columns: [Column], rows: [[SQLValue]]) -> String {
        var out = "["
        for (r, row) in rows.enumerated() {
            if r > 0 { out += "," }
            out += "{"
            for (c, col) in columns.enumerated() {
                if c > 0 { out += "," }
                let value = c < row.count ? row[c] : .null
                out += jsonString(col.name) + ":" + jsonValue(value)
            }
            out += "}"
        }
        out += "]"
        return out
    }

    // MARK: - CSV helpers

    /// The plain text of a cell for CSV: NULL → empty, blob → base64, everything else its displayString.
    private static func cellText(_ value: SQLValue) -> String {
        switch value {
        case .null: return ""
        case .blob(let d): return d.base64EncodedString()
        default: return value.displayString
        }
    }

    /// Quote a CSV field per RFC 4180 when it contains a comma, quote, CR, or LF; double internal quotes.
    private static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return text
        }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - JSON helpers

    private static func jsonValue(_ value: SQLValue) -> String {
        switch value {
        case .null: return "null"
        case .integer(let v): return String(v)
        case .double(let v): return v.isFinite ? String(v) : jsonString(String(v))
        case .text(let v): return jsonString(v)
        case .bool(let v): return v ? "true" : "false"
        case .blob(let d): return jsonString(d.base64EncodedString())
        }
    }

    /// A JSON string literal with the mandatory escapes (`"`, `\`, and control characters) per RFC 8259.
    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
