# Simpleton Update Server

A lightweight **Cloudflare Worker + R2** service that hosts the [Sparkle](https://sparkle-project.org/)
auto-update **appcast feed** and the signed, notarized artifacts for the
Simpleton macOS app.

It does two things:

1. Serves `GET /appcast.xml` — a valid Sparkle appcast (RSS 2.0 + `sparkle:`
   namespace) generated on the fly from JSON sidecars stored in R2.
2. Serves `GET /download/<file>` — streams the zipped `.app` artifact straight
   from R2 with correct caching, `ETag`, and range support.

The CI release pipeline only ever **uploads two objects per release** to R2; the
Worker turns them into a feed. No build step runs on the Worker beyond rendering
XML.

---

## Architecture

```
CI pipeline (on release)                     Cloudflare
┌──────────────────────────┐                 ┌───────────────────────────────┐
│ build + sign + notarize  │                 │  Worker: simpleton-update-server │
│ zip the .app             │   wrangler /    │                               │
│ sign_update <zip>  ──────┼──  S3 API  ───▶ │  R2 bucket: simpleton-updates │
│ write sidecar .json      │   upload        │   releases/                   │
└──────────────────────────┘                 │     Simpleton-<ver>.zip       │
                                             │     Simpleton-<ver>.json      │
Sparkle (in the app)                         │                               │
   GET /appcast.xml   ◀──────────────────────┤  list releases/*.json         │
   GET /download/..   ◀──────────────────────┤  stream releases/<file>       │
                                             └───────────────────────────────┘
```

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/appcast.xml` | Sparkle appcast built from `releases/*.json`. Newest-first by `sparkle:version`. `Cache-Control: public, max-age=60`. |
| `GET`  | `/download/<file>` | Streams `releases/<file>` from R2. `ETag`, `Accept-Ranges`, conditional (304) and range (206) support, `Cache-Control: public, max-age=31536000, immutable`. 404 if missing; 400 on path traversal / illegal filename. |
| `GET`  | `/health` | Returns `200 ok`. |

Only `GET`/`HEAD` are allowed; other methods return `405`.

---

## R2 object layout (CI must match EXACTLY)

Everything lives under the `releases/` prefix in the bucket bound as `UPDATES`:

```
simpleton-updates/                 (R2 bucket)
└── releases/
    ├── Simpleton-2.0.0.zip        ← signed + notarized, zipped .app
    ├── Simpleton-2.0.0.json       ← sidecar metadata for 2.0.0
    ├── Simpleton-1.9.0.zip
    └── Simpleton-1.9.0.json
```

Rules the pipeline MUST follow:

- The artifact is `releases/Simpleton-<shortVersionString>.zip`.
- The sidecar is `releases/Simpleton-<shortVersionString>.json` — **same base
  name, `.json` extension**. The Worker derives the download filename from the
  sidecar key by swapping `.json` → `.zip`, so the two names must match.
- `<file>` in a download URL must be a **plain filename** (letters, digits,
  `.`, `_`, `-`). No slashes, no `..`, nothing outside `releases/`. The Worker
  rejects anything else with `400`.
- The appcast only lists versions that have a **valid** sidecar. A malformed or
  incomplete sidecar is skipped (logged at error severity) — the rest of the
  feed still renders.

> The `.zip` object does **not** have to physically exist for the sidecar to
> appear in the appcast (the feed is driven by the sidecars). In practice CI
> uploads the `.zip` first, then the `.json`, so a listed version is always
> downloadable.

---

## Sidecar JSON schema (CI must produce this EXACTLY)

One JSON object per release, written to `releases/Simpleton-<shortVersionString>.json`.
Source of truth: [`src/types.ts`](./src/types.ts) (`ReleaseSidecar`).

```jsonc
{
  // REQUIRED — CFBundleVersion: the machine-readable build number Sparkle uses
  // to compare releases and pick the newest. Must equal the app's actual
  // CFBundleVersion. May be "420" or dotted "2.0.420".
  "version": "2.0.0",

  // REQUIRED — CFBundleShortVersionString: human-readable version shown in UI.
  "shortVersionString": "2.0.0",

  // REQUIRED — RFC 822 / RFC 2822 date string. Emitted verbatim as <pubDate>.
  "pubDate": "Wed, 29 Oct 2025 09:20:11 +0000",

  // REQUIRED — Sparkle EdDSA (Ed25519) signature of the EXACT .zip, base64,
  // straight from `sign_update <zip>`. Emitted as sparkle:edSignature.
  "edSignature": "WVyVJpOx+a5+vNWJVY79TRjFKveNk+VhGJf2iti4CZtJsJewIUGvh==",

  // REQUIRED — size of the .zip in bytes. Must come from the SAME sign_update
  // run (or `stat`) as the hosted file. Emitted as the enclosure length.
  "length": 18452310,

  // OPTIONAL — minimum macOS version, e.g. "12.0". Emitted as
  // <sparkle:minimumSystemVersion> when present.
  "minimumSystemVersion": "12.0",

  // OPTIONAL — update channel ("beta", "nightly", ...). Omit for stable.
  // Emitted as <sparkle:channel> when present.
  "channel": "beta",

  // OPTIONAL — inline HTML release notes. Emitted inside a <description>
  // CDATA block. Takes precedence over releaseNotesLink if both are set.
  "releaseNotesHtml": "<h2>What's new</h2><ul><li>Faster renderer</li></ul>",

  // OPTIONAL — external HTML release-notes URL. Emitted as
  // <sparkle:releaseNotesLink>. Ignored when releaseNotesHtml is present.
  "releaseNotesLink": "https://updates.simpleton.app/notes/2.0.0.html"
}
```

Validation applied by the Worker before an entry is included:

| Field | Required | Type | Rejected if |
|-------|----------|------|-------------|
| `version` | yes | string | empty / missing / not a string |
| `shortVersionString` | yes | string | empty / missing / not a string |
| `pubDate` | yes | string | empty / missing / not a string |
| `edSignature` | yes | string | empty / missing / not a string |
| `length` | yes | number | missing / ≤ 0 / not finite |
| `minimumSystemVersion` | no | string | — (dropped if empty) |
| `channel` | no | string | — (dropped if empty) |
| `releaseNotesHtml` | no | string | — (dropped if empty) |
| `releaseNotesLink` | no | string | — (dropped if empty) |

### Getting `edSignature` and `length`

Both come from Sparkle's `sign_update` tool, run against the **exact** `.zip`
you upload (do not recompute separately or they will mismatch and Sparkle will
reject the update):

```bash
# Sparkle ships sign_update in its tools; it prints the enclosure attributes.
./bin/sign_update Simpleton-2.0.0.zip
#   sparkle:edSignature="WVyV..." length="18452310"
```

Copy `edSignature` and `length` from that output into the sidecar.

---

## Appcast fields emitted (so the Sparkle wiring matches)

Generated by the pure function `buildAppcast(entries, baseUrl)` in
[`src/appcast.ts`](./src/appcast.ts).

- Root: `<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">`
  (the namespace URI is character-exact — `http`, `andymatuschak.org`).
- `<channel>`: `<title>`, `<link>` (→ `/appcast.xml`), `<description>`, `<language>`.
- Per `<item>`, in order:
  - `<title>Simpleton <shortVersionString></title>`
  - `<pubDate>` — RFC 822, verbatim from the sidecar.
  - `<sparkle:version>` — `version` (CFBundleVersion). **Sparkle sorts/compares on this.**
  - `<sparkle:shortVersionString>` — `shortVersionString`.
  - `<sparkle:minimumSystemVersion>` — only when provided.
  - `<sparkle:channel>` — only when provided.
  - Release notes — `<description><![CDATA[ … ]]></description>` for inline
    HTML, else `<sparkle:releaseNotesLink>`; inline HTML wins if both present.
  - `<enclosure url="<baseUrl>/download/Simpleton-<ver>.zip" length="<bytes>"
    type="application/octet-stream" sparkle:edSignature="<base64>" />`

Items are sorted **newest-first** by `sparkle:version` using a numeric/dotted
comparator (so build `100` sorts above `21`, and `2.1.0` above `2.0.5`).

`baseUrl` is the `BASE_URL` var (see below) with any trailing slash stripped.

---

## Configuration, bindings & secrets

Config lives in [`wrangler.jsonc`](./wrangler.jsonc).

### Bindings

| Binding | Type | Resource | Purpose |
|---------|------|----------|---------|
| `UPDATES` | R2 bucket | `simpleton-updates` (prod) / `simpleton-updates-staging` | Holds `releases/*` objects. |

### Vars (non-secret, in `wrangler.jsonc`)

| Var | Example | Purpose |
|-----|---------|---------|
| `BASE_URL` | `https://updates.simpleton.app` | Public origin used to build enclosure download URLs. **No trailing slash.** Set per environment. |

### Secrets

**None.** This service has no secrets. The appcast and artifacts are public by
design (they are signed with EdDSA; Sparkle verifies the signature client-side),
and R2 access is via the in-process binding — no API tokens in the Worker.

> The release pipeline needs credentials to *upload* to R2 (an R2 API token or
> account-scoped `wrangler login`), but those live in **CI**, not in this
> Worker. Nothing secret is committed here.

If you ever add a secret, use `wrangler secret put <NAME>` — never put it in
`wrangler.jsonc` or source.

---

## Local development & validation (no Cloudflare account needed)

```bash
cd services/update-server

# 1. Install (org policy: pnpm + ignore scripts; versions are pinned exactly
#    and .npmrc enforces save-exact + a 3-day minimum release age).
pnpm install --ignore-scripts

# 2. Generate binding + runtime types (creates worker-configuration.d.ts,
#    which is gitignored). Required before typecheck.
pnpm types

# 3. Type-check.
pnpm exec tsc --noEmit

# 4. Build / validate the Worker without logging in (dry run).
pnpm run build          # == wrangler deploy --dry-run --outdir dist

# 5. Unit tests for the pure appcast generator.
pnpm test
```

Local run against a simulated R2 bucket (optional):

```bash
pnpm dev                # wrangler dev — local R2 simulation
# Seed a fixture:
pnpm exec wrangler r2 object put simpleton-updates/releases/Simpleton-2.0.0.json \
  --file ./fixtures/Simpleton-2.0.0.json --local
```

---

## Deployment (requires a Cloudflare account — not performed here)

```bash
# One-time: create the R2 buckets.
pnpm exec wrangler r2 bucket create simpleton-updates
pnpm exec wrangler r2 bucket create simpleton-updates-staging

# Deploy.
pnpm exec wrangler deploy                 # production (top-level env)
pnpm exec wrangler deploy --env staging   # staging
```

### Custom domain

Serve the Worker on `updates.simpleton.app` so Sparkle points at a stable host
and `BASE_URL` matches the real origin. Two options:

1. **Dashboard** — Workers & Pages → `simpleton-update-server` → Settings →
   Domains & Routes → **Add Custom Domain** → `updates.simpleton.app`. The
   domain's zone must be on the same Cloudflare account; Cloudflare provisions
   the certificate and DNS automatically.

2. **Config** — add a custom domain route to `wrangler.jsonc` (the zone must be
   in your account):

   ```jsonc
   {
     "routes": [
       { "pattern": "updates.simpleton.app", "custom_domain": true }
     ]
   }
   ```

   Then `wrangler deploy`.

After the domain is live, make sure `BASE_URL` in `wrangler.jsonc` equals
`https://updates.simpleton.app` (prod) and the staging equivalent, and that the
app's Sparkle `SUFeedURL` points at `https://updates.simpleton.app/appcast.xml`.

---

## App side (Sparkle wiring)

In the app's `Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://updates.simpleton.app/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><!-- base64 Ed25519 public key from generate_keys --></string>
```

The private key used by `sign_update` in CI must correspond to `SUPublicEDKey`.

---

## Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Worker entry: routing, R2 listing/streaming, validation, path-traversal guard. |
| `src/appcast.ts` | Pure `buildAppcast(entries, baseUrl)` + version comparator + XML escaping. |
| `src/types.ts` | `ReleaseSidecar` / `AppcastEntry` — the sidecar contract. |
| `test/appcast.test.ts` | Vitest unit tests for `buildAppcast`. |
| `wrangler.jsonc` | Worker config, R2 binding, vars, environments. |
| `.npmrc` | `save-exact` + `minimum-release-age` (org policy). |
