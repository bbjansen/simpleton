import { describe, it, expect } from "vitest";
import { buildAppcast, compareVersions, escapeXml } from "../src/appcast.js";
import type { AppcastEntry } from "../src/types.js";

const BASE_URL = "https://updates.simpleton.app";

const SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle";

function entry(overrides: Partial<AppcastEntry> & Pick<AppcastEntry, "version">): AppcastEntry {
  return {
    version: overrides.version,
    shortVersionString: overrides.shortVersionString ?? overrides.version,
    pubDate: overrides.pubDate ?? "Wed, 29 Oct 2025 09:20:11 +0000",
    edSignature: overrides.edSignature ?? "c2lnbmF0dXJlLWJhc2U2NA==",
    length: overrides.length ?? 18452310,
    fileName: overrides.fileName ?? `Simpleton-${overrides.version}.zip`,
    minimumSystemVersion: overrides.minimumSystemVersion,
    channel: overrides.channel,
    releaseNotesHtml: overrides.releaseNotesHtml,
    releaseNotesLink: overrides.releaseNotesLink,
  };
}

/** Count non-overlapping occurrences of a substring. */
function countOf(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
}

describe("buildAppcast — document shape", () => {
  it("emits a valid RSS 2.0 appcast with the exact sparkle namespace", () => {
    const xml = buildAppcast([entry({ version: "100", shortVersionString: "1.0.0" })], BASE_URL);

    expect(xml.startsWith('<?xml version="1.0" encoding="utf-8"?>')).toBe(true);
    expect(xml).toContain('<rss version="2.0"');
    expect(xml).toContain(`xmlns:sparkle="${SPARKLE_NS}"`);
    expect(xml).toContain("<channel>");
    expect(xml).toContain("</channel>");
    expect(xml.trimEnd().endsWith("</rss>")).toBe(true);
  });

  it("produces well-formed XML with balanced item tags", () => {
    const xml = buildAppcast(
      [
        entry({ version: "200", shortVersionString: "2.0.0" }),
        entry({ version: "100", shortVersionString: "1.0.0" }),
      ],
      BASE_URL,
    );

    expect(countOf(xml, "<item>")).toBe(2);
    expect(countOf(xml, "</item>")).toBe(2);
    expect(countOf(xml, "<rss")).toBe(1);
    expect(countOf(xml, "</rss>")).toBe(1);
    // No unescaped stray ampersands outside entities/CDATA.
    expect(/&(?!amp;|lt;|gt;|quot;|apos;|#)/.test(xml)).toBe(false);
  });

  it("handles an empty release set (channel with no items)", () => {
    const xml = buildAppcast([], BASE_URL);
    expect(xml).toContain("<channel>");
    expect(countOf(xml, "<item>")).toBe(0);
    expect(xml.trimEnd().endsWith("</rss>")).toBe(true);
  });
});

describe("buildAppcast — sparkle fields per item", () => {
  it("emits version, shortVersionString, pubDate, and a signed enclosure", () => {
    const xml = buildAppcast(
      [
        entry({
          version: "420",
          shortVersionString: "2.0.0",
          pubDate: "Wed, 29 Oct 2025 09:20:11 +0000",
          edSignature: "WVyVJpOx+a5+vNWJVY79TRjFKveNk+VhGJf2iti4CZtJ==",
          length: 12345678,
          fileName: "Simpleton-2.0.0.zip",
        }),
      ],
      BASE_URL,
    );

    expect(xml).toContain("<sparkle:version>420</sparkle:version>");
    expect(xml).toContain("<sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>");
    expect(xml).toContain("<pubDate>Wed, 29 Oct 2025 09:20:11 +0000</pubDate>");

    // Enclosure: url points at /download/<file>, correct length/type/signature.
    expect(xml).toContain(
      `url="${BASE_URL}/download/Simpleton-2.0.0.zip"`,
    );
    expect(xml).toContain('length="12345678"');
    expect(xml).toContain('type="application/octet-stream"');
    expect(xml).toContain('sparkle:edSignature="WVyVJpOx+a5+vNWJVY79TRjFKveNk+VhGJf2iti4CZtJ=="');
  });

  it("emits minimumSystemVersion and channel only when present", () => {
    const withExtras = buildAppcast(
      [entry({ version: "200", minimumSystemVersion: "13.0", channel: "beta" })],
      BASE_URL,
    );
    expect(withExtras).toContain("<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>");
    expect(withExtras).toContain("<sparkle:channel>beta</sparkle:channel>");

    const without = buildAppcast([entry({ version: "200" })], BASE_URL);
    expect(without).not.toContain("sparkle:minimumSystemVersion");
    expect(without).not.toContain("sparkle:channel");
  });

  it("uses the shortVersionString in the item title", () => {
    const xml = buildAppcast([entry({ version: "200", shortVersionString: "2.1.3" })], BASE_URL);
    expect(xml).toContain("<title>Simpleton 2.1.3</title>");
  });
});

describe("buildAppcast — release notes handling", () => {
  it("wraps inline HTML notes in a CDATA <description>", () => {
    const xml = buildAppcast(
      [entry({ version: "200", releaseNotesHtml: "<h2>New</h2><p>Stuff & things</p>" })],
      BASE_URL,
    );
    expect(xml).toContain("<description><![CDATA[<h2>New</h2><p>Stuff & things</p>]]></description>");
    // Raw HTML must NOT be escaped inside CDATA.
    expect(xml).not.toContain("&lt;h2&gt;");
  });

  it("emits sparkle:releaseNotesLink when only a link is provided", () => {
    const xml = buildAppcast(
      [entry({ version: "200", releaseNotesLink: "https://notes.example/2.0.html" })],
      BASE_URL,
    );
    expect(xml).toContain(
      "<sparkle:releaseNotesLink>https://notes.example/2.0.html</sparkle:releaseNotesLink>",
    );
    // The channel always has a <description>; the item must not carry a
    // CDATA release-notes <description>.
    expect(xml).not.toContain("<description><![CDATA[");
  });

  it("prefers inline HTML over a link when both are present", () => {
    const xml = buildAppcast(
      [
        entry({
          version: "200",
          releaseNotesHtml: "<p>inline</p>",
          releaseNotesLink: "https://notes.example/2.0.html",
        }),
      ],
      BASE_URL,
    );
    expect(xml).toContain("<![CDATA[<p>inline</p>]]>");
    expect(xml).not.toContain("<sparkle:releaseNotesLink>");
  });

  it("emits neither when no notes are provided", () => {
    const xml = buildAppcast([entry({ version: "200" })], BASE_URL);
    expect(xml).not.toContain("<description><![CDATA[");
    expect(xml).not.toContain("<sparkle:releaseNotesLink>");
  });

  it("defuses a literal ]]> inside release notes so CDATA cannot terminate early", () => {
    const xml = buildAppcast(
      [entry({ version: "200", releaseNotesHtml: "before ]]> after" })],
      BASE_URL,
    );
    expect(xml).not.toContain("before ]]> after");
    expect(xml).toContain("]]]]><![CDATA[>");
  });
});

describe("buildAppcast — ordering (newest-first by sparkle:version)", () => {
  it("sorts dotted versions newest-first regardless of input order", () => {
    const xml = buildAppcast(
      [
        entry({ version: "1.0.0", shortVersionString: "1.0.0" }),
        entry({ version: "2.1.0", shortVersionString: "2.1.0" }),
        entry({ version: "2.0.5", shortVersionString: "2.0.5" }),
      ],
      BASE_URL,
    );
    const order = [...xml.matchAll(/<sparkle:version>([^<]+)<\/sparkle:version>/g)].map((m) => m[1]);
    expect(order).toEqual(["2.1.0", "2.0.5", "1.0.0"]);
  });

  it("sorts integer-style CFBundleVersion build numbers numerically, not lexically", () => {
    const xml = buildAppcast(
      [
        entry({ version: "9" }),
        entry({ version: "100" }),
        entry({ version: "21" }),
      ],
      BASE_URL,
    );
    const order = [...xml.matchAll(/<sparkle:version>([^<]+)<\/sparkle:version>/g)].map((m) => m[1]);
    // Lexical sort would give 9, 21, 100 reversed wrongly; numeric gives 100,21,9.
    expect(order).toEqual(["100", "21", "9"]);
  });

  it("does not mutate the caller's array", () => {
    const input = [entry({ version: "1" }), entry({ version: "2" })];
    const before = input.map((e) => e.version);
    buildAppcast(input, BASE_URL);
    expect(input.map((e) => e.version)).toEqual(before);
  });
});

describe("buildAppcast — URL / base handling", () => {
  it("strips a trailing slash from baseUrl", () => {
    const xml = buildAppcast([entry({ version: "1", fileName: "Simpleton-1.zip" })], `${BASE_URL}/`);
    expect(xml).toContain(`url="${BASE_URL}/download/Simpleton-1.zip"`);
    expect(xml).not.toContain("//download/");
  });

  it("escapes ampersands in the enclosure URL", () => {
    const xml = buildAppcast(
      [entry({ version: "1", fileName: "Simpleton-1+beta.zip" })],
      BASE_URL,
    );
    // '+' becomes %2B via encodeURIComponent; ensure URL is attribute-safe.
    expect(xml).toContain("Simpleton-1%2Bbeta.zip");
  });
});

describe("compareVersions", () => {
  it("orders numeric components numerically", () => {
    expect(compareVersions("2", "10")).toBeLessThan(0);
    expect(compareVersions("10", "2")).toBeGreaterThan(0);
    expect(compareVersions("2.0.0", "2.0.0")).toBe(0);
  });

  it("treats missing trailing components as zero", () => {
    expect(compareVersions("1.0", "1.0.0")).toBe(0);
    expect(compareVersions("1.0.1", "1.0")).toBeGreaterThan(0);
  });
});

describe("escapeXml", () => {
  it("escapes the five predefined XML entities", () => {
    expect(escapeXml(`<a href="x">&'</a>`)).toBe(
      "&lt;a href=&quot;x&quot;&gt;&amp;&apos;&lt;/a&gt;",
    );
  });
});
