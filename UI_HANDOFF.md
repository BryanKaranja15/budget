# MakeTheChoice — UI Handoff (start here for the Codex build)

The data layer is done and tested (104 unit tests). **You design SwiftUI in Codex against a
fixed, already-computed contract** — the view-models in `MakeTheChoiceCore`. Views never touch
the database, never format money, never do math. They bind to structs and render.

## Where to start

1. **Create the Xcode app target** in a folder named `MakeTheChoice/` (per your file-org rule).
   - File → New → Project → iOS App, **SwiftUI**, name `MakeTheChoice`, deployment **iOS 17**.
   - Add the local package: File → Add Package Dependencies → "Add Local…" → select this repo
     root (the `Package.swift`), add the `MakeTheChoiceCore` library to the app target.
   - `import MakeTheChoiceCore` and you have every type below.

2. **Design each screen against its view-model.** Every view-model has a `.preview` static so
   you can build entire screens in Xcode Previews / Codex with realistic data and **no database**:

   ```swift
   #Preview { DashboardView(model: .preview) }
   ```

## The 5 screens → their contract

| Screen (plan.md "UI Structure") | View-model | Built by |
|---|---|---|
| 1. Dashboard (donut + category table + month selector) | `DashboardViewModel` | `AppPresenter.dashboard(for:)` |
| 2. Category drilldown (+ "Wrong category?") | `CategoryDetailViewModel` | `AppPresenter.categoryDetail(categoryId:month:)` |
| 3. Subscriptions board | `SubscriptionsBoardViewModel` | `AppPresenter.subscriptionsBoard()` |
| 4. Chat | `ChatViewModel` | (Phase 4 — struct + `.preview` ready now) |
| 5. Receipt scan & splits | `ReceiptSplitViewModel` | `AppPresenter.receiptSplit(receiptId:)` |

Shared types: `Money` (`amount` + `currencyCode` + `.formatted`), `BudgetStatus`
(`none/ok/warning/over` → map to grey/green/amber/red), `CategorySource`,
`SubscriptionStatus`, `ReceiptMatchStatus`.

All view-models are `Codable`, `Hashable`, `Sendable`; list rows are `Identifiable`.

## Wiring data into views (the only glue you write)

`AppPresenter` is the single entry point. Build it once with the live DB + base currency and
call a method per screen. A thin `@Observable` wrapper is all the app needs:

```swift
import SwiftUI
import MakeTheChoiceCore

@Observable @MainActor
final class DashboardStore {
    private let presenter: AppPresenter
    var model: DashboardViewModel
    init(db: AppDatabase, baseCurrency: String, month: MonthKey) throws {
        presenter = AppPresenter(db, baseCurrency: baseCurrency)
        model = try presenter.dashboard(for: month)
    }
}
```

For app boot: `let db = try AppDatabase.makeOnDisk(at: <appSupportURL>/MakeTheChoice.sqlite)`.
For design only: `AppDatabase.makeInMemory(seed: true)` + `try FixtureLoader.load(into: db)`
gives a fully populated DB (two banks, May 2024 data, a Netflix subscription, an internal
transfer, and a Target receipt) so screens render against real numbers without any network.

## What is real now vs. stubbed

- **Real & tested:** dashboard/category/subscriptions/receipt-split view-models, FX conversion,
  internal-transfer detection, subscription detection, receipt categorize→match→split.
- **Stubbed for later (design the UI anyway):**
  - Chat (Screen 4) narration/figure — on-device LLM is Phase 4. The struct + `.preview` exist.
  - Plaid sync / onboarding Link / backfill progress — Phase 3 (backend). Design the empty,
    loading, re-auth, and backfill states from plan.md "Edge / empty states".
  - Camera / share-sheet capture + OCR — Phase 4. Design the capture + review UI; it will feed
    `ReceiptStore.ingest(...)` which already exists.

## Don't break these invariants
- Money always comes pre-converted to base currency via `Money` — don't re-convert in the view.
- Spending excludes internal transfers and income; the presenter already handles it.
- The "Wrong category?" action should call back into the categorization layer (Phase 1 task,
  landing next) — for now wire the button to a closure; the correction API is coming.
