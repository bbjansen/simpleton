// Sources/SimpletonCore/Core/TerminalURI.swift
import Foundation

/// Helpers for the URIs terminals report via OSC escape sequences.
public enum TerminalURI {
    /// Parse an OSC 7 "current working directory" report into a plain filesystem path.
    ///
    /// Shells emit the CWD as a file URL — `file://<hostname>/<path>` — so the raw value must NOT
    /// be used as a path directly (it would concatenate `file://host/...` into whatever consumes
    /// it, e.g. the file browser). This strips the scheme + host authority and percent-decodes the
    /// path. Non-`file://` input (already a plain path) is returned unchanged.
    public static func directoryPath(fromOSC7 raw: String) -> String {
        guard raw.hasPrefix("file://"), let url = URL(string: raw) else { return raw }
        let path = url.path
        return path.isEmpty ? raw : path
    }
}
