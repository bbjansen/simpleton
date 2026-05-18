// Sources/Simpleton/ShellPromptTracker.swift
import Foundation

enum SemanticPromptEvent {
    case promptStart
    case commandStart
    case outputStart
    case commandEnd(Int32?)
}

struct CommandRegion {
    let promptRow: Int
    var commandRow: Int?
    var outputRow: Int?
    var endRow: Int?
    var exitCode: Int32?
}

final class ShellPromptTracker {
    private(set) var regions: [CommandRegion] = []

    // MARK: - Event Handling

    func handleEvent(_ event: SemanticPromptEvent, atRow row: Int) {
        switch event {
        case .promptStart:
            regions.append(CommandRegion(promptRow: row))
        case .commandStart:
            guard !regions.isEmpty else { return }
            regions[regions.count - 1].commandRow = row
        case .outputStart:
            guard !regions.isEmpty else { return }
            regions[regions.count - 1].outputRow = row
        case .commandEnd(let code):
            guard !regions.isEmpty else { return }
            regions[regions.count - 1].endRow = row
            regions[regions.count - 1].exitCode = code
        }
    }

    // MARK: - Navigation Queries

    func previousPromptRow(before row: Int) -> Int? {
        for region in regions.reversed() {
            if region.promptRow < row {
                return region.promptRow
            }
        }
        return nil
    }

    func nextPromptRow(after row: Int) -> Int? {
        for region in regions {
            if region.promptRow > row {
                return region.promptRow
            }
        }
        return nil
    }

    // MARK: - Output Selection

    func commandOutputRange(at row: Int) -> (start: Int, end: Int)? {
        for region in regions.reversed() {
            guard let outputRow = region.outputRow else { continue }
            let end = region.endRow ?? region.promptRow + 1000
            if row >= region.promptRow && row <= end {
                return (start: outputRow, end: end)
            }
        }
        return nil
    }

    // MARK: - Pruning

    func prune(belowRow threshold: Int) {
        regions.removeAll { $0.promptRow < threshold }
    }

    // MARK: - OSC 133 Parsing

    static func parsePayload(_ payload: ArraySlice<UInt8>) -> SemanticPromptEvent? {
        guard let first = payload.first else { return nil }
        switch first {
        case UInt8(ascii: "A"):
            return .promptStart
        case UInt8(ascii: "B"):
            return .commandStart
        case UInt8(ascii: "C"):
            return .outputStart
        case UInt8(ascii: "D"):
            let rest = payload.dropFirst()
            if rest.isEmpty {
                return .commandEnd(nil)
            }
            let codeBytes = rest.first == UInt8(ascii: ";") ? rest.dropFirst() : rest
            if let codeStr = String(bytes: codeBytes, encoding: .ascii),
               let code = Int32(codeStr) {
                return .commandEnd(code)
            }
            return .commandEnd(nil)
        default:
            return nil
        }
    }
}
