// Sources/SimpletonSQL/SQLEventLoop.swift
import NIOPosix

/// Process-wide event loop group shared by the NIO-based SQL drivers (Postgres/MySQL). Created
/// lazily; lives for the process lifetime (no explicit shutdown — the app owns it until exit).
public enum SQLEventLoop {
    public static let shared = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
