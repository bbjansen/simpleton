/**
 * Release sidecar metadata.
 *
 * The CI pipeline writes one of these JSON objects to R2 alongside each
 * artifact, at `releases/Simpleton-<version>.json`. The shape here is the
 * EXACT contract the pipeline must produce — see README.md.
 */
export interface ReleaseSidecar {
  /**
   * CFBundleVersion — the machine-readable build number Sparkle uses to
   * compare releases and decide which update is newest. Required.
   * May be an integer-like string ("420") or a dotted numeric string
   * ("2.0.420"); it must match the running app's CFBundleVersion.
   */
  version: string;

  /**
   * CFBundleShortVersionString — the human-readable version shown in the UI
   * (e.g. "2.0.0"). Required.
   */
  shortVersionString: string;

  /**
   * Publication date as an RFC 822 / RFC 2822 string, e.g.
   * "Wed, 29 Oct 2025 09:20:11 +0000". Required. Emitted verbatim as
   * <pubDate>.
   */
  pubDate: string;

  /**
   * Sparkle EdDSA (Ed25519) signature of the .zip, base64-encoded, exactly
   * as produced by Sparkle's `sign_update` tool. Required. Emitted as the
   * `sparkle:edSignature` enclosure attribute.
   */
  edSignature: string;

  /**
   * Size of the .zip in bytes. Required. Emitted as the enclosure `length`
   * attribute. Must come from the same `sign_update` run as `edSignature`
   * (or `stat` of the exact file) so it matches the hosted artifact.
   */
  length: number;

  /**
   * Minimum macOS version, e.g. "12.0". Optional. Emitted as
   * <sparkle:minimumSystemVersion> when present.
   */
  minimumSystemVersion?: string;

  /**
   * Update channel (e.g. "beta", "nightly"). Optional. Omit for the default
   * (stable) channel. Emitted as <sparkle:channel> when present.
   */
  channel?: string;

  /**
   * Inline release notes as an HTML fragment. Optional. Emitted inside a
   * <description> CDATA block. Takes precedence over `releaseNotesLink`
   * when both are present (matching Sparkle's own preference).
   */
  releaseNotesHtml?: string;

  /**
   * URL to an external HTML release-notes page. Optional. Emitted as
   * <sparkle:releaseNotesLink>. Ignored if `releaseNotesHtml` is set.
   */
  releaseNotesLink?: string;
}

/**
 * A parsed, validated sidecar paired with the artifact filename it describes.
 * This is the input unit for `buildAppcast`.
 */
export interface AppcastEntry extends ReleaseSidecar {
  /**
   * The artifact filename under the `releases/` prefix, e.g.
   * "Simpleton-2.0.0.zip". The appcast turns this into a
   * `<baseUrl>/download/<fileName>` enclosure URL.
   */
  fileName: string;
}
