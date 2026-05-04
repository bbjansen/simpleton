// Sources/SimpletonCore/Models/PaneState.swift
import Foundation

public enum PaneState: Equatable {
    case running
    case exited(code: Int32)
    case disconnected
    case connecting
    case authRequired
}

public enum ConnectionType: Equatable {
    case local(shell: String, workingDirectory: String)
    case ssh(bookmarkID: UUID)
}
