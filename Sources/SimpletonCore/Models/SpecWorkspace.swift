// Sources/SimpletonCore/Models/SpecWorkspace.swift
import Foundation

/// The active editing mode of the spec-driven dev workspace.
///
/// `brainstorm` and `spec` are open/structured idea modes that generate their own markdown artifact;
/// `plan` writes an implementation plan; `act` is a passthrough mode noting that execution happens in
/// the AI chat; `board` is a kanban over `board.md`. Order here is the authoring flow and drives the
/// mode control (via `allCases`) — add a case and the UI picks it up automatically.
public enum SpecMode: String, Codable, CaseIterable, Sendable {
    case brainstorm
    case spec
    case plan
    case act
    case board

    /// Human-readable label for the mode control.
    public var displayName: String {
        switch self {
        case .brainstorm: return "Brainstorm"
        case .spec: return "Spec"
        case .plan: return "Plan"
        case .act: return "Act"
        case .board: return "Board"
        }
    }

    /// The artifact a doc-generating mode produces, if any. `act` reflects the plan; `board` is driven
    /// by its own board view rather than this mapping.
    public var generatedArtifact: SpecArtifact? {
        switch self {
        case .brainstorm: return .brainstorm
        case .spec: return .spec
        case .plan: return .plan
        case .act, .board: return nil
        }
    }

    /// The artifact this mode displays in the preview/edit slot (brainstorm/spec/plan show their own;
    /// `act` shows the plan for reference).
    public var displayedArtifact: SpecArtifact {
        switch self {
        case .brainstorm: return .brainstorm
        case .spec: return .spec
        case .plan, .act: return .plan
        case .board: return .board
        }
    }
}

/// A repo-local markdown artifact the workspace reads and writes under `<projectRoot>/.plan/`.
///
/// Phase 1 generates and edits `plan`; `brainstorm`, `spec`, and `board` are defined now so the
/// store's path helpers and later phases (brainstorm/spec modes, kanban over `board.md`) have a
/// stable file-name contract to build on.
public enum SpecArtifact: String, Codable, CaseIterable, Sendable {
    case brainstorm
    case spec
    case plan
    case board

    /// The markdown file name for this artifact inside the `.plan/` directory (e.g. `plan.md`).
    public var fileName: String {
        "\(rawValue).md"
    }

    /// Human-readable label for the artifact.
    public var displayName: String {
        switch self {
        case .brainstorm: return "Brainstorm"
        case .spec: return "Spec"
        case .plan: return "Plan"
        case .board: return "Board"
        }
    }
}

/// Persisted state for a single project's spec-driven dev workspace: which mode/artifact was last
/// active, the project it belongs to, and when it was last touched. Keyed per project by the store.
public struct SpecWorkspaceState: Codable, Equatable, Sendable {
    public var activeMode: SpecMode
    public var activeArtifact: SpecArtifact
    public var projectPath: String
    public var updatedAt: Date

    public init(
        activeMode: SpecMode = .plan,
        activeArtifact: SpecArtifact = .plan,
        projectPath: String = "",
        updatedAt: Date = Date()
    ) {
        self.activeMode = activeMode
        self.activeArtifact = activeArtifact
        self.projectPath = projectPath
        self.updatedAt = updatedAt
    }
}
