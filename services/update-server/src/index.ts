import { buildAppcast } from "./appcast.js";
import type { AppcastEntry, ReleaseSidecar } from "./types.js";

/** R2 prefix under which all release artifacts and sidecars live. */
const RELEASES_PREFIX = "releases/";

/** Appcast cache: short, so new releases appear quickly. */
const APPCAST_CACHE_CONTROL = "public, max-age=60";

/** Artifact cache: artifacts are immutable (versioned filenames), cache hard. */
const ARTIFACT_CACHE_CONTROL = "public, max-age=31536000, immutable";

function jsonLog(fields: Record<string, unknown>): string {
  return JSON.stringify(fields);
}

/**
 * Validate a parsed sidecar has the required, correctly-typed fields. Returns
 * a typed ReleaseSidecar or null if the object is malformed (so a single bad
 * sidecar is skipped rather than breaking the whole feed).
 */
function parseSidecar(raw: unknown): ReleaseSidecar | null {
  if (typeof raw !== "object" || raw === null) return null;
  const o = raw as Record<string, unknown>;

  if (typeof o.version !== "string" || o.version.length === 0) return null;
  if (typeof o.shortVersionString !== "string" || o.shortVersionString.length === 0) {
    return null;
  }
  if (typeof o.pubDate !== "string" || o.pubDate.length === 0) return null;
  if (typeof o.edSignature !== "string" || o.edSignature.length === 0) return null;
  if (typeof o.length !== "number" || !Number.isFinite(o.length) || o.length <= 0) {
    return null;
  }

  const sidecar: ReleaseSidecar = {
    version: o.version,
    shortVersionString: o.shortVersionString,
    pubDate: o.pubDate,
    edSignature: o.edSignature,
    length: o.length,
  };

  if (typeof o.minimumSystemVersion === "string" && o.minimumSystemVersion.length > 0) {
    sidecar.minimumSystemVersion = o.minimumSystemVersion;
  }
  if (typeof o.channel === "string" && o.channel.length > 0) {
    sidecar.channel = o.channel;
  }
  if (typeof o.releaseNotesHtml === "string" && o.releaseNotesHtml.length > 0) {
    sidecar.releaseNotesHtml = o.releaseNotesHtml;
  }
  if (typeof o.releaseNotesLink === "string" && o.releaseNotesLink.length > 0) {
    sidecar.releaseNotesLink = o.releaseNotesLink;
  }
  return sidecar;
}

/**
 * Derive the artifact (.zip) filename from a sidecar object key.
 * `releases/Simpleton-2.0.0.json` -> `Simpleton-2.0.0.zip`.
 */
function artifactFileNameFromSidecarKey(key: string): string {
  const base = key.slice(RELEASES_PREFIX.length);
  return base.replace(/\.json$/i, ".zip");
}

/** List every `releases/*.json` sidecar key, following R2 list pagination. */
async function listSidecarKeys(bucket: R2Bucket): Promise<string[]> {
  const keys: string[] = [];
  let cursor: string | undefined;

  do {
    const listed = await bucket.list({ prefix: RELEASES_PREFIX, cursor });
    for (const obj of listed.objects) {
      if (obj.key.toLowerCase().endsWith(".json")) {
        keys.push(obj.key);
      }
    }
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor);

  return keys;
}

/** Fetch and parse one sidecar into an AppcastEntry, or null if unusable. */
async function loadEntry(bucket: R2Bucket, key: string): Promise<AppcastEntry | null> {
  const object = await bucket.get(key);
  if (!object) return null;

  let raw: unknown;
  try {
    raw = await object.json();
  } catch {
    console.error(jsonLog({ message: "sidecar parse failed", key }));
    return null;
  }

  const sidecar = parseSidecar(raw);
  if (!sidecar) {
    console.error(jsonLog({ message: "sidecar validation failed", key }));
    return null;
  }

  return { ...sidecar, fileName: artifactFileNameFromSidecarKey(key) };
}

async function handleAppcast(env: Env): Promise<Response> {
  const keys = await listSidecarKeys(env.UPDATES);
  const settled = await Promise.all(keys.map((key) => loadEntry(env.UPDATES, key)));
  const entries = settled.filter((e): e is AppcastEntry => e !== null);

  const xml = buildAppcast(entries, env.BASE_URL);

  return new Response(xml, {
    status: 200,
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": APPCAST_CACHE_CONTROL,
    },
  });
}

/**
 * Validate a download filename: must be a plain filename inside `releases/`,
 * with no path traversal, no subdirectories, no leading slash. Returns the
 * safe R2 key, or null if the request is rejected.
 */
function safeArtifactKey(fileName: string): string | null {
  // Decode once; a malformed escape sequence throws.
  let decoded: string;
  try {
    decoded = decodeURIComponent(fileName);
  } catch {
    return null;
  }

  if (decoded.length === 0) return null;
  if (decoded.includes("/") || decoded.includes("\\")) return null;
  if (decoded.includes("..")) return null;
  if (decoded.includes("\0")) return null;
  // Disallow anything that is not a conservative artifact filename.
  if (!/^[A-Za-z0-9._-]+$/.test(decoded)) return null;

  return `${RELEASES_PREFIX}${decoded}`;
}

async function handleDownload(request: Request, env: Env, fileName: string): Promise<Response> {
  const key = safeArtifactKey(fileName);
  if (key === null) {
    return new Response("Bad request", { status: 400 });
  }

  // Honour conditional requests (ETag) so the CDN/client can revalidate cheaply.
  const object = await env.UPDATES.get(key, {
    onlyIf: request.headers,
    range: request.headers,
  });

  if (!object) {
    return new Response("Not found", { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag); // quoted form, correct for the header
  headers.set("Cache-Control", ARTIFACT_CACHE_CONTROL);
  headers.set("Accept-Ranges", "bytes");
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/octet-stream");
  }

  // A precondition failure (e.g. If-None-Match matched) returns an object with
  // no body — respond 304 Not Modified rather than a broken 200.
  if (!("body" in object) || object.body === undefined || object.body === null) {
    return new Response(null, { status: 304, headers });
  }

  // A ranged read sets `.range`; reply 206 with Content-Range.
  if (object.range && "offset" in object.range && "length" in object.range) {
    const offset = object.range.offset ?? 0;
    const length = object.range.length ?? object.size - offset;
    const end = offset + length - 1;
    headers.set("Content-Range", `bytes ${offset}-${end}/${object.size}`);
    headers.set("Content-Length", String(length));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { status: 200, headers });
}

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    try {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", {
          status: 405,
          headers: { Allow: "GET, HEAD" },
        });
      }

      if (pathname === "/health") {
        return new Response("ok", {
          status: 200,
          headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
      }

      if (pathname === "/appcast.xml") {
        return await handleAppcast(env);
      }

      if (pathname.startsWith("/download/")) {
        const fileName = pathname.slice("/download/".length);
        return await handleDownload(request, env, fileName);
      }

      return new Response("Not found", { status: 404 });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      console.error(jsonLog({ message: "unhandled error", error: message, path: pathname }));
      return new Response("Internal server error", { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;
