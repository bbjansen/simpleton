# Plugin Architecture — Research & Recommendation

**Date:** 2026-08-12
**Type:** Research spike (decision input — not a spec)
**Question:** For the client-viewer suite (SQL/S3/RabbitMQ/…), should we build a third-party **plugin** architecture + **marketplace** (free/paid/subscription, installable from the web or the settings UI), or ship these as **native Swift** features? If plugins, which execution model, given the app is Developer-ID signed, notarized, and **directly distributed via Sparkle (not the Mac App Store)**?

---

## TL;DR recommendation

**Decouple two things that got conflated — because only one of them is expensive:**

1. **A monetizable, extensible, light-core product** (a marketplace of installable viewers, some free/some paid, installed from the web or settings) — **this does NOT require a third-party plugin runtime.** It's a licensing + payments + signed-registry layer that works identically whether a module is first-party-native or third-party-sandboxed.
2. **An open third-party ecosystem** (outside developers ship code that runs in our app) — **this is the large, risky, ongoing subsystem**, and under our distribution model it forces third-party code *out of our process* (WKWebView / subprocess / WASM), which means giving up native-quality UI or building a server-driven-UI runtime.

**Recommended path:** build the client viewers as **first-party native Swift modules** plus the **monetization/marketplace layer** now. This delivers the entire "light + extensible + marketplace + subscription" vision at **native quality and far lower risk/cost**, because our own code (same Team ID) needs no sandbox. **Defer the third-party untrusted runtime** until an open ecosystem is genuinely the business goal — and if we get there, the monetization layer carries over unchanged and the safe model is **WKWebView (UI plugins) + out-of-process subprocess (capability plugins)**.

**The real decision is a business one, not a technical one:** *are the near-term viewers things **we** build, or a genuine third-party developer ecosystem?* The technical answer follows directly.

---

## Why in-process native plugins are off the table for *untrusted* code

Under Developer-ID / notarized / **Hardened Runtime** / Sparkle distribution, the security boundary is **process isolation + code-signing**, not the App Sandbox. That single fact decides everything:

- **Hardened Runtime implicitly enables Library Validation** — `dyld` will only load code signed by Apple or by **our own Team ID**. A third-party (different Team ID) `.dylib`/`.bundle` **fails to load**. ([Apple forums 126895](https://developer.apple.com/forums/thread/126895), [WWDC19 S703](https://asciiwwdc.com/2019/sessions/703))
- To load third-party native code you must ship **`com.apple.security.cs.disable-library-validation`** — process-wide, all-or-nothing, no per-publisher allowlist — which also triggers **extra Gatekeeper scrutiny**. ([forums 770156](https://developer.apple.com/forums/thread/770156))
- **The killer:** in-process plugin code inherits our **entire** authority — keychain, all **TCC** grants (Full Disk Access, Automation…), entitlements, network identity — with **no separate prompt**, all under **our** signature. A malicious/paid plugin could exfiltrate the keychain and get **our Developer ID flagged/revoked**. Apple's own guidance: *"consider moving to an out-of-process plug-in model so that you don't have to load unknown third-party code into your app."* ([S703](https://asciiwwdc.com/2019/sessions/703))

**Corollary:** in-process native is perfectly fine for **first-party** modules (our Team ID → Library Validation passes, no entitlement needed). It is a **no-go for an untrusted/paid third-party marketplace.**

## The four execution models (for untrusted third-party code)

| | In-process bundle | Out-of-process (subprocess/XPC) | WebAssembly (WasmKit) | WKWebView |
|---|---|---|---|---|
| 3rd-party code in our address space | **Yes — full privileges** | No (separate process) | Yes, but capability-sandboxed | No (Apple's WebContent process) |
| Security for untrusted code | ✗ keychain/TCC/entitlements exposed under our Team ID | ✓ strong (self-sandbox, own identity) | ✓✓ capability sandbox, in-proc | ✓✓ OS-sandboxed + capability bridge |
| Hardened Runtime impact | ✗ must disable Library Validation | ✓ none | ✓ none (interpreter; no JIT entitlement) | ✓ none (host needs **no** `allow-jit` — verified) |
| UI approach | native, direct | declarative → native render (build a runtime) | declarative → native render | HTML/CSS/JS (rich, but web-feel) |
| Native fidelity | ✓✓ full | ✓ (your widget vocabulary) | ✓ (your widget vocabulary) | ✗ web-tier; ~100–200 MB per panel |
| Marketplace-viable for untrusted paid code | ✗ **No** | ✓ Yes | ✓ Yes | ✓ Yes |
| Effort | low to enable, impossible to secure | high (SDUI runtime + sandbox + quarantine policy) | med-high (marshalling + SDUI) | low-med (bridge + CSP) |

**If we ever build the third-party runtime, the recommended shape is two-tier:** **WKWebView** as the primary surface for UI-heavy plugins (VS Code's model; clean data-distribution, excellent sandbox), plus **out-of-process subprocess + JSON-RPC/stdio** (the LSP/MCP model, self-sandboxing like Chromium) for plugins that need real native capability but not custom UI. **WASM/WasmKit** is the most elegant sandbox for pure compute/logic plugins (no UI), viable later. ([Wasmtime security](https://docs.wasmtime.dev/security.html), [WasmKit](https://github.com/swiftwasm/WasmKit), [WKScriptMessageHandler](https://developer.apple.com/documentation/webkit/wkscriptmessagehandler), [MCP transports](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports))

## Industry precedent

- **No app achieves native-quality plugin UI *and* a real sandbox.** Raycast renders third-party plugins as native AppKit (React→reconciler) but **explicitly rejected sandboxing**; the apps that truly sandbox — **Zed** (WASM), **Figma** (QuickJS→WASM + iframe) — **gave up native UI** to do it. VS Code splits it: Node host process + strongly-sandboxed webviews.
- **Native in-process + unsandboxed is the norm where the host trusts code** — Obsidian (Electron JS), JetBrains (JVM), Sketch (CocoaScript) all grant full host privileges and defend via *review + signing + warnings*. Obsidian's docs literally warn plugins "can access files… connect to the internet… install additional programs."
- **A revenue-taking marketplace (~15%) exists only where the host sandboxes/hosts code AND runs billing** — **JetBrains (15%)**, **Figma (15%)**. Everyone unsandboxed pushes licensing **off-platform (0% cut)** — Obsidian, Sketch; Raycast monetizes via a first-party **Pro subscription**, not paid third-party plugins.
- **Third-party code is a live threat surface:** documented VS Code/OpenVSX supply-chain attacks — 12 malicious extensions, 100+ leaked publisher tokens (a stolen token pushes malware to the whole install base). ([Wiz](https://www.wiz.io/blog/supply-chain-risk-in-vscode-extension-marketplaces), [THN](https://thehackernews.com/2025/10/over-100-vs-code-extensions-exposed.html))

**Takeaway:** shipping our viewers as **first-party native modules** and selling them as first-party paid modules **sidesteps the entire sandbox/trust problem** while still supporting a paid/subscription marketplace.

## Monetization & distribution stack (works for first-party now; third-party later)

Independent of execution model:

- **Registry:** a **CDN-hosted signed JSON manifest** (versions, signatures, min-app-version, pricing) — the cheap free-catalog model (Obsidian/Raycast), reusing our Sparkle/appcast muscle. Artifacts **code-signed + notarized**; verify signature before load.
- **Install/update:** settings-UI reads the manifest, installs into an app-support dir, updates on the Sparkle cadence. Paid modules require a valid entitlement before activation.
- **Licensing/entitlement:** **Keygen** (device activation/limits, subscription expiry, **signed offline license files** with online-validate + offline-grace; Swift SDK). Start on **Keygen CE self-hosted (free)**. ([Keygen offline](https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/))
- **Payments:** a **Merchant-of-Record** — **Paddle** or **Lemon Squeezy** — so VAT/GST is handled globally (~5% + $0.50). Avoid raw Stripe unless we want to own worldwide tax filing. ([Paddle vs Stripe](https://designrevision.com/blog/stripe-vs-paddle))
- **Trust (only if third-party):** signature+notarization enforced at load, per-plugin capability declaration, review gate for paid listings, publisher-token leak monitoring, remote unpublish/kill-switch, developer agreement disclaiming liability.
- **Revenue split:** model **~15%** (JetBrains/Figma norm) *if/when* third-party paid plugins ship; first-party-only keeps payout/tax/liability minimal for the MVP.

## Plugins vs. native Swift — the honest call

If the near-term extensions are things **we** build: **native Swift wins decisively** — zero IPC, zero SDUI runtime, full native fidelity, one signing story, ships on our Sparkle cadence. A plugin architecture is a large ongoing subsystem (SDUI runtime, sandbox hardening, quarantine/signing policy, capability model, versioned ABI) that native features simply don't require. It pays off **only** when the actual goal is **third-party monetizable contributions with independent release cadence**. Decide the business question first; the safe technical models (WKWebView / subprocess / WASM) all exist but only justify their cost if a real third-party ecosystem is the objective.

## "Light core" without a third-party runtime

Two first-party options give the "install only what you want" feel with native quality and no untrusted-code risk:
- **Simplest:** compile modules in, entitlement-gate them (feature unlocks). Not a light *binary*, simplest to build.
- **Modular:** **downloadable first-party native bundles signed with our Team ID** — Library Validation passes (they're ours), so no security compromise; the core ships light and modules download from the registry. Cost: notarize each bundle + handle Gatekeeper quarantine (strip after verifying our own signature). Enables independent release cadence.

## Recommendation

1. **Now:** client viewers as **first-party native Swift modules** + the **monetization/marketplace layer** (signed manifest registry → settings-UI installer gated on entitlement → Keygen licensing → Paddle/Lemon Squeezy payments). Choose "compiled-in" vs "downloadable first-party bundle" based on whether a light binary is worth the loader/notarization infra.
2. **Defer** the third-party untrusted runtime until an open developer ecosystem is genuinely the goal. If/when: **WKWebView (UI plugins) + out-of-process subprocess (capability plugins)**; WASM later for compute. The monetization layer carries over unchanged.

## Two quick empirical checks before committing to any runtime (per "observable data" preference)
- Confirm a **self-sandboxed helper inside our non-sandboxed host** actually denies a disallowed file write (15-min build test).
- Confirm **exec-kill-on-quarantine** behavior for a downloaded, un-notarized helper on current macOS (informs the quarantine policy).
- (The WKWebView `allow-jit` question is already resolved: the host does **not** need it — WebContent JITs in Apple's process.)

## Sources
Hardened Runtime / Library Validation: [forums 126895](https://developer.apple.com/forums/thread/126895), [WWDC19 S703](https://asciiwwdc.com/2019/sessions/703), [forums 770156](https://developer.apple.com/forums/thread/770156) · Out-of-process/sandbox: [Chromium sandbox](https://www.chromium.org/developers/design-documents/sandbox/osx-sandboxing-design/), [MCP transports](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports) · WASM: [Wasmtime security](https://docs.wasmtime.dev/security.html), [WasmKit](https://github.com/swiftwasm/WasmKit) · WKWebView: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [VS Code webviews](https://code.visualstudio.com/api/extension-guides/webview) · Marketplaces: [JetBrains fees](https://plugins.jetbrains.com/docs/marketplace/revenue-sharing-and-fees.html), [Figma selling](https://help.figma.com/hc/en-us/articles/12067637274519-About-selling-Community-resources), [Raycast pricing](https://www.raycast.com/pricing) · Licensing/payments: [Keygen](https://keygen.sh/), [Paddle vs Stripe](https://designrevision.com/blog/stripe-vs-paddle), [Lemon Squeezy licensing](https://docs.lemonsqueezy.com/help/licensing) · Third-party risk: [Wiz](https://www.wiz.io/blog/supply-chain-risk-in-vscode-extension-marketplaces), [THN](https://thehackernews.com/2025/10/over-100-vs-code-extensions-exposed.html)
