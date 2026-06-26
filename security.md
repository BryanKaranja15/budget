# MakeTheChoice — Security Model

This document is the single source of truth for how MakeTheChoice protects financial data. It explains the architecture's security properties honestly — including the limits that cannot be engineered away. See [plan.md](plan.md) for the full build plan.

---

## 1. Threat Model

**Assets (in priority order):**
1. On-device transaction data (the full 24-month corpus, in SQLite).
2. The Plaid `access_token` — grants **read-only** access to transactions (cannot move money).
3. The Plaid `client_secret` — required *alongside* a token to call Plaid at all.

**Trust boundaries:**
- **Device (iPhone):** holds all transaction data + the Secure Enclave key. Primary data-at-rest surface.
- **HermesTrial (server):** holds only ciphertext tokens it can't decrypt, sync cursors, and (in a secrets manager) the Plaid client_secret. Stateless in-memory relay for transaction data.
- **Plaid:** the unavoidable data pipe; sees all transactions by definition.
- **Grok (optional):** sees merchant *names only*, and only as a cold-start fallback that disappears once the on-device classifier ships.

**The one irreducible fact:** at the instant a Plaid call is made, the plaintext `access_token` + `client_secret` must exist together in *some* memory. No design removes that moment — security work shrinks at-rest exposure to zero and minimizes/contains the in-use window.

---

## 2. Where Data Lives (and the risk that implies)

| Data | Location | At-rest risk |
|---|---|---|
| Transaction amounts, dates, categories, balances | Device SQLite only | Guarded by device security (passcode, iOS encryption) — **never on the server** |
| Plaid `access_token` | Server, **as ciphertext the server can't decrypt** | **Zero** — unwrap key is in the device Secure Enclave |
| `access_token` (decrypted) | Server **memory only**, during a sync | Transient; wiped after each call |
| Per-Item sync cursor | Server | Not sensitive (a sync pointer) |
| Plaid `client_secret`, APNs key | Server **secrets manager** | Encrypted, access-audited, rotatable |
| Chat queries | Device (on-device LLM) | Not persisted across sessions |
| Receipt images + raw OCR text | Device only (Vision framework) | **Never uploaded**; OCR runs on-device; raw text stays local |
| Receipt item names + merchant | Device → Grok (via HermesTrial relay), cold-start only | **De-identified** (no amounts/account/card/dates/identity); un-attributable; dropped once on-device classifier ships |

> The bulk corpus did not disappear when we removed it from the server — it lives in **device SQLite**. The device is now the primary data-at-rest surface, protected by the iOS passcode, file-level encryption, and the Secure Enclave.

---

## 3. Token Custody — Tier 3 (device-held Secure Enclave key)

Goal: **zero usable token at rest on the server.**

- At link time the device generates a **non-extractable P-256 key in the Secure Enclave**. The Plaid `access_token` is envelope-encrypted under that key; the server stores **only the ciphertext** + cursor.
- Because the key is **asymmetric**, the server can **encrypt** (wrap) new tokens to the device's *public* key without the device being online. Only **decryption** requires the device.
- At sync time: device authenticates and performs/authorizes the unwrap → server holds the plaintext token **in memory only** → calls Plaid → **wipes** the key material, plaintext token, and transaction data.

**Why a stolen ciphertext is useless:** without the Secure Enclave private key (which never leaves the device hardware) the ciphertext cannot be decrypted. A server-disk theft yields nothing.

**Honest limits:**
- The Plaid `client_secret` is shared across all calls, so it **cannot** be device-held — it stays server-side. During a sync the server briefly holds `decrypted token + client_secret` together. At-rest risk → zero; the brief in-use window remains (closed only by Tier 4).
- Background sync triggered by a webhook only completes when the app can wake to authorize the unwrap; otherwise it waits for the next foreground sync.

---

## 4. Server-Proxy Sync Flow

Plaid requires `client_id` + `client_secret` server-side, so the device cannot call Plaid directly. HermesTrial relays and **stores no transaction rows**:

1. **Link (per bank):** app → `public_token` → `POST /exchange` → server stores access_token as **device-encrypted ciphertext** → returns `item_id`.
2. **Webhook:** Plaid → server (`SYNC_UPDATES_AVAILABLE`) → **verify JWT signature** → silent push to device.
3. **Sync:** device `POST /sync` (authenticated, authorizes unwrap) → server decrypts token in memory → Plaid `/transactions/sync` w/ cursor → returns `added`/`modified`/`removed` → device upserts into SQLite (idempotent on `plaid_transaction_id`) → server advances cursor, **wipes plaintext**.
4. **Fallbacks (silent push is unreliable):** sync on launch, on scene-active, on Background App Refresh, and via pull-to-refresh.

**Transaction data transits the server in-memory only (TLS) and is immediately discarded — never written to disk or logs.**

---

## 5. Token Rotation (periodic, free)

- Rotate each Item's access_token **monthly** via Plaid `/item/access_token/invalidate` — returns a new token, immediately kills the old one, **no user re-auth, no extra cost**. *(Verify the current endpoint name in Plaid docs at build time.)*
- **Piggybacked on a sync:** server calls invalidate while the token is already in memory → **re-wraps the new token to the device public key** (no device round-trip needed) → persists new ciphertext → wipes plaintext.
- **Robustness:** the old token dies immediately, so persisting the new ciphertext must be transactional with retries; on failure → re-link.
- **Security value:** caps the useful lifetime of any token leaked in the in-use window, and **forces an attacker to re-breach every cycle** — which the detection layer (§7) is built to catch. Rotation ≠ Revolut 90-day consent renewal (that still needs Link update mode).

---

## 6. Backend Auth & Hardening

- **Device auth on every endpoint** — per-device credential + **Apple App Attest**; no open token-exchange endpoint.
- **Secrets manager** (Infisical/Vault self-hosted, or AWS/GCP Secret Manager) for `client_secret` + APNs key — fetched at use-time, **access-audited**, rotatable. Never in the app, never in committed env files.
- **Plaid environment:** start in **Sandbox**; complete Production approval before launch.
- **Transport & host:** TLS everywhere; rate limiting; firewall; **key-only SSH** (no passwords); automatic security patching.
- **Logging hygiene:** never log tokens, keys, or transaction data.

---

## 7. Compromise Detection (required deliverables)

We **cannot** detect a stolen token's *read use* on Plaid's side — attacker traffic is indistinguishable from our own app, and Plaid exposes no real-time per-token source feed. So detection targets the **breach and the repeated access** instead. All four ship:

1. **Secrets-manager access alerting** *(primary tripwire).* Because any token is useless without the `client_secret`, alarm on **anomalous retrieval** of the secret — outside the expected sync schedule, or from an unexpected process/host.
2. **Rotation-collision detection.** Only one party can rotate a token. If a scheduled rotation **fails because the token was already invalidated**, treat as theft → alert + force re-link.
3. **Host intrusion detection.** Since rotation forces an attacker to re-breach each cycle, catch the repeated intrusion: `auditd`, file-integrity monitoring (AIDE/Tripwire), `fail2ban`, alerts on unexpected SSH / new processes / outbound connections.
4. **App Attest binding on `/sync` and all device endpoints.** Only the genuine app instance can trigger a sync; combined with the secret never leaving the server, the attacker's only viable path becomes full host compromise — exactly what §7.1 and §7.3 watch.

---

## 8. On-Device & Privacy Notes

- **Posture (reframed):** the priorities are (1) **protect credit-card/account credentials** and (2) ensure **nothing sent off-device is attributable to the user**. Innocuous, de-identified text leaving the device for categorization is acceptable *because it cannot be tied back to a person* — it carries no identity, account, card, amount, or date.
- **Categorization** runs on-device (Core ML classifier). Until that ships, the **Grok cold-start fallback** — for both unknown **merchants** and **receipt line items** — receives only **de-identified text**: merchant names and/or item descriptions, **never amounts, dates, accounts, card numbers, or IDs**. Requests are relayed through HermesTrial (`POST /categorize/items`), so Grok sees the *server*, not the user's device/IP. Once the on-device classifiers are trained, **Grok is dropped entirely**.
- **Chat** runs on-device (small fine-tuned LLM via MLX/llama.cpp). The model emits **constrained JSON query params over a whitelist — never raw SQL and never math** (prevents injection / arbitrary queries). SQLite computes; the model narrates the returned figure under a constrained template so it cannot invent numbers.
- **Receipt scanning** OCR uses Apple's **Vision** framework entirely on-device. Receipt/order **images are never uploaded**, and the **raw OCR text is written only to local SQLite**. The only thing that may leave the device is the de-identified categorization request above (item names + merchant). This gives item-level granularity (one Target charge → Food + Enjoyment + Housing) with nothing attributable to the user.
- **Model training data:** synthetic/teacher data + **user-consented** exports only. Raw transactions are never auto-uploaded.

---

## 9. Residual Risks (stated plainly)

| Risk | Status |
|---|---|
| Server disk/DB stolen at rest | **Mitigated** — token is undecryptable ciphertext; no transaction corpus stored |
| Full host compromise *during* a sync | **Partially mitigated** — minimized window + rotation + detection; fully closed only by Tier 4 |
| Lost/stolen unlocked phone | Device passcode + iOS encryption; Secure Enclave key non-extractable; local corpus exposed if device is unlocked |
| Plaid / third-party breach | Out of our control — standard aggregator trust |
| Silent read-abuse of a leaked token | Not directly detectable; contained via secret-separation + rotation + breach detection |

**Tier 4 (future option):** run the Plaid call inside a confidential enclave (AWS Nitro Enclave / GCP Confidential Cloud Run) so the host operator never sees the token+secret in plaintext — structurally removing the in-use vector. Not required for a single-user app; documented for later.

---

## 10. Net Posture

Compared to a typical cloud budgeting app (which stores your full history on its servers indefinitely), MakeTheChoice keeps **zero transaction history server-side** and **zero usable token at rest**. The remaining exposures are (a) the device itself (your phone's security) and (b) a brief in-use window on the server that rotation + detection contain and Tier 4 could eliminate.
