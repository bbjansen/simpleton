// Sources/Simpleton/WorkspaceStore.swift
import Foundation

/// Observable, app-wide source of truth for the workspace switcher: the list of saved workspace
/// names and which one is currently applied. AppDelegate owns the writes (it re-reads the list from
/// WorkspaceManager after saves/deletes and stamps `activeName` when a workspace is opened); the
/// header dropdown and the Settings tab observe it so both stay in sync without threading callbacks.
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var names: [String] = []
    @Published var activeName: String? = nil

    private init() {}
}
