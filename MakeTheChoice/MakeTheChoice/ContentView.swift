import SwiftUI
import UIKit
import UserNotifications
import PhotosUI
import Combine
import MakeTheChoiceCore

/// Shared so the Transactions screen's selection state (which ambiguous charges are
/// picked) drives a header action button living in `ContentView`.
@MainActor final class TransactionScanModel: ObservableObject {
    @Published var selected: Set<UUID> = []
    @Published var launch = false       // toggled to start the batch classify+scan flow
    @Published var requestAdd = false   // toggled to open the single "add a transaction" sheet
}

/// Glassy pill background — Liquid Glass on iOS 26, a tinted capsule fallback below.
private struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Palette.blue), in: Capsule())
        } else {
            content
                .background(Palette.blue, in: Capsule())
                .shadow(color: Palette.blue.opacity(0.4), radius: 8, x: 0, y: 3)
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 2  // "Dashboard" is tab 2
    @StateObject private var scanModel = TransactionScanModel()
    private let tabs = ["Accounts", "Transactions", "Dashboard", "Categories", "Recurrings"]
    @State private var headerHeight: CGFloat = 116
    @State private var topZoneHeight: CGFloat = 304   // header + locked card (when present)
    private let overlap: CGFloat = 100        // blue band height below the header — same on every tab
    private let searchBarDrop: CGFloat = 35   // how far the locked search bar sits below the header
    // Dashboard's budget-card overlap benefits from a longer dissolve; other tabs use a
    // smaller fade so content sits closer under the header/search bar.
    private var fadeHeight: CGFloat { selectedTab == 2 ? 30 : 14 }
    private let scrollGap: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()

            // Blue band behind content
            Palette.blue
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight + overlap)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

            // Scrolling content — disappears into the shadow under the locked zone.
            ScrollView(.vertical, showsIndicators: false) {
                scrollContent
                    .padding(.horizontal, 16)
                    .padding(.top, lockedZoneHeight + fadeHeight + scrollGap)
                    .padding(.bottom, 36)
            }
            .mask(scrollFadeMask)

            // Pinned header + nav bar + (tab-specific) locked card, drawn on top so the
            // scrolling content fades away beneath it.
            VStack(spacing: 0) {
                header
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                        }
                    )
                    .background(Palette.blue.ignoresSafeArea(edges: .top))

                lockedCard
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TopZoneHeightKey.self, value: geo.size.height)
                }
            )
        }
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
        .onPreferenceChange(TopZoneHeightKey.self) { topZoneHeight = $0 }
        .preferredColorScheme(.light)
    }

    /// Dashboard (budget card) and Transactions (search bar) have a locked card; other
    /// tabs start right below the header. The budget card's height is variable so it's
    /// measured (topZoneHeight); the search bar is a fixed 50pt.
    private var hasLockedCard: Bool { selectedTab == 1 || selectedTab == 2 }
    private var lockedZoneHeight: CGFloat {
        switch selectedTab {
        case 1: return headerHeight + searchBarDrop + 50 + 12 + 44  // header + drop + search + gap + add button
        case 2: return topZoneHeight                       // header + budget card (measured)
        default: return headerHeight
        }
    }

    /// The element that stays locked over the blue band per tab — Transactions' search
    /// bar and Dashboard's budget card. Other tabs scroll all of their content.
    @ViewBuilder private var lockedCard: some View {
        switch selectedTab {
        case 1:
            // Search bar + "add" button both stay locked over the blue band so the user can
            // keep selecting ambiguous charges and reach the launcher; the month summary and
            // the list scroll away beneath them.
            VStack(spacing: 12) {
                TransactionSearchBar()
                lockedAddButton
            }
            .padding(.top, searchBarDrop)
            .padding(.horizontal, 16)
        case 2:
            // Only the budget card is locked; TO REVIEW scrolls with everything else.
            BudgetOverviewCard()
                .padding(.horizontal, 16)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var scrollContent: some View {
        switch selectedTab {
        case 1:  // Transactions
            TransactionsPageView(scanModel: scanModel)
        case 2:  // Dashboard
            DashboardView(onViewAllTransactions: { selectedTab = 1 },
                          onShowCategories: { selectedTab = 3 })
        case 3:  // Categories
            CategoriesPageView()
        default:
            Text("Tab \(selectedTab)")
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 40)
        }
    }

    private var scrollFadeMask: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: lockedZoneHeight)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fadeHeight)
            Color.black
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                Spacer()
                Text("Copilot")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            tabStrip
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
    }

    /// The locked "add" button under the search bar. With nothing selected it's the dotted
    /// "ADD A NEW TRANSACTION" placeholder; once ambiguous charges are selected it morphs
    /// into a glassy blue launcher for the batch classify+scan flow. Because it's locked, it
    /// stays in reach while the user scrolls and keeps selecting charges from the list.
    private var lockedAddButton: some View {
        let count = scanModel.selected.count
        return Button(action: {
            if count == 0 { scanModel.requestAdd = true } else { scanModel.launch = true }
        }) {
            Group {
                if count == 0 {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Palette.blue).frame(width: 22, height: 22)
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("ADD A NEW TRANSACTION")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Palette.textSecondary.opacity(0.45),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.viewfinder")
                        Text("SPLIT SELECTED TRANSACTIONS")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .modifier(GlassPill())
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tabs.indices, id: \.self) { index in
                        let selected = index == selectedTab
                        Text(tabs[index])
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.blue : .white)
                            .padding(.horizontal, selected ? 16 : 6)
                            .frame(height: 34)
                            .background { if selected { Capsule().fill(.white) } }
                            .id(index)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = index }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.07),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .onAppear { proxy.scrollTo(selectedTab, anchor: .center) }
            .onChange(of: selectedTab) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    /// Live data contract (currently rendered with prototype values matching the
    /// reference; wire to `AppPresenter.dashboard(for:)` when the data layer connects).
    var model: DashboardViewModel = .preview
    var onViewAllTransactions: (() -> Void)?
    var onShowCategories: (() -> Void)?

    /// Only the budget card is locked in `ContentView` (overlaps the blue). Everything
    /// here — including TO REVIEW — scrolls underneath it. The review cards are tap-only
    /// (no swipe gesture), so scrolling with a thumb over them stays smooth.
    var body: some View {
        VStack(spacing: 16) {
            BudgetIconsSection(onShowCategories: onShowCategories ?? {})
                .sectionScroll()
            ToReviewSection(onViewAll: onViewAllTransactions)
                .sectionScroll()
            UpcomingSection()
                .sectionScroll()
            IncomeSection()
                .sectionScroll()
        }
    }
}

private extension View {
    /// A consistent, scroll-driven enter/leave for each dashboard section: as a bucket
    /// crosses the top or bottom edge of the scroll viewport it fades, scales down, and
    /// eases vertically. Tied to scroll position (not a timed animation) so it always
    /// feels smooth instead of popping in/out.
    func sectionScroll() -> some View {
        scrollTransition(axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.92, anchor: .center)
                .offset(y: phase.value * 16)
        }
    }
}

private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 116
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TopZoneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 304
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Budget overview

private struct BudgetOverviewCard: View {
    // Data inputs (placeholder values match references/dashboard.png). When the data
    // layer connects, feed these from `AppPresenter.dashboard(for:)`:
    //   amountLeft / totalBudgeted -> formatted figures
    //   progress  = fraction of the month elapsed (daysElapsed / daysInMonth)
    //   variance  = budget − projectedSpend, sign drives "under"/"over" + color
    var amountLeft = "$1,592"
    var totalBudgeted = "$1,612"
    var progress: CGFloat = 0.045        // time elapsed: daysElapsed / daysInMonth
    var spendFraction: CGFloat = 0.012   // money spent: spent / totalBudget
    var varianceLabel = "$53 under"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text("\(amountLeft) left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 22)

                Text("out of \(totalBudgeted) budgeted")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 3)

                BudgetTrendLine(progress: progress, spendFraction: spendFraction, varianceLabel: varianceLabel)
                    .padding(.top, 14)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
            }

            Image(systemName: "questionmark.circle")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: 0xC7C7CC))
                .padding(.top, 20)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 188)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

private struct BudgetTrendLine: View {
    /// `progress` = fraction of the month elapsed (x axis, time).
    /// `spendFraction` = spent / totalBudget (y axis, money).
    /// The dot floats relative to the dashed pace line: below = under budget (green),
    /// above = over budget (red). Early in the month both are near 0 → bottom-left.
    var progress: CGFloat = 0.045
    var spendFraction: CGFloat = 0.012
    var varianceLabel = "$53 under"

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let x = w * min(max(progress, 0), 1)

            // Pace line: $0 at month start (bottom-left) → full budget at month end (top-right).
            let paceStart = CGPoint(x: 0, y: h)
            let paceEnd = CGPoint(x: w, y: 0)

            // Actual spend dot: y is driven by money spent, independent of time.
            let dot = CGPoint(x: x, y: h * (1 - min(max(spendFraction, 0), 1)))

            // Under budget when spent less than the time-proportional pace.
            let isUnder = spendFraction <= progress
            let color = isUnder ? Palette.green : Color(hex: 0xFF3B30)

            ZStack(alignment: .topLeading) {
                // The budget pace reference (dashed, full width).
                Path { p in p.move(to: paceStart); p.addLine(to: paceEnd) }
                    .stroke(Color(hex: 0xC7C7CC), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                // Actual spending trajectory so far (origin → today's dot).
                Path { p in p.move(to: paceStart); p.addLine(to: dot) }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                Circle()
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .position(dot)

                VarianceBadge(label: varianceLabel, color: color)
                    .position(x: dot.x + 28, y: dot.y - 22)
            }
        }
        .frame(height: 96)
    }
}

private struct VarianceBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(color, in: Capsule())
            .overlay(alignment: .bottomLeading) {
                DownTriangle()
                    .fill(color)
                    .frame(width: 8, height: 5)
                    .offset(x: 10, y: 4)
            }
    }
}

private struct DownTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - To review

/// A single transaction awaiting review. Prototype data; when the data layer connects,
/// these come from a `toReview` contract on the presenter (merchant, category, base
/// amount, account — same shape as `CategoryDetailViewModel.TransactionRow`).
private struct ReviewTransaction: Identifiable {
    let id = UUID()
    let merchant: String
    let categoryName: String     // display label, e.g. "ENTERTAINMENT"
    let categoryIcon: String     // emoji glyph
    let categoryColor: Color     // pill tint
    let amount: String
    let account: String          // "Chase Credit… 8533"
    let dateLong: String         // "Wednesday, Jun 24, 2026"
    /// A single charge that likely bundles several categories (e.g. a Target run).
    /// Can't be auto-categorized → prompt the user to clarify with a receipt scan.
    var needsReceipt: Bool = false
}

/// One day's worth of transactions to review — the unit shown per stacked card.
private struct ReviewGroup: Identifiable {
    let id = UUID()
    let dateLabel: String        // "Wednesday, Jun 24"
    let transactions: [ReviewTransaction]
}

private extension ReviewGroup {
    static var samples: [ReviewGroup] {
        let entertainment = (name: "ENTERTAINMENT", icon: "🎟️", color: Palette.red)
        let restaurants = (name: "RESTAURANTS", icon: "🍔", color: Color(hex: 0xE8833A))
        let transport = (name: "TRANSPORT", icon: "🚗", color: Color(hex: 0x4C8DF5))
        let shopping = (name: "SHOPPING", icon: "🛍️", color: Color(hex: 0xA468E0))
        let acct = "Chase Credit… 8533"
        return [
            // Sorted from today backwards.
            ReviewGroup(dateLabel: "Wednesday, Jun 24", transactions: [
                .init(merchant: "Wine & Spirits", categoryName: entertainment.name,
                      categoryIcon: entertainment.icon, categoryColor: entertainment.color,
                      amount: "$40.00", account: acct, dateLong: "Wednesday, Jun 24, 2026"),
                .init(merchant: "Target", categoryName: shopping.name,
                      categoryIcon: shopping.icon, categoryColor: shopping.color,
                      amount: "$87.34", account: acct, dateLong: "Wednesday, Jun 24, 2026",
                      needsReceipt: true),
                .init(merchant: "Fries And Bites", categoryName: restaurants.name,
                      categoryIcon: restaurants.icon, categoryColor: restaurants.color,
                      amount: "$20.11", account: acct, dateLong: "Wednesday, Jun 24, 2026")
            ]),
            ReviewGroup(dateLabel: "Tuesday, Jun 23", transactions: [
                .init(merchant: "Blue Bottle Coffee", categoryName: restaurants.name,
                      categoryIcon: restaurants.icon, categoryColor: restaurants.color,
                      amount: "$6.50", account: acct, dateLong: "Tuesday, Jun 23, 2026"),
                .init(merchant: "Lyft", categoryName: transport.name,
                      categoryIcon: transport.icon, categoryColor: transport.color,
                      amount: "$18.40", account: acct, dateLong: "Tuesday, Jun 23, 2026")
            ]),
            ReviewGroup(dateLabel: "Monday, Jun 22", transactions: [
                .init(merchant: "Amazon", categoryName: shopping.name,
                      categoryIcon: shopping.icon, categoryColor: shopping.color,
                      amount: "$54.99", account: acct, dateLong: "Monday, Jun 22, 2026",
                      needsReceipt: true)
            ])
        ]
    }
}

/// Persists which day-cards have been fully reviewed, so a partially-finished list
/// resumes with only the remaining days next launch. Keyed by the day's stable label.
private enum ReviewStore {
    private static let key = "reviewedDayKeys"
    static var reviewedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }
    static func markReviewed(_ dayKey: String) {
        var s = reviewedKeys; s.insert(dayKey); reviewedKeys = s
    }
    /// Days still needing review (samples minus the ones already completed).
    static var remainingDays: [ReviewGroup] {
        ReviewGroup.samples.filter { !reviewedKeys.contains($0.dateLabel) }
    }
}

private struct ToReviewSection: View {
    @State private var groups: [ReviewGroup] = ReviewStore.remainingDays
    @State private var selectedGroup: ReviewGroup?      // the day whose sheet is open
    @State private var autoAcceptId: UUID?              // day-card to slide off after its sheet finishes
    @State private var pendingFinishId: UUID?           // set when a sheet fully completes
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            SectionHeader(title: "TRANSACTIONS TO REVIEW", action: "all transactions", onAction: onViewAll)

            if groups.isEmpty {
                ReviewEmptyState()
            } else {
                ReviewCardStack(groups: $groups, autoAcceptId: $autoAcceptId,
                                onOpen: { selectedGroup = $0 },
                                onAccepted: { ReviewStore.markReviewed($0.dateLabel) })
            }
        }
        .sheet(item: $selectedGroup, onDismiss: handleDismiss) { group in
            ReviewDaySheet(group: group, onFinished: {
                // Mark for the dashboard-card slide-off, then close the sheet downward.
                pendingFinishId = group.id
                selectedGroup = nil
            })
            // Sits just below the trend chart (see reference) — taller than .medium.
            .presentationDetents([.fraction(0.68), .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// After the sheet closes: if the day was fully reviewed, send its card off the deck.
    private func handleDismiss() {
        if let id = pendingFinishId {
            autoAcceptId = id
            pendingFinishId = nil
        }
    }
}

/// Shown once every card has been swiped away.
private struct ReviewEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.green.opacity(0.12)).frame(width: 54, height: 54)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.green)
            }
            Text("You're all caught up")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

// MARK: Stacked, tappable review cards (locked in place — no swipe)

private struct ReviewCardStack: View {
    @Binding var groups: [ReviewGroup]
    @Binding var autoAcceptId: UUID?
    var onOpen: (ReviewGroup) -> Void
    var onAccepted: (ReviewGroup) -> Void = { _ in }

    var body: some View {
        // Top-aligned so each card behind peeks a fixed amount above the front one,
        // regardless of how many transactions (and thus how tall) each card is.
        ZStack(alignment: .top) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                ReviewCard(
                    group: group,
                    depth: index,
                    autoAccept: group.id == autoAcceptId,
                    onOpen: { onOpen(group) },
                    onAccept: { accept(group) }
                )
                // Front card (index 0) draws on top of the deck.
                .zIndex(Double(groups.count - index))
            }
        }
        .padding(.top, 30)   // headroom so the single peeking card isn't cramped
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: groups.count)
    }

    private func accept(_ group: ReviewGroup) {
        onAccepted(group)   // persist before removing so it stays gone next launch
        groups.removeAll { $0.id == group.id }
        autoAcceptId = nil
    }
}

private struct ReviewCard: View {
    let group: ReviewGroup
    let depth: Int
    /// Set by the parent once the day's sheet has been fully reviewed → slide off.
    let autoAccept: Bool
    let onOpen: () -> Void
    let onAccept: () -> Void

    @State private var accepted = false   // true while sliding off after a completed review

    // Only the front card and one card behind it show (a blank, faded peek above) so
    // multiple pending days read as a stack without exposing the dates behind.
    private var depthC: Int { min(depth, 1) }
    private var stackScale: CGFloat { 1 - 0.06 * CGFloat(depthC) }
    private var stackOffsetY: CGFloat { -14 * CGFloat(depthC) }
    private var stackOpacity: Double {
        switch depth {
        case 0: return 1
        case 1: return 0.6
        default: return 0     // cards beyond the second are hidden
        }
    }

    /// Front card shows its content; the card behind is blanked (keeps its size so the
    /// peek is a clean card edge, but hides the date/rows).
    @ViewBuilder private var visibleContent: some View {
        if depth == 0 {
            cardContent
        } else {
            cardContent.opacity(0)
        }
    }

    var body: some View {
        visibleContent
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
            .shadow(color: Palette.green.opacity(accepted ? 0.5 : 0), radius: 16)
            .overlay { if accepted { AcceptCheckBadge() } }
            // No manual swipe: the card only slides off after a review is completed.
            .rotationEffect(.degrees(accepted ? 16 : 0), anchor: .bottomLeading)
            .offset(x: accepted ? 700 : 0)
            .scaleEffect(stackScale, anchor: .top)
            .offset(y: stackOffsetY)
            .opacity(stackOpacity)
            .contentShape(Rectangle())
            .onTapGesture { if depth == 0 { onOpen() } }
            .allowsHitTesting(depth == 0)
            .onChange(of: autoAccept) { _, now in
                if now { slideOff() }
            }
    }

    private var cardContent: some View {
        VStack(spacing: 16) {
            Text(group.dateLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.blue)

            VStack(spacing: 14) {
                ForEach(group.transactions) { txn in
                    ReviewRow(txn: txn)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11))
                Text("Tap to review")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Palette.blue)
        }
        .padding(16)
    }

    /// Slides the day-card off after its review is completed (driven by `autoAccept`).
    private func slideOff() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeIn(duration: 0.32)) { accepted = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onAccept() }
    }
}

/// Reusable green circle + white check, with a soft green glow.
private struct AcceptCheckBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.green)
                .frame(width: 66, height: 66)
                .shadow(color: Palette.green.opacity(0.6), radius: 12)
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct ReviewRow: View {
    let txn: ReviewTransaction

    var body: some View {
        HStack(spacing: 8) {
            Text(txn.merchant)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Pills right-align against a fixed-width price column so amounts line up.
            CategoryPill(name: txn.categoryName, icon: txn.categoryIcon, color: txn.categoryColor)
                .layoutPriority(1)

            Text(txn.amount)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

private struct CategoryPill: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 11))
            Text(name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: Per-day review sheet

/// Editable categories the reviewer can pick from. Prototype set; maps to the app's
/// 12 category slugs when the data layer connects.
private struct CategoryOption: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
}

private enum CategoryCatalog {
    static let base: [CategoryOption] = [
        .init(name: "ENTERTAINMENT", icon: "🎟️", color: Palette.red),
        .init(name: "RESTAURANTS", icon: "🍔", color: Color(hex: 0xE8833A)),
        .init(name: "TRANSPORT", icon: "🚗", color: Color(hex: 0x4C8DF5)),
        .init(name: "SHOPPING", icon: "🛍️", color: Color(hex: 0xA468E0)),
        .init(name: "GROCERIES", icon: "🛒", color: Color(hex: 0x34A853)),
        .init(name: "HEALTH", icon: "💊", color: Color(hex: 0x2BB5A8))
    ]
    /// Categories the user creates at runtime (session-only in the prototype).
    static var custom: [CategoryOption] = []
    static var all: [CategoryOption] { base + custom }

    static func addCustom(_ option: CategoryOption) { custom.append(option) }

    static func option(for name: String) -> CategoryOption {
        all.first { $0.name == name } ?? base[0]
    }
}

/// The half-screen sheet for one day: a horizontal deck of that day's transactions,
/// reviewed one at a time. The center card is under review; remaining ones peek in
/// from the faded left. Finishing the last one calls `onFinished`.
private struct ReviewDaySheet: View {
    let group: ReviewGroup
    var onFinished: () -> Void

    @State private var pending: [ReviewTransaction]
    @State private var exitingId: UUID?

    init(group: ReviewGroup, onFinished: @escaping () -> Void) {
        self.group = group
        self.onFinished = onFinished
        _pending = State(initialValue: group.transactions)
    }

    private var reviewedCount: Int { group.transactions.count - pending.count }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                deck
            }
            .padding(.top, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(group.dateLabel)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.blue)
            Text("\(reviewedCount) of \(group.transactions.count) reviewed")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var deck: some View {
        GeometryReader { geo in
            let cardW = min(geo.size.width - 64, 360)
            ZStack {
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, txn in
                    DayReviewCard(
                        txn: txn,
                        isCurrent: index == 0,
                        exiting: txn.id == exitingId,
                        onReviewed: review
                    )
                    .frame(width: cardW)
                    // Waiting cards fan to the left, pivoting on their LEFT edge so a
                    // promotion swings the right side through a C-curve while the left
                    // edge barely moves. The card being reviewed slides straight right.
                    .scaleEffect(scale(index: index, txn: txn), anchor: .leading)
                    .rotationEffect(.degrees(rotation(index: index, txn: txn)), anchor: .leading)
                    .offset(x: xOffset(index: index, txn: txn, width: geo.size.width))
                    .opacity(opacity(index: index, txn: txn))
                    .zIndex(Double(pending.count - index))
                    .allowsHitTesting(index == 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: pending.count)
        }
        .padding(.horizontal, 16)
    }

    private func depthC(_ index: Int) -> Int { min(index, 2) }

    private func rotation(index: Int, txn: ReviewTransaction) -> Double {
        if txn.id == exitingId { return 0 }              // exit slides straight, no tilt
        return Double(depthC(index)) * -7                // waiting cards lean left
    }

    private func scale(index: Int, txn: ReviewTransaction) -> CGFloat {
        if txn.id == exitingId { return 1 }
        return 1 - 0.03 * CGFloat(depthC(index))
    }

    private func xOffset(index: Int, txn: ReviewTransaction, width: CGFloat) -> CGFloat {
        if txn.id == exitingId { return width * 1.1 }    // slide fully off to the right
        return index == 0 ? 0 : -CGFloat(depthC(index)) * 14   // waiting cards peek left
    }

    private func opacity(index: Int, txn: ReviewTransaction) -> Double {
        if txn.id == exitingId { return 1 }
        switch index {
        case 0: return 1
        case 1: return 0.6
        default: return 0.3
        }
    }

    private func review() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard let first = pending.first else { return }
        withAnimation(.easeIn(duration: 0.28)) { exitingId = first.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                _ = pending.removeFirst()
            }
            exitingId = nil
            if pending.isEmpty {
                // Let the last card settle, then close the sheet + slide the day-card off.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onFinished() }
            }
        }
    }
}

private struct DayReviewCard: View {
    let txn: ReviewTransaction
    let isCurrent: Bool
    let exiting: Bool
    var onReviewed: () -> Void

    @State private var category: CategoryOption
    @State private var note: String = ""
    @State private var receiptItems: [ReceiptLineItem] = []   // populated after a receipt scan
    @State private var showCapture = false
    @State private var captureSource: ReceiptSource = .camera
    @State private var showCategoryPicker = false
    @State private var reminderTime: Date?       // set when "Save for later" schedules a nudge
    @State private var showReminder = false
    @FocusState private var noteFocused: Bool

    init(txn: ReviewTransaction, isCurrent: Bool, exiting: Bool, onReviewed: @escaping () -> Void) {
        self.txn = txn
        self.isCurrent = isCurrent
        self.exiting = exiting
        self.onReviewed = onReviewed
        _category = State(initialValue: CategoryCatalog.option(for: txn.categoryName))
    }

    /// Still needs a receipt scan before it can be reviewed (and hasn't been deferred).
    private var awaitingReceipt: Bool {
        txn.needsReceipt && receiptItems.isEmpty && reminderTime == nil
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(txn.merchant)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(txn.amount)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if !receiptItems.isEmpty {
                receiptSplitSection
            } else if txn.needsReceipt {
                if let reminderTime {
                    reminderSetView(reminderTime)
                } else {
                    clarifyPrompt
                }
            } else {
                categorySection
                AccountCard(account: txn.account)
                    .scaleEffect(0.92)
            }

            if isCurrent {
                // A free-text hint the categorization AI uses as context about what
                // this purchase was for (e.g. "work lunch" → Business).
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    TextField("Add context to help categorize", text: $note)
                        .font(.system(size: 15))
                        .focused($noteFocused)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Palette.background, in: Capsule())
                // Make the whole capsule focus the field on a single tap.
                .contentShape(Capsule())
                .onTapGesture { noteFocused = true }

                // Only show Reviewed once it's actionable (ambiguous charges use the
                // two blue clarify buttons above instead).
                if !awaitingReceipt {
                    Button(action: onReviewed) {
                        Text(reminderTime != nil && receiptItems.isEmpty ? "Done for now" : "Reviewed")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Palette.blue, in: Capsule())
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 5)
        .shadow(color: Palette.green.opacity(exiting ? 0.5 : 0), radius: 16)
        .overlay { if exiting { AcceptCheckBadge() } }
        .fullScreenCover(isPresented: $showCapture) {
            ReceiptCaptureSheet(merchant: txn.merchant, total: txn.amount, source: captureSource,
                                showCameraFirst: captureSource == .camera) { items in
                withAnimation(.easeInOut(duration: 0.25)) { receiptItems = items }
            }
        }
        .sheet(isPresented: $showReminder) {
            ReminderSheet(merchant: txn.merchant) { time in
                withAnimation(.easeInOut(duration: 0.2)) { reminderTime = time }
            }
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Normal single-category section

    private var categorySection: some View {
        VStack(spacing: 8) {
            Text("CATEGORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.blue)

            if isCurrent {
                // Same bottom-sheet picker as the rest of the app (dim fades, options
                // slide up) — and it includes the "Add a category" option.
                Button(action: { showCategoryPicker = true }) {
                    HStack(spacing: 6) {
                        CategoryPill(name: category.name, icon: category.icon, color: category.color)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showCategoryPicker) {
                    CategoryPickerSheet { sel in
                        withAnimation(.easeInOut(duration: 0.15)) { category = sel }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            } else {
                CategoryPill(name: category.name, icon: category.icon, color: category.color)
            }
        }
    }

    // MARK: Receipt-needed prompt (ambiguous multi-category charge)

    private var clarifyPrompt: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.split.2x2.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("MIXED PURCHASE")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.blue)

            Text("This charge likely spans a few categories. Scan the receipt to split it accurately.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrent {
                clarifyButton(icon: "camera.fill", title: "Clarify with receipt image", source: .camera)
                clarifyButton(icon: "photo.on.rectangle", title: "Screenshot Online Receipt", source: .screenshot)

                Button(action: { showReminder = true }) {
                    Text("Save for later")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Shown after the user defers via "Save for later" and schedules a nudge.
    private func reminderSetView(_ time: Date) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("REMINDER SET")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.blue)

            Text("We'll nudge you at \(time, format: .dateTime.hour().minute()) to scan this receipt.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrent {
                Button(action: { showReminder = true }) {
                    Text("Change time")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func clarifyButton(icon: String, title: String, source: ReceiptSource) -> some View {
        Button(action: {
            captureSource = source
            showCapture = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Palette.blue, in: Capsule())
        }
    }

    // MARK: Receipt split result

    private var receiptSplitSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("SPLIT INTO \(receiptItems.count) ITEMS")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.green)

            VStack(spacing: 8) {
                ForEach(receiptItems) { item in
                    HStack(spacing: 10) {
                        Text(item.category.icon).font(.system(size: 15))
                        Text(item.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(item.amount)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
            }

            if isCurrent {
                Button(action: { showCapture = true }) {
                    Text("Re-scan")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Receipt capture & line-item split

/// A line item extracted from a scanned receipt, with an AI-suggested category.
private struct ReceiptLineItem: Identifiable {
    let id = UUID()
    var name: String
    var amount: String
    var category: CategoryOption
}

/// Where the receipt artifact came from — drives the analyzing copy.
private enum ReceiptSource { case camera, screenshot }

/// Receipt clarification flow: simulated Grok analysis → review & edit the line-item
/// split. Launched directly from the card's two clarify buttons. Calls `onComplete`.
///
/// NOTE: Grok extraction + the on-device camera/Vision OCR are simulated here. The real
/// pipeline (camera capture, `POST /categorize/items`) lands in Phase 4 — this is the UI.
private struct ReceiptCaptureSheet: View {
    let merchant: String
    let total: String
    /// The bulk charge's date, shown on the confirm-photo card so the user can verify the
    /// receipt is matched to the right transaction. nil = no charge to confirm against.
    var date: Date? = nil
    let source: ReceiptSource
    var showCameraFirst: Bool = false
    /// When true this sheet is one step in a sequence: saving hands off to `onComplete`
    /// (which advances to the next receipt) instead of self-dismissing.
    var continues: Bool = false
    var onComplete: ([ReceiptLineItem]) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case camera, captured, analyzing, review }
    @State private var phase: Phase
    @State private var items: [ReceiptLineItem] = []
    @State private var editingItem: EditingID?         // line item whose category is being changed

    init(merchant: String, total: String, date: Date? = nil, source: ReceiptSource,
         showCameraFirst: Bool = false, continues: Bool = false,
         onComplete: @escaping ([ReceiptLineItem]) -> Void) {
        self.merchant = merchant
        self.total = total
        self.date = date
        self.source = source
        self.showCameraFirst = showCameraFirst
        self.continues = continues
        self.onComplete = onComplete
        _phase = State(initialValue: showCameraFirst ? .camera : .analyzing)
    }

    private var onDark: Bool { phase == .camera || phase == .captured }
    private var title: String {
        switch phase {
        case .camera: return "Scan receipt"
        case .captured: return "Confirm receipt"
        case .analyzing: return "Reading…"
        case .review: return "Review split"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            (onDark ? Color.black : Palette.background).ignoresSafeArea()

            switch phase {
            case .camera:    cameraView
            case .captured:  capturedView
            case .analyzing: analyzingView
            case .review:    reviewView
            }

            // Top bar (title + close)
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(onDark ? .white : Palette.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(onDark ? .white : Palette.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .onAppear(perform: startAnalyzing)
        // Recategorize a line item — bottom sheet (dim fades, options slide up).
        .sheet(item: $editingItem) { target in
            CategoryPickerSheet { sel in
                if let idx = items.firstIndex(where: { $0.id == target.id }) {
                    items[idx].category = sel
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Camera viewfinder (mock — real capture is Phase 4)

    private var cameraView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                    .frame(width: 230, height: 300)
                Text("Position the receipt in frame")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button(action: capture) {
                    ZStack {
                        Circle().fill(.white).frame(width: 72, height: 72)
                        Circle().stroke(.white, lineWidth: 3).frame(width: 84, height: 84)
                    }
                }
                .padding(.bottom, 44)
            }
        }
    }

    private func capture() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { phase = .captured }
    }

    // MARK: Confirm the captured shot (before reading / moving to the next receipt)

    private var capturedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        capturedPhoto
                        if hasCharge {
                            chargeConfirmCard
                            matchStatus
                        } else {
                            Text("Is the whole receipt clear and in frame?")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 64)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                HStack(spacing: 12) {
                    Button(action: { withAnimation { phase = .camera } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Retake")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(.white.opacity(0.15), in: Capsule())
                    }
                    Button(action: useCapturedPhoto) {
                        HStack(spacing: 6) {
                            Image(systemName: discrepancies.isEmpty ? "checkmark" : "exclamationmark.triangle.fill")
                            Text(discrepancies.isEmpty ? "Use photo" : "Use anyway")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(discrepancies.isEmpty ? Palette.blue : Palette.amber, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
    }

    // Stand-in for the captured photo (real frame lands in Phase 4).
    private var capturedPhoto: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.12))
                .frame(width: 210, height: 264)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                )
            VStack(spacing: 10) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.85))
                Text(merchant)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(total)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// The bulk charge this receipt is being matched to — confirm vendor, date and price.
    private var chargeConfirmCard: some View {
        HStack(spacing: 12) {
            Text("🧾").font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Palette.background, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(merchant)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let date {
                    Text(BatchClassifySheet.fullDate(date))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            Text(total)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    /// AI check: green when the read receipt matches the charge, amber prompt when it doesn't.
    @ViewBuilder private var matchStatus: some View {
        if discrepancies.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.green)
                Text("Vendor, date and total match this charge.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Palette.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.amber)
                    Text("This receipt may not match the charge")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                ForEach(discrepancies, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Palette.amber)
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Text("Retake the photo, or use it anyway if the charge is correct.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var hasCharge: Bool { !total.isEmpty }

    /// Stand-in for Grok reading the receipt (real OCR lands in Phase 4). Normally returns
    /// values matching the charge; here Amazon simulates a total mismatch to show the flag.
    private var detectedReceipt: (vendor: String, total: String, date: Date?) {
        if merchant.lowercased().contains("amazon") {
            return (vendor: merchant, total: "$118.00", date: date)
        }
        return (vendor: merchant, total: total, date: date)
    }

    /// Field-by-field comparison of the read receipt against the charge.
    private var discrepancies: [String] {
        guard hasCharge else { return [] }
        let d = detectedReceipt
        var out: [String] = []
        if d.vendor.lowercased() != merchant.lowercased() {
            out.append("Receipt vendor reads “\(d.vendor)”, not \(merchant).")
        }
        if let read = Self.amountValue(d.total), let charge = Self.amountValue(total),
           abs(read - charge) > 0.005 {
            out.append("Receipt total is \(d.total) but the charge is \(total).")
        }
        if let dd = d.date, let cd = date, !Calendar.current.isDate(dd, inSameDayAs: cd) {
            out.append("Receipt date doesn't match the charge date.")
        }
        return out
    }

    private static func amountValue(_ s: String) -> Double? {
        Double(s.filter { $0.isNumber || $0 == "." })
    }

    private func useCapturedPhoto() {
        withAnimation { phase = .analyzing }
        scheduleAnalyze()
    }

    // MARK: Analyzing (simulated Grok)

    private var analyzingView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
                .tint(Palette.blue)
            Text(source == .screenshot ? "Reading your screenshot…" : "Reading your receipt…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Identifying line items and categories")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Spacer()
        }
    }

    // MARK: Review & edit split

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Text("Found \(items.count) items in \(merchant)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 4)

                    if let single = singleCategoryName {
                        learningNote(for: single)
                    }

                    VStack(spacing: 10) {
                        ForEach($items) { $item in
                            ReceiptItemRow(item: $item) { editingItem = EditingID(id: item.id) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 100)
            }

            // Save bar
            Button(action: { onComplete(items); if !continues { dismiss() } }) {
                Text("Save split")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Palette.blue, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }

    /// If every item resolved to one category, the store is probably single-category —
    /// surface that we'll remember it so it won't need review next time.
    private var singleCategoryName: String? {
        let names = Set(items.map { $0.category.name })
        return names.count == 1 ? names.first : nil
    }

    private func learningNote(for category: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16))
                .foregroundStyle(Palette.blue)
            Text("Looks like \(merchant) is all \(category.capitalized). We'll remember it so it won't need review next time.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Actions

    private func startAnalyzing() {
        // Only auto-start when we open straight into analysis (not the camera viewfinder).
        guard phase == .analyzing, items.isEmpty else { return }
        scheduleAnalyze()
    }

    private func scheduleAnalyze() {
        // Simulate Grok latency, then return classified line items.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            items = Self.simulatedItems(for: merchant)
            withAnimation { phase = .review }
        }
    }

    /// Stand-in for Grok's `POST /categorize/items` response.
    private static func simulatedItems(for merchant: String) -> [ReceiptLineItem] {
        func cat(_ name: String) -> CategoryOption { CategoryCatalog.option(for: name) }
        let m = merchant.lowercased()
        if m.contains("target") {
            return [
                .init(name: "Bananas", amount: "$2.40", category: cat("GROCERIES")),
                .init(name: "Frozen Pizza", amount: "$5.99", category: cat("GROCERIES")),
                .init(name: "Paper Towels", amount: "$8.99", category: cat("SHOPPING")),
                .init(name: "Cotton T-Shirt", amount: "$12.00", category: cat("SHOPPING")),
                .init(name: "Ibuprofen", amount: "$6.49", category: cat("HEALTH"))
            ]
        } else if m.contains("amazon") {
            return [
                .init(name: "USB-C Cable", amount: "$14.99", category: cat("SHOPPING")),
                .init(name: "Kindle eBook", amount: "$9.99", category: cat("ENTERTAINMENT")),
                .init(name: "Protein Bars", amount: "$19.99", category: cat("GROCERIES")),
                .init(name: "Phone Case", amount: "$9.99", category: cat("SHOPPING"))
            ]
        } else {
            return [
                .init(name: "Item A", amount: "$12.00", category: cat("SHOPPING")),
                .init(name: "Item B", amount: "$8.50", category: cat("GROCERIES"))
            ]
        }
    }
}

/// One editable receipt line item: name → category pill (tap to recategorize) → price,
/// matching the Transactions list layout/order.
private struct ReceiptItemRow: View {
    @Binding var item: ReceiptLineItem
    var onEditCategory: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Item name", text: $item.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)

            Spacer(minLength: 8)

            Button(action: onEditCategory) {
                CategoryPill(name: item.category.name, icon: item.category.icon, color: item.category.color)
            }
            .buttonStyle(.plain)

            TextField("$0.00", text: $item.amount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Save for later (reminder + local notification)

/// Schedules a local notification nudging the user to scan a receipt later. A local
/// notification stands in for the planned daily push (Phase 4 wires the real push).
private enum ReminderScheduler {
    static func schedule(merchant: String, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Scan your \(merchant) receipt"
            content.body = "You saved this to review later — got the receipt handy?"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: trigger))
        }
    }

    /// Suggested "you're probably home with receipts" time — today at 7pm, or tomorrow
    /// if it's already past.
    static func suggestedTime() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 19
        comps.minute = 0
        let sevenPM = cal.date(from: comps) ?? now
        return sevenPM > now ? sevenPM : (cal.date(byAdding: .day, value: 1, to: sevenPM) ?? sevenPM)
    }
}

/// Lets the user pick a time to be reminded to scan a receipt, pre-suggesting a
/// likely "at home" hour. Schedules a local notification on confirm.
private struct ReminderSheet: View {
    let merchant: String
    var onScheduled: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date = ReminderScheduler.suggestedTime()

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Remind me to scan")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("We'll nudge you to scan the \(merchant) receipt.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                HStack(spacing: 6) {
                    Image(systemName: "house.fill").font(.system(size: 11))
                    Text("Pick a time you're usually home with receipts")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.blue.opacity(0.08), in: Capsule())

                DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button(action: {
                    ReminderScheduler.schedule(merchant: merchant, at: time)
                    onScheduled(time)
                    dismiss()
                }) {
                    Text("Set reminder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Palette.blue, in: Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

private struct AccountCard: View {
    let account: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 6) {
                Text("CHASE")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
            Text(account)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: 230, alignment: .leading)
        .frame(height: 110)
        .background(Color(hex: 0x1565C0), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Budgets

private struct BudgetIconItem: Identifiable {
    let id = UUID()
    let categoryId: String       // e.g. "housing", "food"
    let categoryName: String     // display name
    let icon: String
    let amount: String
    let amountValue: Double      // numeric for sorting
    let ringProgress: Double?    // green arc (active) when set
    let dot: Bool                // small green status dot
    let color: Color
    let transactions: [BudgetTransactionRow]
}

private struct BudgetTransactionRow: Identifiable {
    let id = UUID()
    let merchant: String
    let amount: String
    let amountValue: Double      // numeric for sorting
}

private struct BudgetIconsSection: View {
    @State private var selectedCategory: BudgetIconItem?
    var onShowCategories: () -> Void = {}

    private let items: [BudgetIconItem] = [
        .init(categoryId: "housing", categoryName: "Housing", icon: "🧧", amount: "$225",
              amountValue: 225, ringProgress: nil, dot: true, color: Palette.red,
              transactions: [
                .init(merchant: "Rent", amount: "$200", amountValue: 200),
                .init(merchant: "Electricity", amount: "$25", amountValue: 25)
              ]),
        .init(categoryId: "shopping", categoryName: "Shopping", icon: "🛍️", amount: "$12.40",
              amountValue: 12.4, ringProgress: nil, dot: false, color: Color(hex: 0xA468E0),
              transactions: [
                .init(merchant: "Target", amount: "$12.40", amountValue: 12.4)
              ]),
        .init(categoryId: "utilities", categoryName: "Utilities", icon: "🔌", amount: "$7.65",
              amountValue: 7.65, ringProgress: 0.78, dot: false, color: Color(hex: 0x2BB5A8),
              transactions: [
                .init(merchant: "Water Bill", amount: "$7.65", amountValue: 7.65)
              ]),
        .init(categoryId: "travel", categoryName: "Travel", icon: "🏖️", amount: "$362",
              amountValue: 362, ringProgress: nil, dot: false, color: Color(hex: 0x4C8DF5),
              transactions: [
                .init(merchant: "Airbnb", amount: "$200", amountValue: 200),
                .init(merchant: "Flight", amount: "$162", amountValue: 162)
              ]),
        .init(categoryId: "food", categoryName: "Food", icon: "🍨", amount: "$203",
              amountValue: 203, ringProgress: nil, dot: false, color: Palette.green,
              transactions: [
                .init(merchant: "Whole Foods", amount: "$89.50", amountValue: 89.5),
                .init(merchant: "Chipotle", amount: "$52.30", amountValue: 52.3),
                .init(merchant: "Coffee Shop", amount: "$12.20", amountValue: 12.2),
                .init(merchant: "Grocery Store", amount: "$49", amountValue: 49)
              ])
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("CATEGORY BUDGETS")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Button(action: onShowCategories) {
                    HStack(spacing: 2) {
                        Text("categories").font(.system(size: 13))
                        Text("›").font(.system(size: 14))
                    }
                    .foregroundStyle(Palette.blue)
                }
            }
            HStack(spacing: 6) {
                ForEach(items) { item in
                    BudgetIconCell(item: item)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategory = item }
                }
            }
        }
        .sheet(item: $selectedCategory) { category in
            BudgetDetailSheet(item: category)
        }
    }
}

private struct BudgetIconCell: View {
    let item: BudgetIconItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

                if let progress = item.ringProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Palette.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }

                Text(item.icon).font(.system(size: 27))
            }
            .frame(width: 58, height: 58)
            .overlay(alignment: .topLeading) {
                if item.dot {
                    Circle().fill(Palette.green).frame(width: 9, height: 9).offset(x: 3, y: 1)
                }
            }

            Text(item.amount)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)

            Text("left")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

private struct BudgetDetailSheet: View {
    let item: BudgetIconItem
    @Environment(\.dismiss) private var dismiss
    @State private var editingTxn: EditingID?

    // Sort transactions largest to smallest.
    private var sortedTransactions: [BudgetTransactionRow] {
        item.transactions.sorted { $0.amountValue > $1.amountValue }
    }

    // Percentage of budget used (simplified; in reality comes from the view-model).
    private var percentageUsed: Int {
        Int((item.amountValue / 500) * 100)   // assume $500 budget for demo
    }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                iconHeader
                    .padding(.vertical, 24)

                Divider()
                    .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(sortedTransactions) { txn in
                            TransactionListRow(
                                transaction: txn,
                                categoryColor: item.color,
                                onEdit: { editingTxn = EditingID(id: txn.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }

            // Close button (top-right).
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    }
                }
                Spacer()
            }
        }
        // Recategorize — bottom sheet (dim fades, options slide up).
        .sheet(item: $editingTxn) { _ in
            CategoryPickerSheet { _ in }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var iconHeader: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    Text(item.icon).font(.system(size: 32))
                }
                .frame(width: 72, height: 72)

                Text("\(percentageUsed)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.blue)

                Text(item.categoryName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("Spent:")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                        Text(item.amount)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    HStack(spacing: 2) {
                        Text("Budget:")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                        Text("$500")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
    }
}

private struct TransactionListRow: View {
    let transaction: BudgetTransactionRow
    let categoryColor: Color
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(categoryColor).frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }

            Spacer(minLength: 8)

            Text(transaction.amount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Button(action: onEdit) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Identifiable wrapper so a `UUID` selection can drive `.sheet(item:)`.
private struct EditingID: Identifiable { let id: UUID }

/// Category picker presented as a bottom sheet — the dim fades in and the options slide
/// up from below (native sheet). Tap a category to choose; the scrollable list ends with
/// an "Add a category" affordance to create a new one.
private struct CategoryPickerSheet: View {
    var onSelect: (CategoryOption) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [CategoryOption] = CategoryCatalog.all
    @State private var addingNew = false
    @State private var newName = ""
    @FocusState private var newNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Change Category")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(categories) { cat in
                        Button(action: { onSelect(cat); dismiss() }) {
                            HStack(spacing: 12) {
                                Text(cat.icon).font(.system(size: 20))
                                Text(cat.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(cat.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    addCategoryRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
    }

    /// "Add a category" pinned at the bottom of the list — reveals a name field, then
    /// creates a new category (session-only in the prototype).
    @ViewBuilder private var addCategoryRow: some View {
        if addingNew {
            HStack(spacing: 8) {
                TextField("New category", text: $newName)
                    .font(.system(size: 15, weight: .medium))
                    .focused($newNameFocused)
                    .submitLabel(.done)
                    .onSubmit(create)
                Button(action: create) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.blue)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button(action: { addingNew = true; newNameFocused = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18))
                    Text("Add a category").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Palette.blue)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Palette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let new = CategoryOption(name: trimmed.uppercased(), icon: "🏷️", color: Palette.blue)
        CategoryCatalog.addCustom(new)
        categories = CategoryCatalog.all
        onSelect(new)
        dismiss()
    }
}

/// Modal budget editor with preset options and custom input.
private struct BudgetEditModal: View {
    let currentBudget: Double
    @Binding var selectedBudget: Double?
    var onConfirm: () -> Void
    @State private var customAmount: String = ""

    private var budgetOptions: [(label: String, amount: Double)] {
        [
            ("Keep Current", currentBudget),
            ("Increase by 10%", currentBudget * 1.1),
            ("Increase by 25%", currentBudget * 1.25),
            ("Increase by 50%", currentBudget * 1.5),
            ("Double Budget", currentBudget * 2)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Adjust Budget")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                Text("Current: $\(Int(currentBudget))")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)

                VStack(spacing: 10) {
                    ForEach(budgetOptions.indices, id: \.self) { idx in
                        let option = budgetOptions[idx]
                        Button(action: {
                            selectedBudget = option.amount
                            onConfirm()
                        }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text("$\(Int(option.amount))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.blue)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Palette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Divider()
                        .padding(.vertical, 6)

                    HStack(spacing: 10) {
                        TextField("Custom amount", text: $customAmount)
                            .font(.system(size: 15))
                            .keyboardType(.decimalPad)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))

                        Button(action: {
                            if let amount = Double(customAmount), amount > 0 {
                                selectedBudget = amount
                                onConfirm()
                            }
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Palette.blue)
                                .frame(height: 48)
                        }
                    }
                }
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Upcoming

private struct UpcomingItem: Identifiable {
    let id = UUID()
    let timing: String
    let icon: String
    let merchant: String
    let amount: String
}

private struct UpcomingSection: View {
    private let items: [UpcomingItem] = [
        .init(timing: "tomorrow", icon: "🤷‍♂️", merchant: "Apple", amount: "$0.99"),
        .init(timing: "in 21 days", icon: "🔌", merchant: "Simplebills Energy", amount: "$19.10"),
        .init(timing: "May 24", icon: "🎬", merchant: "Netflix", amount: "$15.49"),
        .init(timing: "May 28", icon: "🎵", merchant: "Spotify", amount: "$9.99")
    ]

    var body: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "UPCOMING", action: "recurrings")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { UpcomingCard(item: $0) }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

private struct UpcomingCard: View {
    let item: UpcomingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.timing)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(item.icon).font(.system(size: 19))

                // Grows to fit the name up to a cap, then truncates.
                Text(item.merchant)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)

                // The price always shows in full.
                Text(item.amount)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 110, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Income

private struct IncomeSection: View {
    // Prototype values (match the BudgetOverviewCard pattern). When the data layer
    // connects, feed these from the dashboard contract: income/expense totals for the
    // month, and whether spending pace is ahead of the user's usual rate.
    var income: Double = 4250
    var expenses: Double = 1612
    var incomeLabel = "$4,250"
    var expensesLabel = "$1,612"
    /// true = spending faster than usual (caution), false = slower/on track (kudos).
    var spendingFasterThanUsual = false

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "INCOME", action: "net change")
            IncomeExpenseBars(income: income, expenses: expenses,
                              incomeLabel: incomeLabel, expensesLabel: expensesLabel)
            PaceInsight(faster: spendingFasterThanUsual)
        }
    }
}

/// Minimal two-bar comparison on a clear background: income (green) vs expenses (red).
private struct IncomeExpenseBars: View {
    let income: Double
    let expenses: Double
    let incomeLabel: String
    let expensesLabel: String

    private let chartHeight: CGFloat = 120
    private let barWidth: CGFloat = 56

    var body: some View {
        let maxValue = max(income, expenses, 1)
        HStack(spacing: 44) {
            column(value: income, valueLabel: incomeLabel, caption: "Income",
                   color: Palette.green, maxValue: maxValue)
            column(value: expenses, valueLabel: expensesLabel, caption: "Expenses",
                   color: Palette.red, maxValue: maxValue)
        }
        .frame(maxWidth: .infinity)
    }

    private func column(value: Double, valueLabel: String, caption: String,
                        color: Color, maxValue: Double) -> some View {
        let barHeight = chartHeight * CGFloat(value / maxValue)
        return VStack(spacing: 8) {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(valueLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: barWidth, height: max(barHeight, 4))
            }
            .frame(height: chartHeight + 24)   // headroom so the value label never clips

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// One-line spending-pace read-out beneath the bars.
private struct PaceInsight: View {
    let faster: Bool

    private var color: Color { faster ? Palette.red : Palette.green }
    private var icon: String { faster ? "arrow.up.right" : "checkmark.seal.fill" }
    private var message: String {
        faster
            ? "You're spending at a faster rate than usual."
            : "You're spending slower than usual. Kudos!"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared

private struct SectionHeader: View {
    let title: String
    let action: String
    var onAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if let onAction = onAction {
                Button(action: onAction) {
                    HStack(spacing: 2) {
                        Text(action).font(.system(size: 13))
                        Text("›").font(.system(size: 14))
                    }
                    .foregroundStyle(Palette.blue)
                }
            } else {
                HStack(spacing: 2) {
                    Text(action).font(.system(size: 13))
                    Text("›").font(.system(size: 14))
                }
                .foregroundStyle(Palette.blue)
            }
        }
    }
}

private enum Palette {
    static let blue = Color(hex: 0x1565C0)
    static let green = Color(hex: 0x34C759)
    static let red = Color(hex: 0xFF3B30)
    static let amber = Color(hex: 0xFF9500)
    static let background = Color(hex: 0xF2F2F7)
    static let textPrimary = Color(hex: 0x1A1A2E)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let divider = Color(hex: 0xE5E5EA)
}

// MARK: - Transactions Page

private struct TransactionRow: Identifiable {
    let id = UUID()
    let merchant: String
    var category: CategoryOption?   // optional pill (editable — tap to recategorize)
    let amount: String
    let isIncome: Bool              // income amounts render green
    var date: Date = Date()         // the charge's day (stamped from its TransactionDay)
    /// A big-store charge (Target/Walmart/Amazon…) that likely bundles categories —
    /// gets a selectable circle so it can be batch-scanned for a receipt breakdown.
    var isAmbiguous: Bool = false
}

private struct TransactionDay: Identifiable {
    let id = UUID()
    let date: Date                 // the transaction group's actual date (from the data)
    var rows: [TransactionRow]

    var label: String {
        if Calendar.current.isDateInToday(date) { return "TODAY" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date).uppercased()
    }
}

/// The search bar is locked in `ContentView` (overlaps the blue) so it doesn't scroll.
private struct TransactionSearchBar: View {
    @State private var search = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
            TextField("Search for transaction", text: $search).font(.system(size: 16))
            Image(systemName: "slider.horizontal.3").foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 7, x: 0, y: 3)
    }
}

private struct TransactionsPageView: View {
    @ObservedObject var scanModel: TransactionScanModel
    @State private var showAdd = false
    @State private var days: [TransactionDay] = TransactionsPageView.makeDays()
    @State private var editing: EditTarget?            // which row's category is being changed
    @State private var showGroupScan = false
    /// Charges that have been split into line items (id → items). A split charge no longer
    /// shows the selection circle — it's resolved, so it renders as its line items instead.
    @State private var splits: [UUID: [ReceiptLineItem]] = [:]

    /// Locates a transaction row by day + row index for recategorization.
    struct EditTarget: Identifiable {
        let dayIndex: Int
        let rowIndex: Int
        var id: String { "\(dayIndex)-\(rowIndex)" }
    }

    private var selectedTransactions: [TransactionRow] {
        // Stamp each row with its day's date (kept as a value copy — the id is preserved).
        days.flatMap { day in day.rows.map { row -> TransactionRow in var r = row; r.date = day.date; return r } }
            .filter { scanModel.selected.contains($0.id) }
    }

    private func toggleSelect(_ id: UUID) {
        if scanModel.selected.contains(id) { scanModel.selected.remove(id) }
        else { scanModel.selected.insert(id) }
    }

    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: Date())
    }

    // Each group carries its real date — the list just shows newest first, so the top
    // header is whatever the most recent transaction's date is (today only if one posted
    // today). The data layer supplies real dates; the prototype anchors the newest sample
    // to today and steps back from there.
    private static func makeDays() -> [TransactionDay] {
        let cal = Calendar.current
        let latest = Date()   // stands in for the most recent transaction's date
        func daysBefore(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: latest) ?? latest }
        let shopping = CategoryCatalog.option(for: "SHOPPING")
        let restaurants = CategoryCatalog.option(for: "RESTAURANTS")
        return [
            TransactionDay(date: daysBefore(0), rows: [
                .init(merchant: "Target", category: shopping, amount: "$87.34", isIncome: false, isAmbiguous: true),
                .init(merchant: "Sp Vitaly Design Ltd", category: shopping, amount: "$94.28", isIncome: false)
            ]),
            TransactionDay(date: daysBefore(1), rows: [
                .init(merchant: "Gusto", category: nil, amount: "$100.00", isIncome: true)
            ]),
            TransactionDay(date: daysBefore(3), rows: [
                .init(merchant: "Amazon", category: shopping, amount: "$120.50", isIncome: false, isAmbiguous: true),
                .init(merchant: "Chick-fil-a", category: restaurants, amount: "$21.52", isIncome: false),
                .init(merchant: "Withdrawal to 360…", category: nil, amount: "$120.00", isIncome: false)
            ]),
            TransactionDay(date: daysBefore(4), rows: [
                .init(merchant: "Walmart", category: shopping, amount: "$63.20", isIncome: false, isAmbiguous: true),
                .init(merchant: "Venmo", category: shopping, amount: "$10.00", isIncome: false)
            ])
        ]
    }

    var body: some View {
        // The "add" button now lives in the locked zone (ContentView); the page scrolls the
        // month summary and the list beneath it.
        VStack(spacing: 16) {
            monthSummary
            transactionsList
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        // Recategorize a transaction — bottom sheet (dim fades, options slide up).
        .sheet(item: $editing) { target in
            CategoryPickerSheet { sel in
                days[target.dayIndex].rows[target.rowIndex].category = sel
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Locked "ADD A NEW TRANSACTION" with nothing selected → add a single transaction.
        .onChange(of: scanModel.requestAdd) { _, want in
            if want { showAdd = true; scanModel.requestAdd = false }
        }
        // Locked launcher with charges selected → the batch classify + scan flow.
        .onChange(of: scanModel.launch) { _, launch in
            if launch { showGroupScan = true; scanModel.launch = false }
        }
        .fullScreenCover(isPresented: $showGroupScan) {
            BatchClassifySheet(transactions: selectedTransactions) { resolved in
                withAnimation(.easeInOut(duration: 0.25)) {
                    splits.merge(resolved) { _, new in new }
                }
                scanModel.selected.removeAll()
            }
        }
    }

    private var monthSummary: some View {
        VStack(spacing: 14) {
            Text(monthName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.textPrimary)

            HStack(alignment: .top) {
                summaryColumn(value: "$2,064", label: "TOTAL INCOME", color: Palette.green)
                Spacer()
                summaryColumn(value: "$702", label: "TOTAL SPENT", color: Palette.textPrimary)
                Spacer()
                summaryColumn(value: "$3.44", label: "OVER BUDGET", color: Color(hex: 0xE8833A))
            }

            Divider()

            Button(action: {}) {
                Text("OPEN YOUR MONTH IN REVIEW")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.blue)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func summaryColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        }
    }

    private var transactionsList: some View {
        VStack(spacing: 18) {
            ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    ForEach(Array(day.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        if let items = splits[row.id] {
                            // Resolved charge: show its line items (vendor — item, category,
                            // price). No selection circle — it's already been split.
                            ForEach(items) { item in
                                TransactionListItem(
                                    row: TransactionRow(
                                        merchant: "\(row.merchant) — \(item.name)",
                                        category: item.category,
                                        amount: item.amount,
                                        isIncome: false,
                                        date: row.date
                                    )
                                )
                            }
                        } else {
                            TransactionListItem(
                                row: row,
                                isSelected: scanModel.selected.contains(row.id),
                                onToggleSelect: row.isAmbiguous ? { toggleSelect(row.id) } : nil,
                                onEditCategory: row.category == nil ? nil : {
                                    editing = EditTarget(dayIndex: dayIndex, rowIndex: rowIndex)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct TransactionListItem: View {
    let row: TransactionRow
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)?
    var onEditCategory: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            leadingBullet
            Text(row.merchant)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let cat = row.category {
                if let onEditCategory {
                    Button(action: onEditCategory) {
                        CategoryPill(name: cat.name, icon: cat.icon, color: cat.color)
                    }
                    .buttonStyle(.plain)
                } else {
                    CategoryPill(name: cat.name, icon: cat.icon, color: cat.color)
                }
            }

            Text(row.amount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.isIncome ? Palette.green : Palette.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }

    /// Ambiguous big-store rows get a selectable circle (to batch-scan receipts); every
    /// other row gets a small square bullet in its category color.
    @ViewBuilder private var leadingBullet: some View {
        if row.isAmbiguous {
            Button(action: { onToggleSelect?() }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Palette.blue : Palette.textSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(row.category?.color ?? Palette.textSecondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }
}

/// Batch input chooser for the selected ambiguous charges. A three-column board: the
/// charge under review sits in a centered deck (the rest stacked behind it), with the two
/// input methods as tall side pillars. Swipe the card LEFT to file it under "Receipt image"
/// (camera) or RIGHT under "Upload screenshot"; classified charges stack into the matching
/// pillar. Once every charge has a method, the screenshots are bulk-uploaded and matched to
/// each charge by the total on the online receipt.
private struct BatchClassifySheet: View {
    let transactions: [TransactionRow]
    /// Hands back the line-item split for each charge (keyed by transaction id) so the list
    /// can replace the ambiguous row with its resolved items.
    var onDone: ([UUID: [ReceiptLineItem]]) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Phase { case classify, analyzing, results }
    enum Method { case image, screenshot }

    @State private var queue: [TransactionRow]
    @State private var imageList: [TransactionRow] = []
    @State private var screenshotList: [TransactionRow] = []
    @State private var drag: CGSize = .zero
    @State private var phase: Phase = .classify
    @State private var screenshots: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var dropTarget: Method?          // column highlighted under a drag
    @State private var capturing = false            // camera flow over the image-classified charges
    @State private var captureIndex = 0
    @State private var splitting = false            // split-review flow over the screenshot charges
    @State private var splitIndex = 0
    @State private var results: [UUID: [ReceiptLineItem]] = [:]   // charge id → its split

    init(transactions: [TransactionRow], onDone: @escaping ([UUID: [ReceiptLineItem]]) -> Void) {
        self.transactions = transactions
        self.onDone = onDone
        _queue = State(initialValue: transactions)
    }

    private let threshold: CGFloat = 90

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()
            switch phase {
            case .classify:  classifyView
            case .analyzing: analyzingView
            case .results:   resultsView
            }
            topBar
        }
        .photosPicker(isPresented: $showPicker, selection: $screenshots,
                      maxSelectionCount: max(1, screenshotList.count), matching: .screenshots)
        .onChange(of: screenshots) { _, items in
            if !items.isEmpty { afterScreenshots() }
        }
        // Camera capture → split into line items, one Receipt-image charge at a time.
        .fullScreenCover(isPresented: $capturing) {
            if captureIndex < imageList.count {
                let t = imageList[captureIndex]
                ReceiptCaptureSheet(merchant: t.merchant, total: t.amount, date: t.date,
                                    source: .camera, showCameraFirst: true,
                                    continues: true) { items in
                    results[t.id] = items
                    advanceCapture()
                }
                .id(captureIndex)   // fresh state per charge
            }
        }
        // Screenshot charges → read & split into line items, one at a time, after matching.
        .fullScreenCover(isPresented: $splitting) {
            if splitIndex < screenshotList.count {
                let t = screenshotList[splitIndex]
                ReceiptCaptureSheet(merchant: t.merchant, total: t.amount, date: t.date,
                                    source: .screenshot, continues: true) { items in
                    results[t.id] = items
                    advanceSplit()
                }
                .id(splitIndex)
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Text(topTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var topTitle: String {
        switch phase {
        case .classify:  return "Add receipts"
        case .analyzing: return "Matching"
        case .results:   return "Matched"
        }
    }

    // MARK: Classify (3-column board)

    private var classifyView: some View {
        VStack(spacing: 12) {
            // Two destination columns on top; drag a row across to fix a misclassification.
            HStack(alignment: .top, spacing: 12) {
                column(.image)
                column(.screenshot)
            }
            .frame(maxHeight: .infinity)

            bottomArea
        }
        .padding(.top, 64)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    // MARK: Destination columns

    private func column(_ method: Method) -> some View {
        let list = method == .image ? imageList : screenshotList
        return VStack(spacing: 10) {
            selectAllHeader(method)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(list) { row in classifiedRow(row, in: method) }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if list.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(dropTarget == method ? Palette.blue.opacity(0.12) : Color.black.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Palette.blue, lineWidth: dropTarget == method ? 2 : 0)
        )
        .dropDestination(for: String.self) { ids, _ in
            moveItems(ids, to: method); return true
        } isTargeted: { over in
            dropTarget = over ? method : (dropTarget == method ? nil : dropTarget)
        }
    }

    /// Dotted-blue "select all" header — same family as ADD A NEW TRANSACTION, each with its
    /// own white-on-blue glyph.
    private func selectAllHeader(_ method: Method) -> some View {
        let isImage = method == .image
        return Button(action: { assignAll(method) }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Palette.blue).frame(width: 26, height: 26)
                    Image(systemName: isImage ? "camera.fill" : "square.and.arrow.up.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("SELECT ALL")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Palette.blue.opacity(0.7))
                    Text(isImage ? "RECEIPT IMAGE" : "SCREENSHOT UPLOAD")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Palette.blue)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Palette.blue.opacity(queue.isEmpty ? 0.25 : 0.6),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .disabled(queue.isEmpty)
    }

    /// A classified charge as a neat horizontal row. Drag it to the other column, or tap the
    /// swap button to flip its side — whichever is easier.
    private func classifiedRow(_ row: TransactionRow, in method: Method) -> some View {
        let tint = row.category?.color ?? Palette.blue
        let other: Method = method == .image ? .screenshot : .image
        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 30, height: 30)
                Text(row.category?.icon ?? "🧾").font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.merchant)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(row.amount)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Button { moveItems([row.id.uuidString], to: other) } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                    .frame(width: 28, height: 28)
                    .background(Palette.blue.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .draggable(row.id.uuidString) {
            HStack(spacing: 6) {
                Text(row.category?.icon ?? "🧾")
                Text(row.merchant).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white, in: Capsule())
            .shadow(radius: 6)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Bottom deck (swipe to classify)

    @ViewBuilder private var bottomArea: some View {
        if queue.isEmpty {
            VStack(spacing: 10) {
                Button(action: launch) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.on.clipboard")
                        Text("Upload & match receipts")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Palette.blue, in: Capsule())
                }
                multiPageTip
            }
        } else {
            VStack(spacing: 8) {
                deck.frame(height: 188)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text("Receipt image").fontWeight(.semibold)
                    Text("·").foregroundStyle(Palette.divider)
                    Text("Upload screenshot").fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // Centered deck at the bottom: remaining charges stacked back-to-front, top one swipeable.
    private var deck: some View {
        ZStack {
            ForEach(Array(queue.prefix(3).enumerated()).reversed(), id: \.element.id) { idx, row in
                chargeCard(row, depth: idx)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chargeCard(_ row: TransactionRow, depth: Int) -> some View {
        let isTop = depth == 0
        let scale = 1 - CGFloat(depth) * 0.05
        let backOffset = -CGFloat(depth) * 12   // recede up & back, staying centered
        let tint = row.category?.color ?? Palette.blue
        let leaning: Method? = abs(drag.width) > 20 ? (drag.width < 0 ? .image : .screenshot) : nil

        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 48, height: 48)
                Text(row.category?.icon ?? "🧾").font(.system(size: 24))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.merchant)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(row.amount)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(Self.fullDate(row.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .top) {
            if isTop, let leaning {
                Text(leaning == .image ? "RECEIPT IMAGE" : "UPLOAD SCREENSHOT")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Palette.blue, in: Capsule())
                    .offset(y: -14)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        .scaleEffect(scale)
        .offset(x: isTop ? drag.width : 0, y: backOffset + (isTop ? drag.height * 0.1 : 0))
        .rotationEffect(.degrees(isTop ? Double(drag.width / 22) : 0))
        .opacity(depth >= 2 ? 0.55 : 1)
        .gesture(isTop ? swipe : nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: queue.count)
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.translation.width < -threshold { assign(.image) }
                else if value.translation.width > threshold { assign(.screenshot) }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero } }
            }
    }

    private var multiPageTip: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0xE8833A))
            Text("Long receipt? Screenshot the order-summary page so the items and total sit on one image.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }

    // MARK: Analyzing / results

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4).tint(Palette.blue)
            Text("Matching receipts by price…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Reading \(screenshotList.count) screenshot\(screenshotList.count == 1 ? "" : "s") and pairing each to a charge by its total.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(imageList + screenshotList) { row in resultRow(row) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 70)
            }
            Button(action: { onDone(results); dismiss() }) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Palette.blue, in: Capsule())
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    private func resultRow(_ row: TransactionRow) -> some View {
        let isImage = imageList.contains { $0.id == row.id }
        return HStack(spacing: 12) {
            Text(row.category?.icon ?? "🧾").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.merchant).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Label(isImage ? "Receipt image · split" : "Screenshot · split",
                      systemImage: isImage ? "camera.fill" : "photo.on.rectangle")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Text(row.amount).font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.green)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Actions

    private func assign(_ method: Method) {
        guard let top = queue.first else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: method == .image ? -700 : 700, height: drag.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                if method == .image { imageList.append(top) } else { screenshotList.append(top) }
                queue.removeFirst()
                drag = .zero
            }
        }
    }

    private func assignAll(_ method: Method) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if method == .image { imageList.append(contentsOf: queue) }
            else { screenshotList.append(contentsOf: queue) }
            queue.removeAll()
            drag = .zero
        }
    }

    /// Move dragged rows into a column (fixing a misclassification). Pulls each from
    /// whichever list currently holds it, then appends to the target.
    private func moveItems(_ ids: [String], to method: Method) {
        let uuids = ids.compactMap { UUID(uuidString: $0) }
        var changed = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            for uid in uuids {
                var moved: TransactionRow?
                if let i = imageList.firstIndex(where: { $0.id == uid }) { moved = imageList.remove(at: i) }
                else if let i = screenshotList.firstIndex(where: { $0.id == uid }) { moved = screenshotList.remove(at: i) }
                guard let row = moved else { continue }
                if method == .image { imageList.append(row) } else { screenshotList.append(row) }
                changed = true
            }
        }
        if changed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    static func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"   // e.g. "Wednesday, June 24, 2026"
        return f.string(from: date)
    }

    /// Kick off the capture pipeline. Receipt-image charges get the camera (→ split into
    /// line items) first; then the screenshot charges are bulk-uploaded, matched by price,
    /// and split. The flow is only "done" once every receipt is split.
    private func launch() {
        captureIndex = 0
        if !imageList.isEmpty { capturing = true }   // camera each image charge
        else { startScreenshots() }
    }

    private func advanceCapture() {
        if captureIndex + 1 < imageList.count {
            captureIndex += 1                        // next image charge (cover stays up)
        } else {
            capturing = false
            startScreenshots()
        }
    }

    private func startScreenshots() {
        if screenshotList.isEmpty { finish() }       // nothing to upload — all done
        else { showPicker = true }                   // bulk-upload the screenshots
    }

    /// After the bulk screenshots come back: show the matching pass, then split each one.
    private func afterScreenshots() {
        withAnimation { phase = .analyzing }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            startSplitting()
        }
    }

    private func startSplitting() {
        splitIndex = 0
        splitting = true                             // ReceiptCaptureSheet reads & splits each
    }

    private func advanceSplit() {
        if splitIndex + 1 < screenshotList.count {
            splitIndex += 1
        } else {
            splitting = false
            finish()
        }
    }

    /// Every receipt has been captured/uploaded and split. Hand the results back and
    /// return to the Transactions page (let the last capture cover finish closing first).
    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDone(results)
            dismiss()
        }
    }
}

/// "Add a new transaction" popup: a gray container holding two blue square options —
/// scan a receipt (camera) or upload a screenshot (photos). Each opens the capture flow.
private struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var capture: CaptureKind?

    private enum CaptureKind: Int, Identifiable { case camera, screenshot; var id: Int { rawValue } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Add a transaction")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Scan a receipt or upload a screenshot to capture and split it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 28) {
                    Button(action: { capture = .camera }) {
                        optionTile(icon: "camera.fill", label: "Receipt image")
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        optionTile(icon: "photo.on.rectangle", label: "Upload screenshot")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 20)
            .padding(.top, 38)   // breathing room from the drag indicator
        }
        .onChange(of: photoItem) { _, item in if item != nil { capture = .screenshot } }
        .fullScreenCover(item: $capture) { kind in
            ReceiptCaptureSheet(
                merchant: "your purchase",
                total: "",
                source: kind == .camera ? .camera : .screenshot,
                showCameraFirst: kind == .camera
            ) { _ in dismiss() }
        }
    }

    private func optionTile(icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.blue)
                .frame(width: 76, height: 76)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                )
                .shadow(color: Palette.blue.opacity(0.3), radius: 6, x: 0, y: 3)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

// MARK: - Donut Chart

private struct DonutChartView: View {
    let categories: [CategoryListItem]

    private var totalSpent: Double {
        categories.reduce(0) { $0 + $1.spent }
    }

    var body: some View {
        ZStack {
            // Background circle (unfilled)
            Circle()
                .stroke(Palette.background, lineWidth: 14)

            // Segments
            ForEach(Array(segmentsWithAngles.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: segment.startFraction, to: segment.endFraction)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 140, height: 140)
    }

    private var segmentsWithAngles: [(startFraction: Double, endFraction: Double, color: Color)] {
        var segments: [(startFraction: Double, endFraction: Double, color: Color)] = []
        var currentFraction = 0.0

        for cat in categories where cat.spent > 0 {
            let segmentFraction = cat.spent / totalSpent
            segments.append((
                startFraction: currentFraction,
                endFraction: currentFraction + segmentFraction,
                color: cat.color
            ))
            currentFraction += segmentFraction
        }

        return segments
    }
}

// MARK: - Categories Page (integrated view)

private struct CategoriesPageView: View {
    @State private var selectedCategory: CategoryListItem?
    @State private var selectedMonth = "June 2026"

    private let categories: [CategoryListItem] = [
        .init(id: "housing", name: "Housing", icon: "🏠", spent: 225, budget: 500, color: Palette.red),
        .init(id: "food", name: "Food", icon: "🍎", spent: 589, budget: 700, color: Palette.green),
        .init(id: "shopping", name: "Shopping", icon: "🛍️", spent: 422, budget: 500, color: Color(hex: 0xA468E0)),
        .init(id: "entertainment", name: "Entertainment", icon: "🎬", spent: 284, budget: 200, color: Palette.red),
        .init(id: "transport", name: "Transportation", icon: "🚗", spent: 254, budget: 300, color: Color(hex: 0x4C8DF5)),
        .init(id: "health", name: "Health", icon: "💊", spent: 140, budget: 100, color: Color(hex: 0x2BB5A8)),
        .init(id: "self-care", name: "Self Care", icon: "💆", spent: 129, budget: 160, color: Color(hex: 0xF5A623)),
        .init(id: "subscriptions", name: "Subscriptions", icon: "🔔", spent: 70, budget: 70, color: Color(hex: 0xFF6B6B)),
        .init(id: "donations", name: "Donations", icon: "🤝", spent: 60, budget: 160, color: Color(hex: 0x95E1D3)),
        .init(id: "travel", name: "Travel", icon: "✈️", spent: 0, budget: 500, color: Color(hex: 0x4C8DF5)),
        .init(id: "gifts", name: "Gifts", icon: "🎁", spent: 0, budget: 100, color: Color(hex: 0xFF69B4)),
        .init(id: "other", name: "Other", icon: "📦", spent: 0, budget: 100, color: Color(hex: 0x9B9B9B))
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Pie chart + summary (like reference)
            pieChartSection

            // Analytics
            analyticsSection

            // Category list
            VStack(spacing: 12) {
                ForEach(categories) { cat in
                    CategoryListRow(category: cat)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategory = cat }
                }
            }
        }
        .sheet(item: $selectedCategory) { category in
            CategoryDetailSheet(category: category)
        }
    }

    private var pieChartSection: some View {
        VStack(spacing: 0) {
            // Card overlapping the blue header (like dashboard budget card)
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$4,372")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("spent in Jun")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Spacer()

                    // Donut chart showing category breakdown
                    DonutChartView(categories: categories)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$5,115")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("total budget")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                // Analytics below the chart
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.green)
                        Text("12% less than last month")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.green)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.blue)
                        Text("5% below your average")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.blue)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var analyticsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.green)
                Text("12% less than last month")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.green)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.blue)
                Text("5% below your average")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.blue)
                Spacer()
            }
        }
        .padding(12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CategoryListItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let spent: Double
    let budget: Double
    let color: Color
}

private struct CategoryListRow: View {
    let category: CategoryListItem

    private var budgetStatus: BudgetStatus {
        BudgetStatus.classify(spent: category.spent, limit: category.budget)
    }

    private var statusColor: Color {
        switch budgetStatus {
        case .ok: return Palette.green
        case .warning: return Color(hex: 0xFFA500)
        case .over: return Palette.red
        case .none: return Palette.blue
        }
    }

    private var fractionUsed: Double {
        category.budget > 0 ? category.spent / category.budget : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category icon in a circle.
            ZStack {
                Circle().fill(category.color.opacity(0.12))
                Text(category.icon).font(.system(size: 18))
            }
            .frame(width: 44, height: 44)

            // Category name and spent.
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                // Budget progress bar.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.background)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(statusColor)
                            .frame(width: geo.size.width * min(fractionUsed, 1))
                    }
                }
                .frame(height: 6)
            }

            // Amounts (spent / budget).
            VStack(alignment: .trailing, spacing: 4) {
                Text("$\(Int(category.spent))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                Text("$\(Int(category.budget))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Detail sheet for a selected category, showing all transactions with month navigation.
private struct CategoryDetailSheet: View {
    let category: CategoryListItem
    @Environment(\.dismiss) private var dismiss
    @State private var editingTxn: EditingID?
    @State private var editingBudget = false
    @State private var newBudget: Double?
    @State private var currentMonthIndex = 0  // 0 = current month, -1 = previous, etc.

    private let months = ["June 2026", "May 2026", "April 2026", "March 2026"]

    // Mock transactions for the category (in reality, from the view-model).
    private var mockTransactions: [BudgetTransactionRow] {
        // Simulated data; in reality, pulled from presenter.
        [
            .init(merchant: "Whole Foods", amount: "$150.00", amountValue: 150),
            .init(merchant: "Trader Joe's", amount: "$89.50", amountValue: 89.5),
            .init(merchant: "Chipotle", amount: "$52.30", amountValue: 52.3),
            .init(merchant: "Starbucks", amount: "$32.20", amountValue: 32.2),
            .init(merchant: "Farmer's Market", amount: "$28.50", amountValue: 28.5),
            .init(merchant: "Panera", amount: "$15.60", amountValue: 15.6)
        ].sorted { $0.amountValue > $1.amountValue }
    }

    private var percentageUsed: Int {
        Int((category.spent / category.budget) * 100)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                iconHeader
                    .padding(.vertical, 24)

                Divider()
                    .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(mockTransactions) { txn in
                            TransactionListRow(
                                transaction: txn,
                                categoryColor: category.color,
                                onEdit: { editingTxn = EditingID(id: txn.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }

            // Close button (top-right).
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    }
                }
                Spacer()
            }

            // Budget editor overlay (blur + modal).
            if editingBudget {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { editingBudget = false }

                BudgetEditModal(
                    currentBudget: category.budget,
                    selectedBudget: $newBudget,
                    onConfirm: {
                        // In real app, save the new budget here.
                        editingBudget = false
                    }
                )
            }
        }
        // Recategorize — bottom sheet (dim fades, options slide up).
        .sheet(item: $editingTxn) { _ in
            CategoryPickerSheet { _ in }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var iconHeader: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack(spacing: 12) {
                Button(action: {
                    if currentMonthIndex > 0 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentMonthIndex -= 1
                        }
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(currentMonthIndex > 0 ? Palette.blue : Palette.textSecondary)
                }

                Text(months[currentMonthIndex])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minWidth: 100)

                Button(action: {
                    if currentMonthIndex < months.count - 1 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentMonthIndex += 1
                        }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(currentMonthIndex < months.count - 1 ? Palette.blue : Palette.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)

            // Centered icon + info (stacked vertically)
            VStack(spacing: 12) {
                ZStack {
                    // Progress ring
                    Circle()
                        .stroke(Palette.background, lineWidth: 3)

                    Circle()
                        .trim(from: 0, to: CGFloat(percentageUsed) / 100)
                        .stroke(category.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    // Icon circle
                    ZStack {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        Text(category.icon).font(.system(size: 28))
                    }
                    .frame(width: 60, height: 60)
                }
                .frame(width: 80, height: 80)

                Text("\(percentageUsed)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.blue)

                Text(category.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("Spent:")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                        Text("$\(Int(category.spent))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    HStack(spacing: 2) {
                        Text("Budget:")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                        Button(action: { editingBudget = true }) {
                            Text("$\(Int(category.budget))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.blue)
                                .underline()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)

            // Analytics for this month vs last month
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.green)
                    Text("8% less than last month")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.green)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "equal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                    Text("on par with your average")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.blue)
                    Spacer()
                }
            }
            .padding(10)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    ContentView()
}
