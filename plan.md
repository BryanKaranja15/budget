# MakeTheChoice — Personal Finance App · Plan

## Overview
A read-only personal iOS budgeting app connecting Revolut and US Bank via Plaid. Each bank is a separate Plaid Item; transactions are pulled through a minimal server proxy and stored locally in SQLite, categorized via a layered engine (with an on-device classifier), and surfaced through a dashboard-first SwiftUI UI with natural-language querying. **Receipt scanning** (on-device Vision OCR) breaks past Plaid's transaction-level ceiling to give item-level categorization (e.g. one Target charge split into Food + Enjoyment + Housing). Budget limits reset on the 1st of each month (month-scoped queries). History backfills 24 months on first sync.

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Frontend | SwiftUI + Swift Charts | Native iOS, charts built-in |
| Local DB | SQLite (via GRDB.swift) | Fast, offline-first, zero server cost |
| Both banks | Plaid Transactions API (`/transactions/sync`) | One integration covers US Bank + Revolut (one Item each) |
| Minimal backend | HermesTrial VPS — **Node.js (Express + `plaid` SDK)** | Token exchange + webhook receiver + Plaid proxy |
| Sync trigger | Plaid webhooks (+ on-device fallbacks) | Event-driven, with reliable fallbacks |
| Receipt OCR | Apple **Vision** framework (on-device) | Item-level granularity from receipts/orders; free, private, offline |
| Categorization AI | On-device **classifier** (MiniLM/DistilBERT → Core ML); Grok optional cold-start fallback | Private, gives calibrated confidence scores |
| Conversational AI | On-device **small LLM** (Qwen2.5-1.5B / Llama-3.2, fine-tuned, via MLX-Swift or llama.cpp) | NL → query params + narration only |
| Currency conversion | Historical-capable FX provider (Frankfurter/ECB; secondary source for currencies like KES) | Base-currency normalization incl. 24-mo backfill |

---

## Data Sources

### Plaid (US Bank + Revolut — one Item each)
- **One Plaid Item per institution.** The user runs Plaid Link **once per bank**; each produces a separate `access_token`/`item_id`. The app manages **multiple Items**.
- Products: `transactions`; webhook: `SYNC_UPDATES_AVAILABLE` (`/transactions/sync`).
- Provides per transaction: merchant name, Plaid category, amount, date, currency, account, `pending` status, `plaid_transaction_id`.
- `/transactions/sync` returns `added` / `modified` / `removed` and a **cursor** (stored server-side per Item). Handles **pending → posted** transitions (the transaction id changes; link via `pending_transaction_id`).
- 24-month backfill: request `days_requested` up to **730**; initial data arrives **asynchronously** over multiple sync pages / `HISTORICAL_UPDATE` → show backfill progress.
- ⚠️ Re-auth: Revolut consent expires every 90 days, and any Item can hit `ITEM_LOGIN_REQUIRED`. Both are resolved via Plaid **Link update mode** → generalized re-consent nudge per Item.

### Why Not Direct Revolut Open Banking?
- Requires becoming a Revolut partner (approval process); 4 requests/day rate limit; full history only in first 5 minutes post-auth. Plaid abstracts all of this.

---

## Backend (HermesTrial — Node.js, Minimal Proxy)

Plaid API calls authenticate with `client_id` + `secret`, which **must stay server-side** — so the device cannot call Plaid directly. HermesTrial does three jobs and **stores no transaction rows**. Critically, it also **cannot decrypt the Plaid `access_token` on its own** — see Token Custody below.

1. **Token exchange**: swap Plaid `public_token` → `access_token` (per Item); store the access_token **as ciphertext the server cannot decrypt** (key held on device); return `item_id`.
2. **Webhook receiver**: receive Plaid webhooks, **verify the JWT signature on every request** (reject anything failing verification) → send a silent push to the device to prompt a sync.
3. **Sync proxy**: on an authenticated device request (which supplies the decryption key), decrypt the access_token **in memory**, call Plaid `/transactions/sync` with the stored **cursor per Item**, **stream results back to the device over TLS, and immediately discard** the plaintext token + key + data (no disk, no logs). Persist only the advanced cursor + the ciphertext.
4. **Categorization relay** (`POST /categorize/items`): accept a **de-identified** `{ merchant?, items: [String] }` body, forward to **Grok** with a constrained prompt ("classify each item into exactly one of these 12 slugs; return a JSON array of the same length"), and return `[slug]`. The server validates/strips the payload so **no amounts, account/card numbers, dates, or identity** can be forwarded; because Grok sees the *server*, not the device, requests stay un-attributable to the user. App Attest still gates the endpoint, but the payload itself carries no identity. (Same relay later serves unknown-**merchant** cold-start categorization.)

### Token Custody — Tier 3 (device-held Secure Enclave key)
At-rest exposure on the server is driven to **zero**: the server stores only ciphertext it cannot read by itself.

- At link time the device generates/holds a **wrapping key in the iOS Secure Enclave** (hardware-backed, non-extractable). The Plaid `access_token` is encrypted under that key (envelope encryption); the server persists **only the ciphertext** + per-Item cursor.
- At sync time the device — which is already the thing that calls `/sync` and stores the data — sends the unwrap key (or performs the unwrap) over **authenticated TLS**. The server decrypts the access_token **in memory only**, calls Plaid, then **discards the key + plaintext token + transaction data**.
- Net: a server compromise *at rest* yields nothing usable — the key lives in the user's pocket, in hardware.
- **Caveat (honest):** the Plaid **`client_secret`** is shared across all calls and therefore *cannot* be device-held — it stays server-side (in a secrets manager, below). So during a sync the server briefly holds `decrypted access_token + client_secret` together in memory. At-rest risk → zero; the brief in-use window remains (only Tier 4 / confidential computing closes it — documented as a future option).
- **Caveat (operational):** webhook-triggered background sync only completes when the app can wake to supply the key; otherwise it waits for the next foreground sync. This is acceptable because push is already best-effort with fallbacks.

### Token Rotation (periodic, free)
- Rotate each Item's access_token on a schedule (default **monthly**) via Plaid's `/item/access_token/invalidate` (returns a new token, immediately kills the old one, **no user re-auth**, no extra cost). *Verify the current endpoint name in Plaid docs at build time.*
- **Piggyback on a sync:** because the device's Secure Enclave key is asymmetric (P-256), the server can **re-wrap the new token under the device's public key without a device round-trip**. Flow: during a normal sync (token already decrypted in memory) → call invalidate → encrypt the new token to the device public key → persist new ciphertext → wipe plaintext.
- **Robustness:** `invalidate` kills the old token immediately, so persist-the-new-ciphertext must be reliable (transactional + retries) before the rotation is considered complete; on failure, fall back to re-link.
- **Security value:** caps the useful lifetime of any token leaked during the in-use window and forces an attacker to re-breach every cycle (which feeds detection, below). Note: rotation ≠ Revolut 90-day consent renewal (still needs Link update mode).

### Backend Auth & Infra
- **Device auth required** on all endpoints (per-device token issued at onboarding; consider Apple **App Attest**) — no open token-exchange endpoint.
- **Secrets manager (Tier 1):** Plaid `client_id`/`client_secret`, APNs `.p8` key, and any server keys live in a managed secrets store (Infisical/Vault self-hosted = free; or AWS/GCP Secret Manager) — fetched at use-time, with access **audit logging** and rotation. Never in the app, never in plain env files committed anywhere.
- **Plaid environment**: start in **Sandbox**; plan **Production approval + cost** before launch.
- TLS everywhere; rate limiting; **logging hygiene — never log transaction data, tokens, or keys**.
- VPS hardening: firewall, no SSH password auth (keys only), automatic security patching.

### Server-Proxy Sync Flow
1. **Link (per bank):** App runs Plaid Link → `public_token` → `POST /exchange` → server stores the access_token **as device-encrypted ciphertext** (Secure Enclave-wrapped) → returns `item_id`.
2. **Webhook:** Plaid → server (`SYNC_UPDATES_AVAILABLE`) → verify JWT → silent push to device.
3. **Sync:** device `POST /sync` (authenticated, **supplies the unwrap key**) → server decrypts access_token in memory → calls Plaid `/transactions/sync` w/ cursor → returns `added`/`modified`/`removed` → device **upserts into SQLite** (idempotent on `plaid_transaction_id`) → server advances cursor and **wipes key + plaintext**.
4. **Fallbacks (silent push is unreliable):** also sync on launch, on scene-active, on Background App Refresh, and via pull-to-refresh.

---

## SQLite Schema (Core Tables)

Managed with GRDB `DatabaseMigrator` + `schema_version` from day one.

```text
plaid_items        -- item_id, institution, status (device keeps status/metadata; cursor lives server-side)
accounts           -- account_id, item_id, institution, name, mask, type, currency, balances
transactions       -- see columns below (date, category_id, account_id indexed)
merchants          -- normalized_name → category_id, source, locked (user override)  [Layer 2]
categories         -- 12 category definitions + monthly budget limit
budgets            -- (optional) category_id, month, limit — budget history
subscriptions      -- detected recurring charges
fx_rates           -- (date, base, quote, rate)
user_corrections   -- user overrides feeding back into merchants + training set
training_samples   -- corrections + chat feedback collected for periodic re-fine-tuning
receipts           -- scanned receipt/order header + link to its transaction  [Layer 0]
receipt_items      -- raw OCR line items belonging to a receipt
transaction_items  -- reconciled category splits of a transaction (item-level spend)
```

**Receipt-scanning tables (migration v2):**
- `receipts`: `merchant_name`, `normalized_merchant`, `purchase_date`, `total_amount`, `currency`, `source` (camera/share_sheet/manual), `raw_text` (on-device OCR), `scanned_at`, `transaction_id` (FK, null until matched), `match_status` (unmatched/matched/ambiguous), `match_confidence`.
- `receipt_items`: `receipt_id` (FK), `line_no`, `name`, `quantity`, `amount`, `category_id`, `category_source`, `confidence`.
- `transaction_items`: `transaction_id` (FK), `receipt_item_id` (FK), `name`, `amount`, `base_amount`, `category_id`, `category_source`, `confidence`. **Item-level spend reads these when present, else the transaction's own category.**
- Indexes: `receipts(transaction_id)`, `receipts(normalized_merchant)`, `receipt_items(receipt_id)`, `transaction_items(transaction_id)`.

**`transactions` columns:** `plaid_transaction_id` (unique, idempotent upsert), `account_id`, `date`, `merchant_name`, `pending` (bool), `iso_currency_code`, `original_amount`, `base_amount`, `plaid_category`, `category_id`, `category_source` (enum: user/merchant/model/plaid/grok), `confidence`, `is_subscription`, `is_internal_transfer`.

**Indexes (from day one):** `transactions(date)`, `transactions(category_id)`, `transactions(account_id)`, `merchants(normalized_name)`, `subscriptions(merchant)`.

> 24 months of data makes unindexed date/category queries slow — index from the start.

---

## Categories

| Category | Includes |
|---|---|
| Housing | Rent, utilities, furniture, cleaning supplies |
| Food | Groceries, restaurants, delivery |
| Transport | Uber, gas, public transit, parking |
| Health | Gym, pharmacy, doctor, dental |
| Education | Courses, books, tuition |
| Clothing | Apparel, shoes, accessories |
| Travel | Flights, hotels, Airbnb |
| Subscriptions | All recurring digital/service charges |
| Business | Work-related expenses |
| Enjoyment | Entertainment, events, hobbies |
| Savings | Transfers to brokerage/savings accounts |
| Uncategorized | Fallback — user corrects these |

---

## Categorization Engine (Precedence Order)

User corrections must win, so precedence is:

```
0. Receipt scan (item-level split)            highest automatic accuracy — see Receipt Scanning
1. User override (locked merchant/line)       beats even a receipt for a single item
2. Local merchant→category table (Layer 2)    seeded ~200 merchants, grows via corrections
3. On-device classifier (if confidence ≥ τ)   MiniLM/DistilBERT → Core ML; softmax = confidence
4. Plaid built-in category                    broad fallback
5. Grok API (merchant name only)              optional cold-start fallback before classifier ships
```

> Precedence in code (`CategorySource`): `user > receipt > merchant > model > plaid > grok`. "Layer 0" (receipt) outranks every *automatic* source because it reflects what was actually bought, but an explicit **user** correction still wins so a person can fix a single mis-scanned line.

- **Confidence:** the classifier's softmax probability (temperature-calibrated) is the confidence score — no hand-rolled scoring. If `confidence < τ` (e.g., 0.65) → mark **ambiguous** → enqueue a notification / in-app review → user confirms/corrects.
- **Feedback loop:** correction → update merchant table (locked) → **recategorize all past + future** transactions from that merchant → also append a labeled row to `training_samples`.
- Once the classifier is trained, Grok can be dropped entirely (privacy win); if used, it sends **merchant name only** (never amounts, dates, accounts, ids).

---

## Internal Transfers (avoid double-counting)

Transfers between the user's own accounts (e.g., "Savings" moves, credit-card payments) are **not spending**. Flag `is_internal_transfer = true` and **exclude from spending totals**. Detect via opposite-sign amount matching across accounts within a date window, plus Plaid transfer categories.

---

## Receipt Scanning (item-level granularity)

**The problem:** Plaid only ever reports `Target — $87.34`. Bread, wine, and an oven tray from one Target run get lumped into a single line and a single category. Transaction-level data has a hard ceiling; **item-level granularity requires receipts** — Plaid cannot solve this.

**The solution:** capture the receipt and parse it **on-device** with Apple's **Vision** framework (free, private, offline OCR). Each line item is categorized individually, the receipt is linked to its Plaid transaction, and the transaction is split into category-level sub-items.

**Flow:**
```
User photographs receipt / shares an order screenshot
        ↓  (Vision on-device OCR → line items)
Each item → LayeredItemCategorizer (Grok → keyword fallback) → category
        ↓
Match to a Plaid transaction by normalized merchant + date window + total (± tolerance)
        ↓
Split the transaction into transaction_items (amounts scaled so splits sum to the
real charged total — absorbs tax/rounding/FX)
```

**Item categorization (layered, mirrors the merchant engine).** Receipt line items are often cryptic abbreviations ("GV WHT BRD" = Great Value White Bread) that defeat simple matching, so:
```
item precedence:  user > on-device product classifier (Phase 4) > Grok > keyword > uncategorized
```
- **Grok** (cold-start / default now): all line items of a receipt are sent in **one batched call** that returns a constrained JSON array of category slugs. Reached via HermesTrial `POST /categorize/items`; the request carries **only de-identified item names + merchant** — never amounts, account/card numbers, dates, or identity (see [security.md](security.md)).
- **Keyword fallback** (`ItemCategorizer`): deterministic, offline; backfills any item Grok punts on and fully replaces the result when Grok is unreachable.
- **Method ≠ precedence source.** However an item is labeled (Grok or keyword), its `category_source` is stamped **`receipt`** (Layer 0 item-level truth); only an explicit user correction becomes `user`. The on-device product classifier replaces Grok later, same as the merchant classifier replaces merchant-level Grok.
- Code: `LayeredItemCategorizer` / `GrokItemCategorizer` / `KeywordItemCategorizer` (protocol `ItemCategorizing`); `ReceiptStore.ingest(_:rawItems:using:)` runs categorization then persists. Web search as an item identifier is **deferred** (possible future manual "identify this item" last-resort — rejected as the default: slow, rate-limited, noisy).

**Two capture modes:**
| Mode | Best for |
|---|---|
| Camera (photo a paper receipt) | Target, grocery stores, restaurants |
| Share sheet / screenshot | Amazon orders, online order confirmations |

**Matching & confidence:** candidates must share the normalized merchant key, fall inside the date window, and have a total within tolerance. Zero candidates → receipt stays `unmatched`; exactly one → `matched` + auto-split; more than one → `ambiguous` (user disambiguates, no auto-split). A 0–1 confidence is computed from amount + date closeness.

**The hard part is behavioral, not technical** — value only accrues if scanning actually happens. So the app pushes daily and surfaces unlinked transactions prominently:
- **Daily push** (heavily encouraged): *"3 unlinked transactions from yesterday — scan receipts?"* Driven by `transactionsNeedingReceipt(...)` over receipt-worthy merchants (Target, Amazon, groceries).
- Unscanned receipt-worthy transactions flagged on the dashboard; their items remain in the "Uncategorized / needs receipt" state (visible, slightly nagging) until scanned.

**Privacy:** OCR runs entirely on-device; **receipt images are never uploaded**, and the extracted text stays local (see [security.md](security.md)).

---

## Subscription Detection (Rule-Based)

```
Trigger: same merchant + amount within ±5% + cadence ≈ 7/14/30/365 days (with tolerance window)
Flag:    price creep (same merchant, cadence matches, amount increased)
Output:  subscriptions row: merchant, amount, currency, cadence, last_charged,
         next_expected_date, annual_cost, status, confidence
```

---

## Currency Handling

- User sets a base currency (USD, GBP, EUR, KES, etc.) at onboarding.
- Always preserve `original_amount` + `iso_currency_code`; store computed `base_amount`.
- **24-month backfill needs historical FX.** Convert at the **transaction-date rate** where available, else latest. Use a provider with free historical rates (Frankfurter/ECB); note ECB lacks some currencies (e.g., KES) → flag a secondary source.
- `fx_rates(date, base, quote, rate)`: fetch daily + on-demand for backfill.

---

## AI Layer

Two separate models for two jobs. Both fine-tuned on Kaggle (12 hr/day GPU is far more than needed). Neither does math — SQLite computes; models only parse/narrate.

### 1. Categorization — fine-tuned classifier (on-device)
- **Text classification:** input `merchant_name (+ Plaid category, amount sign)` → probability distribution over the 12 categories.
- Base: small encoder (**MiniLM / DistilBERT**, multilingual variant if needed) → fine-tune → **Core ML** (encoders convert cleanly, run fast offline).
- Softmax = calibrated **confidence** (temperature scaling) → drives the ambiguous-expense notification (gap fix, no manual rules).

### 2. Chat — fine-tuned small LLM (on-device), NL → query params
- Base: **Qwen2.5-1.5B-Instruct** or **Llama-3.2-1B/3B-Instruct** (3B = better accuracy, 1B = smaller).
- Output: **strict enum'd JSON params** (intent, category, period, merchant, aggregation, compare_to_budget, …) — **never raw SQL, never math**. App builds **parameterized** queries from the params; SQLite computes; the model **narrates the returned figure** under a constrained template so it can't invent numbers.
- Runtime: **MLX-Swift** (preferred) or **llama.cpp** via Swift (Core ML reserved for the classifier).
- Ship the LLM via **on-demand download** (~0.5–2 GB), not in the app binary.

```
User:  "How much did I spend on food last month?"
LLM:   { intent: "spend_total", category: "Food", period: "last_month" }
App:   parameterized SQL → $347.82
LLM:   "You spent $347.82 on food in May, $52 under your $400 budget."
```

See **Appendix: Model Training (Kaggle) Workflow**.

---

## UI Structure

### Onboarding
Base-currency selection → notification priming → Plaid Link (run per bank) → backfill progress.

- **Guided tip callouts (haptic):** instructional tip popups point out key spots on each screen (e.g. month selector, "Wrong category?", receipt scan, chat). Each callout fires a **single short buzz** as it appears (`UIImpactFeedbackGenerator`, light style) so the guidance is felt as well as seen. Respect Reduce Motion / system haptic settings; exactly one buzz per callout, debounced so rapid-advancing through tips doesn't buzz repeatedly.

### Screen 1 — Dashboard (Home)
- Donut chart: spending share by category (current month).
- Category table: `[Category] [Spent] [Budget] [Remaining]` with green/amber/red indicator.
- Month selector to navigate history.

### Screen 2 — Category Drilldown
- Tap a category → its transactions (merchant, amount, date, base-currency equivalent).
- Inline "Wrong category?" correction → reclassify (updates merchant table + recategorizes history).

### Screen 3 — Subscriptions Board
- Detected recurring charges sorted by annual cost (desc): merchant, amount, cadence, next expected charge, annual total, price-creep badge.

### Screen 4 — Chat
- NL queries via on-device LLM → params; SQLite returns exact figures; session-only history (not persisted).

### Screen 5 — Receipt Scan & Splits
- Capture: camera (paper receipt) or share-sheet/screenshot import (online orders).
- Review extracted line items + per-item category before saving; confirm/disambiguate the matched transaction.
- A split transaction shows its item-level breakdown in the category drilldown.

### Edge / empty states
No items, Item error/re-auth required, sync failure, offline, backfill-in-progress, ambiguous-expense review prompt, **unlinked receipt-worthy transactions (daily nudge)**, ambiguous receipt match.

---

## Build Phases (iOS-first)

### Phase 0 — Scaffold & Schema  ✅ (core package built + 61 unit tests green)
- [x] `MakeTheChoiceCore` Swift package, SPM: GRDB (LinkKit/MLX/Vision later).
- [x] GRDB migrations for all tables + indexes; `schema_version` (v1 core, v2 receipts).
- [x] Seed 12 categories + ~200 common merchants.
- [x] Repositories + `TransactionStore` + `ReceiptStore` + fixture data loader.
- [x] Receipt-scanning data model + matching/splitting/itemized-spend logic + `ItemCategorizer` (keyword fallback).
- [ ] Xcode app target (`MakeTheChoice/`) that links the core package (created when UI starts).

### Phase 1 — Core Logic on Fixtures (no network)
- [ ] Categorization pipeline w/ precedence (rule fallback until classifier ships).
- [ ] Subscription detector; internal-transfer detection.
- [ ] FX conversion service (mock rates first).
- [ ] Query-param builder + parameterized query layer (reused by chat).
- [ ] Unit tests for all of the above.

### Phase 2 — UI on Fixtures
- [ ] Dashboard (donut + category table + month selector).
- [ ] Category drilldown + correction flow.
- [ ] Subscriptions board.
- [ ] Per-category budget setting; month-scoped spending (auto "reset" on 1st).
- [ ] Empty/error states.

### Phase 3 — Backend (Node) + Real Plaid (Sandbox)
- [ ] `/exchange`, multi-Item, `/sync` proxy w/ cursor, webhook + JWT verify, APNs push, device auth.
- [ ] **Tier 3 token custody:** device Secure Enclave wrapping key (P-256, asymmetric); server stores access_token ciphertext only; device supplies unwrap at sync; server decrypts in memory → calls Plaid → wipes.
- [ ] **Periodic token rotation** (monthly, piggybacked on sync, re-wrapped to device public key, transactional persist).
- [ ] **Compromise detection (all 4):** secrets-manager access alerting; rotation-collision detection; host IDS (auditd/file-integrity/fail2ban); App Attest binding on device endpoints.
- [ ] **Secrets manager** for Plaid `client_secret` + APNs key; VPS hardening (firewall, key-only SSH, auto-patch); no-PII logging.
- [ ] iOS: Plaid Link (per bank), `SyncService` → proxy, backfill progress, re-auth flow.
- [ ] Store device auth credential in Keychain; push + Background App Refresh + foreground + pull-to-refresh sync.

### Phase 4 — Models & Receipt OCR
- [ ] Train classifier (Kaggle → Core ML) → wire categorization + confidence/ambiguous notifications.
- [ ] Distill + QLoRA chat model → MLX/llama.cpp → Chat screen w/ constrained decoding + narration.
- [ ] **Vision OCR pipeline** (camera + share-sheet) → line-item extraction → review UI; upgrade `ItemCategorizer` from keyword rules to a product classifier; daily unlinked-transaction push.
- [ ] Retraining tooling (export `training_samples` → re-fine-tune → ship updated model).

### Phase 5 — Production Hardening
- [ ] Plaid Production approval; secrets management; monitoring; no-PII logging; on-demand model download; QA.

---

## Privacy Model Summary (honest)

| Data | Where it lives / who sees it |
|---|---|
| Transaction amounts, dates, categories | On device (SQLite) only — **never stored** server-side |
| Account numbers | On device only |
| Transaction data in transit | **Transits HermesTrial in-memory only** (TLS), immediately discarded — never written to disk or logs |
| Aggregated summaries | On device only — never leave |
| Bank credentials | Never seen (OAuth via Plaid Link) |
| Plaid `access_token` | **Stored on HermesTrial as ciphertext the server can't decrypt** — unwrap key lives in the device **Secure Enclave** (Tier 3). At-rest server exposure = zero |
| Plaid `access_token` (decrypted) | Exists **in server memory only** during a sync, then wiped — never persisted |
| Per-Item sync cursor | Stored on HermesTrial (not sensitive — just a sync pointer) |
| Plaid `client_secret`, APNs key | Server **secrets manager** (audit-logged, rotatable); cannot be device-held |
| Merchant names (unknown only) | Grok API only, *if* used as cold-start fallback (none once classifier ships) |
| Chat queries | On device (on-device LLM); not persisted across sessions |
| Model training data | Synthetic/teacher data + **user-consented** exports only — raw transactions never auto-uploaded |

---

## Threat Model & Hardening

**Assets:** (1) on-device transaction data, (2) the Plaid `access_token` (read-only access to transactions — cannot move money), (3) the Plaid `client_secret`.

| Threat | Outcome | Mitigation |
|---|---|---|
| Server disk/DB stolen (at rest) | **Nothing usable** — access_token is ciphertext, unwrap key not on server | Tier 3 device-held Secure Enclave key |
| Server fully compromised *during* a sync | Attacker could observe a decrypted token in memory for that window | Minimize window (decrypt → call → wipe); VPS hardening; secrets manager audit logs; Tier 4 (future) closes this |
| Token/data leaked via logs | Exposure | Strict no-logging of tokens/keys/transaction data |
| Open/abused endpoints | Unauthorized sync attempts | Per-device auth (App Attest); rate limiting; TLS |
| Webhook spoofing | Fake sync triggers | Verify Plaid JWT signature on every webhook |
| Lost/stolen phone | Local data + Secure Enclave key exposure | Device passcode + iOS data-at-rest encryption; Secure Enclave key is non-extractable and bound to device |
| Plaid or ExchangeRate/Grok breach | Out of our control | Standard third-party trust (Plaid is the unavoidable data pipe); Grok sees merchant names only and is droppable |

**Hardening checklist (Phase 3 / Phase 5):** secrets manager for client_secret + APNs key; firewall + key-only SSH + auto-patching on the VPS; per-secret access audit logs; periodic token rotation; revoke = re-link. **Future option (Tier 4):** move the Plaid call into AWS Nitro Enclave or GCP Confidential Cloud Run (scales to zero, low cost) to also close the in-use window — not needed for a single-user app.

### Compromise Detection (built into the security plan)

We cannot detect a stolen token's *read use* on Plaid's side (attacker traffic is indistinguishable from our own app), so detection targets the **breach and the repeated access** instead. All four are required deliverables:

1. **Secrets-manager access alerting.** The `client_secret` (required alongside any token) lives in a secrets manager with audit logging. **Alarm on anomalous retrieval** — fetched outside the expected sync schedule, or from an unexpected process/host. This is the primary tripwire for the compromise that actually matters.
2. **Rotation-collision detection.** Only one party can rotate a token (`invalidate` kills the current one). If a scheduled rotation **fails because the token was already invalidated**, treat it as a theft signal → alert + force re-link. Catches an attacker who rotates.
3. **Intrusion detection on the host.** Because rotation forces an attacker to re-breach every cycle, run host IDS to catch the repeated intrusion: `auditd`, file-integrity monitoring (e.g., AIDE/Tripwire), `fail2ban`, and alerts on unexpected SSH logins / new processes / outbound connections.
4. **App Attest binding on `/sync` (and all device endpoints).** Apple **App Attest** ensures only the genuine app instance can trigger a sync through our server; combined with the secret never leaving the server, an attacker's only path becomes full host compromise — narrowing the surface to the one thing IDS + secrets-alerting watch.

> Structural alternative to detection: **Tier 4** (confidential enclave) removes the in-use theft vector entirely, making this detection layer moot for that vector. Documented as a future option; the four signals above are what ship.

---

## Resolved Decisions
- App name: **MakeTheChoice**
- History backfill: **24 months** (`days_requested` 730, async)
- Budget reset: **1st of each month** (month-scoped queries; limits persist)
- Revolut integration: **via Plaid** (separate Item, not direct Open Banking)
- Sync flow: **server-proxy** (data transits in-memory, never persisted)
- Token custody: **Tier 3 — device-held Secure Enclave key** (server stores ciphertext only) + **secrets manager** for the Plaid client secret. Tier 4 (confidential computing) deferred as a future option.
- Token rotation: **monthly via `/item/access_token/invalidate`**, piggybacked on sync.
- Compromise detection: **secrets-manager alerting + rotation-collision + host IDS + App Attest** (see [security.md](security.md)).
- Backend stack: **Node.js** (Express + `plaid` SDK)
- Chat AI: **on-device fine-tuned LLM** (distillation + QLoRA + constrained decoding)
- Categorization confidence: **classifier softmax** drives ambiguous-expense notifications
- Item-level granularity: **on-device receipt scanning (Vision OCR)** → Layer 0 splits a transaction into per-item categories; matched to Plaid by merchant+date+total; daily push nudges unscanned receipt-worthy transactions
- Savings: tracked as **transfers to Charles Schwab** (seeded merchant → Savings)
- Subscriptions are re-categorizable to **Business** (personal-dev tinkering) while keeping the `is_subscription` flag (flag and category are orthogonal)
- Build order: **iOS + local DB first** (Plaid Sandbox / fixtures)

---

## Appendix: Model Training (Kaggle) Workflow

**Classifier (categorization):**
1. Build dataset from seeded merchants + Plaid Sandbox / synthetic statement entries + collected `training_samples`.
2. Fine-tune MiniLM/DistilBERT classifier (minutes on Kaggle T4/P100).
3. Temperature-scale for calibrated confidence; evaluate accuracy + calibration on held-out set.
4. Convert to Core ML; bundle in app (small).

**Chat LLM (NL → params):**
1. **Distillation dataset:** strong teacher (Claude/Grok) generates thousands of `(question → JSON params)` pairs — all categories, rich period phrasings ("last month", "this year", "since Jan", "Q1"), merchants, budget comparisons, subscription queries, out-of-scope/refusal cases, typos/noise, many paraphrases, hard negatives.
2. **QLoRA (4-bit)** fine-tune on Kaggle (1–3 B fits in 16 GB). LR ~1e-4–2e-4, 2–4 epochs, held-out eval tracking **exact-match on JSON fields**.
3. **Constrained / structured decoding** at inference (JSON-schema or GBNF grammar) — biggest reliability lever for small models.
4. **Quantize to 4-bit**; re-validate post-quant accuracy.
5. Convert for MLX-Swift / llama.cpp; ship via on-demand download.
6. **Retraining loop:** corrections + chat thumbs-down → `training_samples` → periodic re-fine-tune → ship update.
