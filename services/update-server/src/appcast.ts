import type { AppcastEntry } from "./types.js";

/**
 * The Sparkle XML namespace. Character-exact: Sparkle only recognises
 * `sparkle:*` elements/attributes when this URI matches precisely.
 * Note: http (not https), host is andymatuschak.org.
 */
const SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle";

/** MIME type Sparkle's own tooling uses for a zipped .app. */
const ENCLOSURE_TYPE = "application/octet-stream";

/**
 * Escape text for inclusion in an XML text node or attribute value.
 * Covers the five predefined XML entities. Used for everything EXCEPT the
 * CDATA-wrapped release notes.
 */
export function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/**
 * Wrap an HTML fragment in a CDATA section, defusing any literal `]]>`
 * sequence so it cannot terminate the section early.
 */
function wrapCdata(html: string): string {
  const safe = html.replace(/]]>/g, "]]]]><![CDATA[>");
  return `<![CDATA[${safe}]]>`;
}

/**
 * Compare two Sparkle version strings (CFBundleVersion values).
 *
 * Mirrors Sparkle's default numeric/dotted comparison: split on
 * non-alphanumeric separators and compare component-by-component. Numeric
 * components compare numerically; anything else compares lexically. A missing
 * trailing component is treated as 0 ("1.0" == "1.0.0"), so pure-integer
 * build numbers ("420" vs "419") and dotted strings ("2.0.1" vs "2.0") both
 * order correctly.
 *
 * Returns a negative number if `a < b`, positive if `a > b`, 0 if equal.
 */
export function compareVersions(a: string, b: string): number {
  const partsA = a.split(/[^0-9A-Za-z]+/).filter((p) => p.length > 0);
  const partsB = b.split(/[^0-9A-Za-z]+/).filter((p) => p.length > 0);
  const max = Math.max(partsA.length, partsB.length);

  for (let i = 0; i < max; i++) {
    const rawA = partsA[i] ?? "0";
    const rawB = partsB[i] ?? "0";
    const numA = Number(rawA);
    const numB = Number(rawB);
    const bothNumeric = Number.isInteger(numA) && Number.isInteger(numB);

    if (bothNumeric) {
      if (numA !== numB) return numA - numB;
    } else {
      const cmp = rawA.localeCompare(rawB);
      if (cmp !== 0) return cmp;
    }
  }
  return 0;
}

/**
 * Render a single `<item>` for one release entry.
 */
function buildItem(entry: AppcastEntry, baseUrl: string): string {
  const downloadUrl = `${baseUrl}/download/${encodeURIComponent(entry.fileName)}`;

  const lines: string[] = [];
  lines.push("    <item>");
  lines.push(
    `      <title>${escapeXml(`Simpleton ${entry.shortVersionString}`)}</title>`,
  );
  lines.push(`      <pubDate>${escapeXml(entry.pubDate)}</pubDate>`);
  lines.push(`      <sparkle:version>${escapeXml(entry.version)}</sparkle:version>`);
  lines.push(
    `      <sparkle:shortVersionString>${escapeXml(entry.shortVersionString)}</sparkle:shortVersionString>`,
  );

  if (entry.minimumSystemVersion) {
    lines.push(
      `      <sparkle:minimumSystemVersion>${escapeXml(entry.minimumSystemVersion)}</sparkle:minimumSystemVersion>`,
    );
  }
  if (entry.channel) {
    lines.push(`      <sparkle:channel>${escapeXml(entry.channel)}</sparkle:channel>`);
  }

  // Release notes: inline HTML wins over an external link, matching Sparkle's
  // own precedence when both are supplied.
  if (entry.releaseNotesHtml) {
    lines.push(`      <description>${wrapCdata(entry.releaseNotesHtml)}</description>`);
  } else if (entry.releaseNotesLink) {
    lines.push(
      `      <sparkle:releaseNotesLink>${escapeXml(entry.releaseNotesLink)}</sparkle:releaseNotesLink>`,
    );
  }

  lines.push(
    `      <enclosure url="${escapeXml(downloadUrl)}" ` +
      `length="${entry.length}" ` +
      `type="${ENCLOSURE_TYPE}" ` +
      `sparkle:edSignature="${escapeXml(entry.edSignature)}" />`,
  );
  lines.push("    </item>");
  return lines.join("\n");
}

/**
 * Build a complete Sparkle appcast (RSS 2.0 + sparkle namespace) from a set of
 * release entries. Pure function — no I/O — so it is unit-testable without R2.
 *
 * Items are sorted newest-first by `sparkle:version` (CFBundleVersion), the
 * field Sparkle uses to pick the best update.
 *
 * @param entries Parsed/validated release sidecars with their artifact names.
 * @param baseUrl Public origin WITHOUT a trailing slash, e.g.
 *   "https://updates.simpleton.app". Used to build enclosure download URLs.
 */
export function buildAppcast(entries: AppcastEntry[], baseUrl: string): string {
  const normalizedBase = baseUrl.replace(/\/+$/, "");

  const sorted = [...entries].sort((a, b) => compareVersions(b.version, a.version));

  const items = sorted.map((entry) => buildItem(entry, normalizedBase)).join("\n");

  return (
    `<?xml version="1.0" encoding="utf-8"?>\n` +
    `<rss version="2.0" xmlns:sparkle="${SPARKLE_NS}">\n` +
    `  <channel>\n` +
    `    <title>Simpleton</title>\n` +
    `    <link>${escapeXml(normalizedBase)}/appcast.xml</link>\n` +
    `    <description>Appcast for the Simpleton macOS app.</description>\n` +
    `    <language>en</language>\n` +
    (items ? `${items}\n` : "") +
    `  </channel>\n` +
    `</rss>\n`
  );
}
