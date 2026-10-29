# Release & Auto-Update Pipeline

How Simpleton is built, signed, notarized, and auto-updated — and the one-time steps **you** must
do to turn it on. Until the secrets/variables below are set, the pipeline still runs and attaches an
**unsigned** build to each release (today's behavior); adding them upgrades it to a signed,
notarized, auto-updating release with no code changes.

## How it flows

```
Conventional commits on main
        │
        ▼
release-please.yml ──(release PR merged)──► tags vX.Y.Z + creates GitHub Release
        │                                              │
        │  (manual alt: push a v* tag → release.yml)   │
        ▼                                              ▼
            .github/workflows/release-build.yml  (reusable, workflow_call)
        build → Developer ID sign (hardened runtime, inside-out) → notarize + staple
              → Sparkle EdDSA sign → attach .zip to GitHub Release
              → upload .zip + sidecar .json to Cloudflare R2
                                   │
                                   ▼
        services/update-server (Worker + R2) serves /appcast.xml + /download/<file>
                                   │
                                   ▼
        Installed Simpleton checks SUFeedURL, verifies the EdDSA signature, self-updates
```

The signing/notarize/Sparkle/R2 steps are **guarded on secrets** (see `release-build.yml`): no
secrets → plain unsigned build; all signing secrets → signed + notarized; plus Cloudflare secrets →
uploaded to R2 so installed copies auto-update.

## One-time setup (what only you can do)

### 1. Apple Developer ID (signing + notarization)
- Enroll in the Apple Developer Program (paid) if you haven't.
- In Xcode/Developer portal, create a **Developer ID Application** certificate; export it with its
  private key from Keychain Access as a `.p12`. Base64 it: `base64 -i cert.p12 | pbcopy`.
- In App Store Connect → Users and Access → Integrations → App Store Connect API, create a key with
  the **Developer** role, download `AuthKey_XXXX.p8` (one-time), and note the **Key ID** + **Issuer
  ID**. Base64 the `.p8`: `base64 -i AuthKey_XXXX.p8 | pbcopy`.

### 2. Sparkle signing keys
Download Sparkle's tools (or use the copy in `.build/artifacts` after a build) and run once:
```bash
./bin/generate_keys                      # prints the PUBLIC key (SUPublicEDKey)
./bin/generate_keys -x sparkle_private.key   # exports the PRIVATE key for CI, then shred the file
```
- Public key → repo **variable** `SIMPLETON_SU_PUBLIC_ED_KEY`.
- Private key (file contents) → repo **secret** `SPARKLE_PRIVATE_KEY`.
- ⚠️ **This key pair must never change after your first signed release** — if it does, every
  installed copy will reject all future updates.

### 3. Cloudflare update service
See `services/update-server/README.md`. In short: create an R2 bucket `simpleton-updates`, deploy
the Worker (`pnpm --dir services/update-server install --ignore-scripts && pnpm -C services/update-server exec wrangler deploy`),
bind the bucket, and point a custom domain at the Worker. The feed is then
`https://<your-domain>/appcast.xml`. Create a Cloudflare **API token** with R2 read/write and note
your **account ID**.

### 4. GitHub secrets & variables
Repo → Settings → Secrets and variables → Actions.

**Secrets:**

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | base64 of the Developer ID Application `.p12` |
| `P12_PASSWORD` | password protecting that `.p12` |
| `KEYCHAIN_PASSWORD` | any random string (ephemeral CI keychain) |
| `ASC_API_KEY_P8_BASE64` | base64 of the App Store Connect API `.p8` |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID (UUID) |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (from `generate_keys -x`) |
| `CLOUDFLARE_API_TOKEN` | R2 read/write token |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |

**Variables** (not secret):

| Variable | Value |
|---|---|
| `SIMPLETON_SIGN_IDENTITY` | `Developer ID Application: <Name> (<TEAMID>)` |
| `SIMPLETON_SU_FEED_URL` | `https://<your-domain>/appcast.xml` |
| `SIMPLETON_SU_PUBLIC_ED_KEY` | Sparkle public key from `generate_keys` |
| `R2_BUCKET` | `simpleton-updates` (optional; this is the default) |

### Gating logic
- **Signing + notarization** turns on when `DEVELOPER_ID_P12_BASE64` + `ASC_API_KEY_P8_BASE64` +
  `SPARKLE_PRIVATE_KEY` are all present.
- **R2 upload** additionally needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID`.
- The app's **automatic update checks** are baked in only when signing is on **and**
  `SIMPLETON_SU_PUBLIC_ED_KEY` is set — so a bundle never auto-checks a placeholder feed.

## Cutting a release
- **Automated:** merge the release PR that `release-please` maintains → it tags + releases → the
  reusable build runs.
- **Manual:** `git tag vX.Y.Z && git push origin vX.Y.Z`.

`CFBundleVersion` is derived from the commit count, so it increments every release (Sparkle compares
this build number). The marketing version comes from the tag.

## Installing locally for dogfooding
1. Cut a signed release (above).
2. Download the `.zip` from the GitHub Release (or the R2 feed), unzip, move `Simpleton.app` to
   `/Applications`, launch. Because it's Developer ID-signed + notarized, Gatekeeper allows it with
   no override.
3. Leave it running as your daily terminal — it checks `SUFeedURL` on schedule and self-updates from
   each new release, so you get first-hand feedback as development continues.

## Security notes
- Every credential above lives in **GitHub Actions secrets** — never commit any of them. The
  Sparkle private key and the `.p12`/`.p8` are the sensitive ones; rotate if ever exposed (but note
  the Sparkle key-pair immutability constraint — rotating it strands installed copies).
- The update service is intentionally public and unauthenticated: integrity comes from the Sparkle
  **EdDSA signature** that the client verifies against the embedded public key, not from access
  control.

The exact signing/notarization commands and their rationale are captured in the CI
(`.github/workflows/release-build.yml`); it follows current Sparkle 2.x + `notarytool` guidance
(inside-out signing, no `--deep`, hardened runtime, zip→notarize→staple→re-zip, `sign_update` key on
stdin).
