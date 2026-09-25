# Plan 7: Shell and Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app Direction A's look (theme, fonts, debt colours), a three-tab shell (Home · Debts · Plans), a shared chart kit, and chart-first versions of Home, Debts, Plans, Plan detail and Scenarios Compare. Home shows the cheapest plan; there's no progress tracking yet.

**Architecture:** The theme tokens live in `lib/app/theme.dart` as a `ThemeExtension` (`DestroyerColors`). Pure view-data functions live in `lib/features/analysis/domain/plan_series.dart` (unit-tested). Five `fl_chart`-based widgets live in `lib/core/charts/`, and they only draw what they're given. Navigation becomes a `StatefulShellRoute.indexedStack` with three branches. Full-screen routes (debt form, settings, onboarding) sit on the root navigator.

**Tech Stack:** Flutter, Riverpod 3 (codegen), go_router 18, fl_chart 1.2, Drift (unchanged), `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md` (§3, §4.2–4.7, §5, §9, §11 item 2). Design reference: canvas page "A · Demolition crew" at https://claude.ai/artifact/V7Fq1gxCxmMd7J2RT2Gv4b.

## Global Constraints

- Money is never a float, except for display: chart values are major units computed from integer minor units at the edge (`currencyDecimalDigits`).
- All UI text goes in `lib/l10n/app_en.arb` and is read through `context.l10n`. Money and percentages are formatted with `formatMoney` and `formatPercent` using `formatLocaleProvider`.
- TDD for every task: a failing test first, then the minimal code. `dart analyze --fatal-infos` and `dart format lib test` must be clean before each commit.
- Run `./tool/codegen.sh` after changing a Riverpod provider or the ARB file.
- Ads: the anchored banner appears **only** on Debts and Plans, above the bottom nav, and never between list items.
- Borrowing alternatives (`isBorrowingAlternative`) are never marked cheapest, never drawn on the race chart, and never Home's plan.
- `hiVis` (`#FFC400`) is never a text colour, and always carries `#14213D` text.
- Each debt's colour comes from its index in the user's list order, modulo 6. Series are also told apart by line style, never by colour alone.
- Every chart has a `Semantics(label: …)` sentence, and every figure a chart shows also appears as text.
- Code names stay: `StrategyId`, `strategies/` folder, `StrategiesScreen`. Only user-facing copy says "Plans".
- Widget tests use `pumpApp` with a fixed clock of 24 Sep 2026 (as today). Never use real Drift streams or `compute` in widget tests.
- Commit after each task, ending the message with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
  ```

## Review Focus

1. **Card-transfer portions and synthetic debts** (`<card>#from-<source>`, `kConsolidationDebtId`, `kBalanceTransferDebtId`) in milestones, "pay this month", colours and payoff positions. A portion must be merged into its card, never shown as a separate debt. A synthetic debt takes the next colour after the user's debts. Tests: Task 2 and Task 3.
2. **More than 6 debts.** Colours wrap modulo 6 without crashing, and the legend still names every debt. Test: Task 2.
3. **Degenerate plans:** `monthsToClear == 0` (already debt-free) and single-month plans. Charts receive at least two points, and Home shows the "already debt-free" copy instead of a chart. Tests: Task 3 and Task 7.
4. **Large text** (`textScaler` 2.0) on Home's hero and the Debts rows must not overflow. Tests: Task 7 and Task 8.
5. **Route precedence:** `/plans/scenarios` must not be parsed as a strategy id. An unknown id still falls back to `/plans`, and going back from plan detail keeps the Plans tab and its scroll position. Test: Task 6.

---

## File structure

| File | Responsibility |
|---|---|
| `assets/fonts/BricolageGrotesque.ttf`, `AtkinsonHyperlegible-Regular.ttf`, `-Bold.ttf`, `OFL-*.txt` | Bundled fonts (OFL) |
| `lib/app/theme.dart` | `DestroyerColors` extension, `buildTheme`, `displayStyle` helper |
| `lib/core/debt_colors.dart` | `baseDebtId`, `debtColorIndex`, `debtColor` |
| `lib/features/analysis/domain/plan_series.dart` | Pure view data: totals, stacks, milestones, money split, first-month payments, payoff position, APR heat |
| `lib/features/strategies/presentation/current_plans.dart` | `currentPlansProvider`, `homePlanProvider` (Current settings, no slider extra) |
| `lib/core/charts/balance_line_chart.dart` | Line chart: race to zero, Home projection, sparklines |
| `lib/core/charts/stacked_balance_chart.dart` | Stacked area chart with a touch scrubber |
| `lib/core/charts/share_donut.dart` | Donut with centre label |
| `lib/core/charts/segment_bar.dart` | Horizontal proportion bar, optional hazard hatch |
| `lib/core/charts/comparison_bars.dart` | Horizontal labelled bars |
| `lib/core/charts/hazard.dart` | The hazard-stripe painter, shared |
| `lib/app/app_shell.dart` | Bottom-nav scaffold around the shell branches |
| `lib/app/router.dart` | Routes and the shell route |
| `lib/features/home/presentation/home_screen.dart` | Home |
| `lib/features/debts/presentation/debts_screen.dart` | Redesigned Debts |
| `lib/features/strategies/presentation/strategies_screen.dart` | Redesigned Plans |
| `lib/features/analysis/presentation/plan_detail_screen.dart` | Single-scroll plan detail (the tab files are deleted) |
| `lib/features/scenarios/presentation/scenarios_screen.dart` | The Compare tab gains bars |

---

### Task 1: Fonts and theme tokens

**Files:**
- Create: `assets/fonts/` (the three TTFs and their licences)
- Modify: `pubspec.yaml` (the `flutter: fonts:` section)
- Modify: `lib/app/theme.dart`
- Test: `test/app/theme_test.dart`

**Interfaces:**
- Produces: `class DestroyerColors extends ThemeExtension<DestroyerColors>` with fields `ink, ink2, ground, surface, outline, track, hiVis, onHiVis, navBar, navInactive, today, faint, series (List<Color>)`. `DestroyerColors.light` and `DestroyerColors.dark` constants. The extension `DestroyerTheme on BuildContext { DestroyerColors get colors; }`. `ThemeData buildTheme(Brightness)`. `TextStyle displayStyle(double size)` (Bricolage 800, tracking −3% of size). Font family names `kDisplayFont = 'BricolageGrotesque'` and `kBodyFont = 'AtkinsonHyperlegible'`.

- [ ] **Step 1: Add the fonts**

```bash
mkdir -p assets/fonts
curl -sL -o assets/fonts/BricolageGrotesque.ttf "https://github.com/google/fonts/raw/main/ofl/bricolagegrotesque/BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf"
curl -sL -o assets/fonts/AtkinsonHyperlegible-Regular.ttf "https://github.com/google/fonts/raw/main/ofl/atkinsonhyperlegible/AtkinsonHyperlegible-Regular.ttf"
curl -sL -o assets/fonts/AtkinsonHyperlegible-Bold.ttf "https://github.com/google/fonts/raw/main/ofl/atkinsonhyperlegible/AtkinsonHyperlegible-Bold.ttf"
curl -sL -o assets/fonts/OFL-BricolageGrotesque.txt "https://github.com/google/fonts/raw/main/ofl/bricolagegrotesque/OFL.txt"
curl -sL -o assets/fonts/OFL-AtkinsonHyperlegible.txt "https://github.com/google/fonts/raw/main/ofl/atkinsonhyperlegible/OFL.txt"
file assets/fonts/*.ttf   # each must say "TrueType Font data"
```

Add to `pubspec.yaml` under `flutter:`:

```yaml
  fonts:
    - family: BricolageGrotesque
      fonts:
        - asset: assets/fonts/BricolageGrotesque.ttf
    - family: AtkinsonHyperlegible
      fonts:
        - asset: assets/fonts/AtkinsonHyperlegible-Regular.ttf
        - asset: assets/fonts/AtkinsonHyperlegible-Bold.ttf
          weight: 700
```

Register the licences in `lib/main.dart` before `runApp`:

```dart
LicenseRegistry.addLicense(() async* {
  for (final name in ['BricolageGrotesque', 'AtkinsonHyperlegible']) {
    final text = await rootBundle.loadString('assets/fonts/OFL-$name.txt');
    yield LicenseEntryWithLineBreaks([name], text);
  }
});
```

Also list `assets/fonts/` under `flutter: assets:` so the `.txt` files are bundled.

- [ ] **Step 2: Write the failing test** (`test/app/theme_test.dart`)

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses the Direction A tokens', () {
    final theme = buildTheme(Brightness.light);
    final c = theme.extension<DestroyerColors>()!;
    expect(c.ink, const Color(0xFF14213D));
    expect(c.hiVis, const Color(0xFFFFC400));
    expect(c.onHiVis, const Color(0xFF14213D));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
    expect(theme.colorScheme.primary, const Color(0xFF14213D));
    expect(c.series, hasLength(6));
    expect(c.series.first, const Color(0xFF1F4FD1));
    expect(theme.textTheme.bodyMedium!.fontFamily, kBodyFont);
  });

  test('dark theme swaps the primary action to hi-vis', () {
    final theme = buildTheme(Brightness.dark);
    final c = theme.extension<DestroyerColors>()!;
    expect(theme.colorScheme.primary, const Color(0xFFFFC400));
    expect(theme.colorScheme.onPrimary, const Color(0xFF14213D));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0E1628));
    expect(c.series.first, const Color(0xFF4F83F5));
  });

  test('cards have 2px outlines, 6px corners and no elevation', () {
    final shape = buildTheme(Brightness.light).cardTheme.shape!
        as RoundedRectangleBorder;
    expect(shape.side.width, 2);
    expect(shape.borderRadius, BorderRadius.circular(6));
    expect(buildTheme(Brightness.light).cardTheme.elevation, 0);
  });

  test('display style is Bricolage ExtraBold', () {
    final s = displayStyle(40);
    expect(s.fontFamily, kDisplayFont);
    expect(s.fontVariations, contains(const FontVariation.weight(800)));
    expect(s.letterSpacing, closeTo(-1.2, 0.001));
  });
}
```

- [ ] **Step 3: Run it and check it fails**

Run: `flutter test test/app/theme_test.dart`
Expected: FAIL (`DestroyerColors` not defined).

- [ ] **Step 4: Implement `lib/app/theme.dart`**

```dart
import 'package:flutter/material.dart';

const kDisplayFont = 'BricolageGrotesque';
const kBodyFont = 'AtkinsonHyperlegible';
const _navy = Color(0xFF14213D);
const _hiVis = Color(0xFFFFC400);

/// Direction A ("Demolition crew") colours that Material has no slot for.
/// See spec §5.1.
@immutable
class DestroyerColors extends ThemeExtension<DestroyerColors> {
  const DestroyerColors({
    required this.ink,
    required this.ink2,
    required this.ground,
    required this.surface,
    required this.outline,
    required this.track,
    required this.navBar,
    required this.navInactive,
    required this.today,
    required this.faint,
    required this.series,
    this.hiVis = _hiVis,
    this.onHiVis = _navy,
  });

  final Color ink, ink2, ground, surface, outline, track, hiVis, onHiVis;
  final Color navBar, navInactive, today, faint;

  /// One colour per debt, by list order (validated for colour blindness).
  final List<Color> series;

  static const light = DestroyerColors(
    ink: _navy,
    ink2: Color(0xFF4A5568),
    ground: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    outline: _navy,
    track: Color(0xFFE6E8EC),
    navBar: _navy,
    navInactive: Color(0xFFC9D1E0),
    today: Color(0xFFD9590B),
    faint: Color(0xFF9AA3B2),
    series: [
      Color(0xFF1F4FD1), Color(0xFFD9590B), Color(0xFF0F9D7A),
      Color(0xFF7A5AF8), Color(0xFFC23B8A), Color(0xFFA87A00),
    ],
  );

  static const dark = DestroyerColors(
    ink: Color(0xFFEEF1F6),
    ink2: Color(0xFFA9B4C7),
    ground: Color(0xFF0E1628),
    surface: Color(0xFF17223A),
    outline: Color(0xFF3A4B6E),
    track: Color(0xFF24314D),
    navBar: Color(0xFF0A1120),
    navInactive: Color(0xFF8C99B3),
    today: Color(0xFFE0661A),
    faint: Color(0xFF5E6C88),
    series: [
      Color(0xFF4F83F5), Color(0xFFE0661A), Color(0xFF16A080),
      Color(0xFF8E78F5), Color(0xFFDE559F), Color(0xFFB08A00),
    ],
  );

  @override
  DestroyerColors copyWith() => this;

  @override
  DestroyerColors lerp(DestroyerColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension DestroyerTheme on BuildContext {
  DestroyerColors get colors => Theme.of(this).extension<DestroyerColors>()!;
}

/// Bricolage Grotesque ExtraBold with tight display tracking (−3%).
TextStyle displayStyle(double size, {Color? color}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation.weight(800)],
  letterSpacing: -0.03 * size,
  height: 1.0,
  color: color,
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? DestroyerColors.dark : DestroyerColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? _hiVis : _navy,
    onPrimary: dark ? _navy : Colors.white,
    secondary: _hiVis,
    onSecondary: _navy,
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    onError: dark ? _navy : Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.ink2,
    outline: c.outline,
    outlineVariant: c.track,
    surfaceContainerHighest: c.track,
  );
  final shape = RoundedRectangleBorder(
    side: BorderSide(color: c.outline, width: 2),
    borderRadius: BorderRadius.circular(6),
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: c.ground,
    extensions: [c],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: displayStyle(22, color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontFamily: kBodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: c.ink,
        side: BorderSide(color: dark ? c.ink : c.outline, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontFamily: kBodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.outline, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: dark ? c.ink2 : c.outline, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: c.outline, width: 1.5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.navBar,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? _hiVis : c.navInactive,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kBodyFont,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? _hiVis : c.navInactive,
        ),
      ),
    ),
  );
}
```

Remove `kBrandBlue` if nothing else uses it (`grep -rn kBrandBlue lib test`). If something does, keep it.

- [ ] **Step 5: Run the tests and the whole suite**

Run: `flutter test test/app/theme_test.dart && flutter test`
Expected: theme tests PASS. The existing suite still passes (finders use text and keys, not colours). If a test relied on the `primaryContainer` highlight of the cheapest card, leave it for Task 9, which rewrites that card.

- [ ] **Step 6: Commit**

```bash
git add assets/fonts pubspec.yaml lib/main.dart lib/app/theme.dart test/app/theme_test.dart
git commit -m "feat(theme): Direction A tokens, bundled Bricolage and Atkinson fonts"
```

---

### Task 2: Debt colours and base ids

**Files:**
- Create: `lib/core/debt_colors.dart`
- Test: `test/core/debt_colors_test.dart`

**Interfaces:**
- Consumes: `DestroyerColors.series` (Task 1).
- Produces:
  - `String baseDebtId(String planDebtId)`: strips a `#from-…` portion suffix.
  - `int debtColorIndex(String planDebtId, List<String> listOrderIds)`: the index of the base id in `listOrderIds`; unknown ids (synthetic) get `listOrderIds.length + k`, where k is stable per id in first-seen order via the optional `extras` list. Always taken modulo 6.
  - `Color debtColor(DestroyerColors c, String planDebtId, List<String> listOrderIds)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const order = ['a', 'b', 'c'];

  test('a portion belongs to its card', () {
    expect(baseDebtId('b#from-a'), 'b');
    expect(baseDebtId('b'), 'b');
  });

  test('colour follows list order, not clearing order', () {
    expect(debtColorIndex('c', order), 2);
    expect(debtColorIndex('b#from-a', order), 1);
  });

  test('synthetic debts take the next colour after the user list', () {
    expect(debtColorIndex(kConsolidationDebtId, order), 3);
    expect(debtColorIndex(kBalanceTransferDebtId, order), 3);
  });

  test('more than six debts wrap round', () {
    final many = [for (var i = 0; i < 8; i++) 'd$i'];
    expect(debtColorIndex('d6', many), 0);
    expect(debtColorIndex('d7', many), 1);
    expect(
      debtColor(DestroyerColors.light, 'd7', many),
      DestroyerColors.light.series[1],
    );
  });
}
```

- [ ] **Step 2: Run it and check it fails**

Run: `flutter test test/core/debt_colors_test.dart`
Expected: FAIL (the file doesn't exist).

- [ ] **Step 3: Implement**

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/painting.dart';

const _portion = '#from-';

/// The user's debt a plan column belongs to: a card-transfer portion
/// (`<card>#from-<source>`) belongs to its card.
String baseDebtId(String planDebtId) {
  final i = planDebtId.indexOf(_portion);
  return i < 0 ? planDebtId : planDebtId.substring(0, i);
}

/// A debt's colour slot: its position in the user's own list order, so it
/// never changes with the strategy. Debts the user didn't enter (a
/// consolidation loan, a transfer card) take the slot after the list.
int debtColorIndex(String planDebtId, List<String> listOrderIds) {
  final i = listOrderIds.indexOf(baseDebtId(planDebtId));
  return (i < 0 ? listOrderIds.length : i) % 6;
}

Color debtColor(
  DestroyerColors colors,
  String planDebtId,
  List<String> listOrderIds,
) => colors.series[debtColorIndex(planDebtId, listOrderIds)];
```

- [ ] **Step 4: Run it and check it passes**

Run: `flutter test test/core/debt_colors_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/debt_colors.dart test/core/debt_colors_test.dart
git commit -m "feat(core): debt colours by list order, portions merged with their card"
```

---

### Task 3: Plan view data

**Files:**
- Create: `lib/features/analysis/domain/plan_series.dart`
- Modify: `lib/features/analysis/presentation/plan_chart_tab.dart` (delete `stackedBalances`; it moves here)
- Test: `test/features/analysis/plan_series_test.dart`

**Interfaces:**
- Consumes: `baseDebtId` (Task 2), `PayoffPlan`, `currencyDecimalDigits`.
- Produces:
  - `List<double> totalOwedSeries(PayoffPlan plan)`: major units, index 0 = starting total, then each month's closing total. Always at least 2 points: a plan with no months gives `[start, start]`.
  - `List<List<double>> stackedBalances(PayoffPlan plan)`: moved unchanged (cumulative per column).
  - `class PlanDebtGroup { final String id; final String name; final List<int> columns; }` and `List<PlanDebtGroup> groupPlanDebts(PayoffPlan plan, String Function(PlanDebt) nameOf)`: clearing order, with portions merged into their card at the card's first position.
  - `class Milestone { final PlanDebtGroup debt; final int month; final Money rollsOn; final PlanDebtGroup? next; }` and `List<Milestone> milestones(PayoffPlan plan, String Function(PlanDebt) nameOf)`. `month` is 1-based: the first month the group's total closing balance is zero. `rollsOn` is the group's total payment in the month before its last (or in its last month when it clears in month 1). `next` is the following group, or null for the last.
  - `({Money principal, Money interest, Money fees}) moneySplit(PayoffPlan plan)`: principal = totalPaid − totalInterest − totalFees.
  - `List<({PlanDebtGroup debt, Money amount})> firstMonthPayments(PayoffPlan plan, String Function(PlanDebt) nameOf)`: positive amounts only, in clearing order.
  - `int? payoffPosition(PayoffPlan plan, String debtId)`: 1-based clearing position of the user's debt among groups, or null if it's not in the plan.
  - `enum AprHeat { high, medium, low }` and `AprHeat aprHeat(int aprBps)`: high ≥ 2000, medium ≥ 1000, low otherwise.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

Money gbp(int minor) => Money(minor, 'GBP');

MonthRow row(int month, List<int> pay, List<int> close) => MonthRow(
  month: month,
  interest: [for (final _ in pay) gbp(0)],
  payments: [for (final p in pay) gbp(p)],
  closingBalances: [for (final c in close) gbp(c)],
);

String name(PlanDebt d) => d.name;

void main() {
  // Overdraft clears in month 2; Visa (with a portion moved from Store)
  // clears in month 3.
  final plan = PayoffPlan(
    debts: [
      PlanDebt(id: 'od', name: 'Overdraft', startingBalance: gbp(20000)),
      PlanDebt(id: 'visa', name: 'Visa', startingBalance: gbp(30000)),
      PlanDebt(id: 'visa#from-store', name: 'Store', startingBalance: gbp(10000)),
    ],
    months: [
      row(1, [12000, 5000, 3000], [8000, 25000, 7000]),
      row(2, [8000, 9000, 3000], [0, 16000, 4000]),
      row(3, [0, 16000, 4000], [0, 0, 0]),
    ],
    totalPaid: gbp(60000),
    totalInterest: gbp(0),
    totalFees: gbp(0),
  );

  test('total owed starts with the starting balances', () {
    expect(totalOwedSeries(plan), [600.0, 400.0, 200.0, 0.0]);
  });

  test('an empty plan still gives two points', () {
    final done = plan.copyWith(months: []);
    expect(totalOwedSeries(done), [600.0, 600.0]);
  });

  test('portions are merged into their card', () {
    final groups = groupPlanDebts(plan, name);
    expect([for (final g in groups) g.id], ['od', 'visa']);
    expect(groups[1].columns, [1, 2]);
  });

  test('milestones say when each debt clears and what rolls on', () {
    final m = milestones(plan, name);
    expect(m, hasLength(2));
    expect(m[0].debt.name, 'Overdraft');
    expect(m[0].month, 2);
    expect(m[0].rollsOn, gbp(12000)); // month 1, the month before its last
    expect(m[0].next!.id, 'visa');
    expect(m[1].month, 3);
    expect(m[1].next, isNull);
  });

  test('first month payments are grouped and positive only', () {
    final p = firstMonthPayments(plan, name);
    expect([for (final x in p) (x.debt.id, x.amount.minor)], [
      ('od', 12000),
      ('visa', 8000),
    ]);
  });

  test('money split separates interest and fees', () {
    final withCosts = plan.copyWith(
      totalPaid: gbp(70000),
      totalInterest: gbp(8000),
      totalFees: gbp(2000),
    );
    final s = moneySplit(withCosts);
    expect(s.principal, gbp(60000));
    expect(s.interest, gbp(8000));
    expect(s.fees, gbp(2000));
  });

  test('payoff position counts groups, not columns', () {
    expect(payoffPosition(plan, 'od'), 1);
    expect(payoffPosition(plan, 'visa'), 2);
    expect(payoffPosition(plan, 'store'), isNull);
  });

  test('APR heat bands', () {
    expect(aprHeat(3990), AprHeat.high);
    expect(aprHeat(2000), AprHeat.high);
    expect(aprHeat(1999), AprHeat.medium);
    expect(aprHeat(1000), AprHeat.medium);
    expect(aprHeat(790), AprHeat.low);
  });
}
```

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/features/analysis/plan_series_test.dart`
Expected: FAIL (the file doesn't exist).

- [ ] **Step 3: Implement `plan_series.dart`**

```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:payoff_engine/payoff_engine.dart';

int _scale(String currency) {
  var s = 1;
  for (var i = 0; i < currencyDecimalDigits(currency); i++) {
    s *= 10;
  }
  return s;
}

/// Total owed in major units: the starting total, then each month's closing
/// total. At least two points, so a chart can always draw a line.
List<double> totalOwedSeries(PayoffPlan plan) {
  final scale = _scale(plan.totalPaid.currency);
  final start =
      plan.debts.fold<int>(0, (s, d) => s + d.startingBalance.minor) / scale;
  final totals = [
    start,
    for (final m in plan.months)
      m.closingBalances.fold<int>(0, (s, b) => s + b.minor) / scale,
  ];
  return totals.length == 1 ? [start, start] : totals;
}

/// For month 0 (starting balances) through the last month, the cumulative
/// balance in major units: element `i` is the sum of debts `0..i`.
List<List<double>> stackedBalances(PayoffPlan plan) {
  final scale = _scale(plan.totalPaid.currency);
  List<double> cumulative(List<Money> balances) {
    var running = 0;
    return [for (final b in balances) (running += b.minor) / scale];
  }

  return [
    cumulative([for (final d in plan.debts) d.startingBalance]),
    for (final row in plan.months) cumulative(row.closingBalances),
  ];
}

/// A user's debt as it appears in a plan: its own column plus any portions
/// moved onto it.
class PlanDebtGroup {
  const PlanDebtGroup(this.id, this.name, this.columns);

  final String id;
  final String name;
  final List<int> columns;
}

/// The plan's debts in clearing order, with each card-transfer portion
/// merged into its card.
List<PlanDebtGroup> groupPlanDebts(
  PayoffPlan plan,
  String Function(PlanDebt) nameOf,
) {
  final order = <String>[];
  final columns = <String, List<int>>{};
  final names = <String, String>{};
  for (final (i, d) in plan.debts.indexed) {
    final id = baseDebtId(d.id);
    if (!columns.containsKey(id)) {
      order.add(id);
      columns[id] = [];
    }
    columns[id]!.add(i);
    if (id == d.id) names[id] = nameOf(d);
    names.putIfAbsent(id, () => nameOf(d));
  }
  return [for (final id in order) PlanDebtGroup(id, names[id]!, columns[id]!)];
}

Money _sum(List<Money> values, List<int> columns, String currency) => Money(
  columns.fold<int>(0, (s, c) => s + values[c].minor),
  currency,
);

class Milestone {
  const Milestone(this.debt, this.month, this.rollsOn, this.next);

  final PlanDebtGroup debt;

  /// 1-based: the first month the debt's balance is zero.
  final int month;

  /// What was being paid on it in a full month, which rolls on to [next].
  final Money rollsOn;

  final PlanDebtGroup? next;
}

/// When each debt is cleared, in clearing order.
List<Milestone> milestones(
  PayoffPlan plan,
  String Function(PlanDebt) nameOf,
) {
  final currency = plan.totalPaid.currency;
  final groups = groupPlanDebts(plan, nameOf);
  final result = <Milestone>[];
  for (final (gi, g) in groups.indexed) {
    final idx = plan.months.indexWhere(
      (m) => _sum(m.closingBalances, g.columns, currency).isZero,
    );
    if (idx < 0) continue;
    final full = idx == 0 ? 0 : idx - 1;
    result.add(
      Milestone(
        g,
        idx + 1,
        _sum(plan.months[full].payments, g.columns, currency),
        gi + 1 < groups.length ? groups[gi + 1] : null,
      ),
    );
  }
  result.sort((a, b) => a.month.compareTo(b.month));
  return result;
}

({Money principal, Money interest, Money fees}) moneySplit(PayoffPlan plan) =>
    (
      principal: plan.totalPaid - plan.totalInterest - plan.totalFees,
      interest: plan.totalInterest,
      fees: plan.totalFees,
    );

/// This month's payment on each debt, grouped, in clearing order.
List<({PlanDebtGroup debt, Money amount})> firstMonthPayments(
  PayoffPlan plan,
  String Function(PlanDebt) nameOf,
) {
  if (plan.months.isEmpty) return const [];
  final currency = plan.totalPaid.currency;
  final first = plan.months.first;
  return [
    for (final g in groupPlanDebts(plan, nameOf))
      if (_sum(first.payments, g.columns, currency) case final amount
          when amount.isPositive)
        (debt: g, amount: amount),
  ];
}

/// Where the user's debt [debtId] comes in the clearing order (1 first).
int? payoffPosition(PayoffPlan plan, String debtId) {
  final groups = groupPlanDebts(plan, (d) => d.name);
  final i = groups.indexWhere((g) => g.id == debtId);
  return i < 0 ? null : i + 1;
}

enum AprHeat { high, medium, low }

AprHeat aprHeat(int aprBps) => aprBps >= 2000
    ? AprHeat.high
    : aprBps >= 1000
    ? AprHeat.medium
    : AprHeat.low;
```

In `plan_chart_tab.dart`, delete `stackedBalances` and import it from `plan_series.dart`. The tab file itself is deleted in Task 10. Move any existing `stackedBalances` test into `plan_series_test.dart` (`grep -rn stackedBalances test`).

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/analysis/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/analysis test/features/analysis
git commit -m "feat(analysis): pure view data for charts, milestones and payments"
```

---

### Task 4: Home's plan (Current settings, no slider)

**Files:**
- Create: `lib/features/strategies/presentation/current_plans.dart`
- Test: `test/features/strategies/current_plans_test.dart`

**Interfaces:**
- Consumes: `debtsProvider`, `settingsControllerProvider`, `planCalculatorProvider`, `rankResults`, `bestPayOffMethod`.
- Produces:
  - `currentPlansProvider` (`Future<PlanSet>`): Current settings, ignoring the selected scenario and the slider.
  - `homePlanProvider` (`Future<HomePlan>`), where `sealed class HomePlan`:
    - `HomeNoDebts()`
    - `HomeFollowing(Feasible result, PayoffResult baseline)`
    - `HomeShortfall(Money shortfall)`
    - `HomeNeverClears()`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  test('uses Current settings and ignores the slider and scenarios', () async {
    final c = await appTestContainer(
      debts: [testDebt(id: 'a', aprBps: 2000), testDebt(id: 'b', aprBps: 900)],
      scenarios: [scenarioWithBudget('big', 999900)],
    );
    c.read(selectedScenarioIdProvider.notifier).select('big');
    c.read(extraPaymentProvider.notifier).set(50000);
    c.listen(homePlanProvider, (_, _) {});
    final home = await c.read(homePlanProvider.future);
    final following = home as HomeFollowing;
    expect(following.result.strategyId, StrategyId.avalanche);
    final plain = await c.read(currentPlansProvider.future);
    expect(
      (plain.ranked.first as Feasible).plan.monthsToClear,
      following.result.plan.monthsToClear,
    );
  });

  test('no debts, shortfall and never-clears states', () async {
    final empty = await appTestContainer(debts: []);
    empty.listen(homePlanProvider, (_, _) {});
    expect(await empty.read(homePlanProvider.future), isA<HomeNoDebts>());

    final short = await appTestContainer(
      debts: [testDebt(id: 'a', balanceMinor: 1000000, minFloorMinor: 90000)],
      budgetMinor: 30000,
    );
    short.listen(homePlanProvider, (_, _) {});
    expect(await short.read(homePlanProvider.future), isA<HomeShortfall>());
  });
}
```

Before writing this test, open `test/helpers/test_container.dart` and `test/helpers/debts.dart`. If `appTestContainer`, `scenarioWithBudget`, `balanceMinor:`, `minFloorMinor:` or `budgetMinor:` don't exist under those names, use the helpers that do (the existing `plans_providers_test.dart` builds the same kind of container). Adapt the calls; don't add parallel helpers.

- [ ] **Step 2: Run it and check it fails**

Run: `flutter test test/features/strategies/current_plans_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:debt_destroyer/features/strategies/domain/strategy_groups.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_plans.g.dart';

/// Every strategy on the user's own settings: no saved scenario and no
/// "pay more" slider, which are both what-ifs (spec §4.2).
@riverpod
Future<PlanSet> currentPlans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  );
  return (ranked: rankResults(set.ranked), baseline: set.baseline);
}

sealed class HomePlan {
  const HomePlan();
}

class HomeNoDebts extends HomePlan {
  const HomeNoDebts();
}

class HomeFollowing extends HomePlan {
  const HomeFollowing(this.result, this.baseline);

  final Feasible result;
  final PayoffResult baseline;
}

class HomeShortfall extends HomePlan {
  const HomeShortfall(this.shortfall);

  final Money shortfall;
}

class HomeNeverClears extends HomePlan {
  const HomeNeverClears();
}

/// The plan Home follows: until Plan 8 adds a chosen plan, the cheapest way
/// to pay off.
@riverpod
Future<HomePlan> homePlan(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  if (debts.isEmpty) return const HomeNoDebts();
  final set = await ref.watch(currentPlansProvider.future);
  if (bestPayOffMethod(set.ranked) case final best?) {
    return HomeFollowing(best, set.baseline);
  }
  for (final r in set.ranked) {
    if (r case Infeasible(:final shortfall)) return HomeShortfall(shortfall);
  }
  return const HomeNeverClears();
}
```

Run `./tool/codegen.sh`.

- [ ] **Step 4: Run it and check it passes**

Run: `flutter test test/features/strategies/current_plans_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/strategies/presentation/current_plans.dart test/features/strategies/current_plans_test.dart
git commit -m "feat(strategies): Home's plan on Current settings, ignoring what-ifs"
```

---

### Task 5: Chart kit

**Files:**
- Create: `lib/core/charts/hazard.dart`, `balance_line_chart.dart`, `stacked_balance_chart.dart`, `share_donut.dart`, `segment_bar.dart`, `comparison_bars.dart`
- Test: `test/core/charts_test.dart`

**Interfaces:**
- Consumes: `DestroyerColors` (Task 1).
- Produces:
  - `enum LineStyle { solid, dashed, dotted }`
  - `class ChartLine { const ChartLine({required this.values, required this.color, this.style = LineStyle.solid, this.width = 2.5, this.label}); }`
  - `BalanceLineChart({required List<ChartLine> lines, required String semanticLabel, double height = 150, bool compact = false, String? startLabel, String? endLabel})`. `compact` = a sparkline, with no axes or labels.
  - `StackedBalanceChart({required List<List<double>> stacks, required List<Color> colors, required List<String> names, required String semanticLabel, required String Function(int month, double total) tooltipTitle, double height = 200, Set<int> hidden = const {}})`
  - `ShareDonut({required List<({double value, Color color})> slices, required String centre, required String caption, required String semanticLabel, double size = 128})`
  - `class Segment { const Segment(this.value, this.color, {this.hazard = false}); }` and `SegmentBar({required List<Segment> segments, required String semanticLabel, double height = 16})`
  - `class ComparisonBar { const ComparisonBar({required this.label, required this.value, required this.trailing, this.highlight = false}); }` and `ComparisonBars({required List<ComparisonBar> bars, required String semanticLabel})`
  - `class HazardPainter extends CustomPainter` (−45° stripes, `hiVis` and `#14213D`, 7px stripe).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/core/charts/comparison_bars.dart';
import 'package:debt_destroyer/core/charts/segment_bar.dart';
import 'package:debt_destroyer/core/charts/share_donut.dart';
import 'package:debt_destroyer/core/charts/stacked_balance_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: Scaffold(body: Center(child: SizedBox(width: 340, child: child))),
);

void main() {
  testWidgets('line chart draws each line with its style and a label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BalanceLineChart(
          semanticLabel: 'Two plans',
          lines: [
            ChartLine(values: [10, 5, 0], color: Colors.blue),
            ChartLine(
              values: [10, 8, 6, 4],
              color: Colors.grey,
              style: LineStyle.dashed,
            ),
          ],
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    expect(chart.data.lineBarsData[1].dashArray, isNotNull);
    expect(find.bySemanticsLabel('Two plans'), findsOneWidget);
  });

  testWidgets('a single-value line still draws', (tester) async {
    await tester.pumpWidget(
      host(
        const BalanceLineChart(
          semanticLabel: 'x',
          lines: [ChartLine(values: [3], color: Colors.blue)],
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, hasLength(2));
  });

  testWidgets('donut shows its centre text and survives all-zero data', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareDonut(
          semanticLabel: 'Owed',
          centre: '£0',
          caption: 'total owed',
          slices: [(value: 0, color: Colors.red)],
        ),
      ),
    );
    expect(find.text('£0'), findsOneWidget);
  });

  testWidgets('stacked chart, segment bar and comparison bars render', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            StackedBalanceChart(
              semanticLabel: 'Stack',
              stacks: const [
                [2, 5],
                [1, 3],
                [0, 0],
              ],
              colors: const [Colors.red, Colors.blue],
              names: const ['A', 'B'],
              tooltipTitle: (m, t) => 'Month $m',
            ),
            const SegmentBar(
              semanticLabel: 'Split',
              segments: [Segment(3, Colors.grey), Segment(1, Colors.black, hazard: true)],
            ),
            const ComparisonBars(
              semanticLabel: 'Compare',
              bars: [
                ComparisonBar(label: 'Now', value: 2, trailing: 'Nov 28'),
                ComparisonBar(
                  label: 'More',
                  value: 1,
                  trailing: 'Jun 28',
                  highlight: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Jun 28'), findsOneWidget);
    expect(find.bySemanticsLabel('Split'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/core/charts_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the widgets**

`hazard.dart`:

```dart
import 'package:flutter/rendering.dart';

/// "Still to knock down": −45° hi-vis and navy stripes (spec §5.1).
class HazardPainter extends CustomPainter {
  const HazardPainter({this.stripe = 7});

  final double stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFC400),
    );
    final navy = Paint()..color = const Color(0xFF14213D);
    for (var x = -size.height; x < size.width + size.height; x += stripe * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripe, size.height)
        ..lineTo(x + stripe + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, navy);
    }
  }

  @override
  bool shouldRepaint(HazardPainter old) => old.stripe != stripe;
}
```

`balance_line_chart.dart`:

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

enum LineStyle { solid, dashed, dotted }

class ChartLine {
  const ChartLine({
    required this.values,
    required this.color,
    this.style = LineStyle.solid,
    this.width = 2.5,
    this.label,
  });

  final List<double> values;
  final Color color;
  final LineStyle style;
  final double width;
  final String? label;
}

/// Balances over time as lines: race to zero, Home's projection,
/// sparklines ([compact]).
class BalanceLineChart extends StatelessWidget {
  const BalanceLineChart({
    required this.lines,
    required this.semanticLabel,
    this.height = 150,
    this.compact = false,
    this.startLabel,
    this.endLabel,
    super.key,
  });

  final List<ChartLine> lines;
  final String semanticLabel;
  final double height;
  final bool compact;
  final String? startLabel;
  final String? endLabel;

  static List<FlSpot> _spots(List<double> v) => [
    for (final (i, y) in v.indexed) FlSpot(i.toDouble(), y),
    if (v.length == 1) FlSpot(1, v.first),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxX = lines.fold<int>(1, (m, l) => l.values.length - 1 > m ? l.values.length - 1 : m);
    final maxY = lines.fold<double>(0, (m, l) => l.values.fold(m, (a, b) => b > a ? b : a));
    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX.toDouble(),
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.05,
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(
          show: !compact,
          border: Border(bottom: BorderSide(color: c.ink, width: 1.5)),
        ),
        gridData: FlGridData(
          show: !compact,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: c.track, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          for (final l in lines)
            LineChartBarData(
              spots: _spots(l.values),
              color: l.color,
              barWidth: l.width,
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
              dashArray: switch (l.style) {
                LineStyle.solid => null,
                LineStyle.dashed => [7, 4],
                LineStyle.dotted => [2, 4],
              },
            ),
        ],
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 400),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: height, child: chart),
          if (!compact && (startLabel != null || endLabel != null))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(startLabel ?? '', style: TextStyle(fontSize: 11, color: c.ink2)),
                  const Spacer(),
                  Text(endLabel ?? '', style: TextStyle(fontSize: 11, color: c.ink2)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

`stacked_balance_chart.dart`: an `fl_chart` `LineChart` with one `LineChartBarData` per debt, from the tallest stack down (as in today's `PlanChartTab`). Each band is filled with its colour, and `barWidth: 2` with the band's line in `c.surface` for the 2px gap between bands. Touch is on (`handleBuiltInTouches: true`), with a `LineTouchTooltipData` whose first item is `tooltipTitle(month, total)` and whose remaining items give each non-hidden debt's own balance (`stack[i] - stack[i-1]`). `getTooltipColor` is `c.surface` with a 2px `c.outline` border. Columns in `hidden` are drawn with zero height (recompute the cumulative sums skipping hidden columns). Wrap it in `Semantics(label:, excludeSemantics: true)`.

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class StackedBalanceChart extends StatelessWidget {
  const StackedBalanceChart({
    required this.stacks,
    required this.colors,
    required this.names,
    required this.semanticLabel,
    required this.tooltipTitle,
    this.height = 200,
    this.hidden = const {},
    super.key,
  });

  /// Per month (0 = start): cumulative balances, as `stackedBalances`.
  final List<List<double>> stacks;
  final List<Color> colors;
  final List<String> names;
  final String semanticLabel;
  final String Function(int month, double total) tooltipTitle;
  final double height;
  final Set<int> hidden;

  List<List<double>> _visible() => [
    for (final row in stacks)
      () {
        var running = 0.0;
        return [
          for (final (i, v) in row.indexed)
            running += hidden.contains(i) ? 0 : v - (i == 0 ? 0 : row[i - 1]),
        ];
      }(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _visible();
    final n = names.length;
    final bars = [
      for (var i = n - 1; i >= 0; i--)
        LineChartBarData(
          spots: [for (final (m, r) in rows.indexed) FlSpot(m.toDouble(), r[i])],
          color: c.surface,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: colors[i]),
        ),
    ];
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: 0,
            lineBarsData: bars,
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: c.ink, width: 1.5)),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: c.track, strokeWidth: 1),
            ),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: LineTouchData(
              getTouchedSpotIndicator: (bar, idx) => [
                for (final _ in idx)
                  TouchedSpotIndicatorData(
                    FlLine(color: c.ink, strokeWidth: 1.5),
                    const FlDotData(show: false),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => c.surface,
                tooltipBorder: BorderSide(color: c.outline, width: 2),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) {
                  if (spots.isEmpty) return [];
                  final m = spots.first.x.toInt();
                  final row = rows[m];
                  final lines = <String>[
                    tooltipTitle(m, row.isEmpty ? 0 : row.last),
                    for (var i = 0; i < n; i++)
                      if (!hidden.contains(i) &&
                          row[i] - (i == 0 ? 0 : row[i - 1]) > 0.005)
                        names[i],
                  ];
                  return [
                    LineTooltipItem(
                      lines.join('\n'),
                      TextStyle(color: c.ink, fontSize: 12, fontFamily: kBodyFont),
                    ),
                    for (var k = 1; k < spots.length; k++) null,
                  ];
                },
              ),
            ),
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 400),
        ),
      ),
    );
  }
}
```

(`tooltipTitle` is where the screen puts the month, date and total. The names listed are the debts still owing that month; the screen's legend chips show the amounts in text.)

`share_donut.dart`:

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ShareDonut extends StatelessWidget {
  const ShareDonut({
    required this.slices,
    required this.centre,
    required this.caption,
    required this.semanticLabel,
    this.size = 128,
    super.key,
  });

  final List<({double value, Color color})> slices;
  final String centre;
  final String caption;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: total > 0 ? 2 : 0,
                centerSpaceRadius: size * 0.32,
                sections: total > 0
                    ? [
                        for (final s in slices)
                          if (s.value > 0)
                            PieChartSectionData(
                              value: s.value,
                              color: s.color,
                              radius: size * 0.14,
                              showTitle: false,
                            ),
                      ]
                    : [
                        PieChartSectionData(
                          value: 1,
                          color: c.track,
                          radius: size * 0.14,
                          showTitle: false,
                        ),
                      ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(child: Text(centre, style: displayStyle(size * 0.15, color: c.ink))),
                Text(caption, style: TextStyle(fontSize: 11, color: c.ink2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

`segment_bar.dart`:

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/charts/hazard.dart';
import 'package:flutter/material.dart';

class Segment {
  const Segment(this.value, this.color, {this.hazard = false});

  final double value;
  final Color color;
  final bool hazard;
}

class SegmentBar extends StatelessWidget {
  const SegmentBar({
    required this.segments,
    required this.semanticLabel,
    this.height = 16,
    super.key,
  });

  final List<Segment> segments;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = segments.fold<double>(0, (s, x) => s + x.value);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.track,
          border: Border.all(color: c.outline, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: total <= 0
            ? null
            : Row(
                children: [
                  for (final s in segments)
                    if (s.value > 0)
                      Expanded(
                        flex: (s.value / total * 1000).round().clamp(1, 1000),
                        child: s.hazard
                            ? const CustomPaint(painter: HazardPainter())
                            : ColoredBox(color: s.color),
                      ),
                ],
              ),
      ),
    );
  }
}
```

`comparison_bars.dart`:

```dart
import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';

class ComparisonBar {
  const ComparisonBar({
    required this.label,
    required this.value,
    required this.trailing,
    this.highlight = false,
  });

  final String label;
  final double value;
  final String trailing;
  final bool highlight;
}

class ComparisonBars extends StatelessWidget {
  const ComparisonBars({required this.bars, required this.semanticLabel, super.key});

  final List<ComparisonBar> bars;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in bars)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(b.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text(b.trailing),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 16,
                        width: max <= 0 ? 0 : box.maxWidth * b.value / max,
                        decoration: BoxDecoration(
                          color: b.highlight ? c.hiVis : c.ink2,
                          border: b.highlight ? Border.all(color: c.onHiVis, width: 2) : null,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/charts_test.dart`
Expected: PASS. If `fl_chart` 1.2 names differ (for example `tooltipBorder`, or `getTooltipColor`), check the installed API with `grep -rn "class LineTouchTooltipData" -A40 ~/.pub-cache/hosted/pub.dev/fl_chart-*/lib` and adapt. Don't change the widget's public constructor.

- [ ] **Step 5: Commit**

```bash
git add lib/core/charts test/core/charts_test.dart
git commit -m "feat(charts): shared chart kit — lines, stacked area, donut, bars"
```

---

### Task 6: Three-tab shell and routes

**Files:**
- Create: `lib/app/app_shell.dart`
- Modify: `lib/app/router.dart`, every `Routes.strategies` user (`grep -rn "Routes.strategies\|Routes.debts" lib test`), `lib/l10n/app_en.arb`, `test/helpers/pump_app.dart`, `test/app/router_test.dart`
- Create: `lib/features/home/presentation/home_screen.dart` (a placeholder `Scaffold` with the app-bar title `l10n.appTitle`; Task 7 fills it in)

**Interfaces:**
- Produces: the new routes (all later tasks and the whole test suite depend on these):

```dart
abstract final class Routes {
  static const home = '/';
  static const debts = '/debts';
  static const newDebt = '/debts/new';
  static const plans = '/plans';
  static const scenarios = '/plans/scenarios';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
  static String editDebt(String id) => '/debts/$id';
  static String plan(StrategyId id) => '$plans/${id.name}';
  static String editScenario(String id) => '$scenarios/$id';
}
```

- `AppShell({required StatefulNavigationShell shell})`: a `Scaffold` whose `bottomNavigationBar` is a `NavigationBar` with three destinations (Home / Debts / Plans). `onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex)`.
- New ARB keys: `"navHome": "Home"`, `"navDebts": "Debts"`, `"navPlans": "Plans"`. Changed values: `"strategiesTitle": "Plans"`, `"compareStrategies": "See plans"`, `"strategiesEmpty": "Add a debt to see your plans."`.

- [ ] **Step 1: Rewrite `test/app/router_test.dart` (failing)**

```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/home/presentation/home_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('a new user is sent to onboarding', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await app.router.go(tester, Routes.plans);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('finishing onboarding opens Home', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    await app.container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the bottom nav switches tabs', (tester) async {
    await pumpApp(tester, location: Routes.home, debts: [testDebt(id: 'a')]);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('Debts').last);
    await tester.pumpAndSettle();
    expect(find.byType(DebtsScreen), findsOneWidget);
    await tester.tap(find.text('Plans').last);
    await tester.pumpAndSettle();
    expect(find.byType(StrategiesScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('scenarios is not mistaken for a strategy id', (tester) async {
    final app = await pumpApp(tester, location: Routes.scenarios);
    expect(find.byType(ScenariosScreen), findsOneWidget);
    await app.router.go(tester, Routes.plan(StrategyId.balanceTransfer));
    expect(
      tester.widget<PlanDetailScreen>(find.byType(PlanDetailScreen)).strategyId,
      StrategyId.balanceTransfer,
    );
  });

  testWidgets('an unknown strategy id falls back to Plans', (tester) async {
    final app = await pumpApp(tester);
    await app.router.go(tester, '${Routes.plans}/nonsense');
    expect(find.byType(StrategiesScreen), findsOneWidget);
    expect(app.router.location, Routes.plans);
  });

  testWidgets('the debt form and settings hide the nav', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    expect(find.byType(DebtFormScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await app.router.go(tester, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('going back from plan detail keeps the Plans tab', (
    tester,
  ) async {
    await pumpApp(tester, location: Routes.plans, debts: [testDebt(id: 'a')]);
    await tester.tap(find.text('Highest interest first').first);
    await tester.pumpAndSettle();
    expect(find.byType(PlanDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StrategiesScreen), findsOneWidget);
  });
}
```

(Check the avalanche card's visible title with `grep '"strategyAvalanche"' lib/l10n/app_en.arb`, and use that string in the last test.)

- [ ] **Step 2: Run it and check it fails**

Run: `flutter test test/app/router_test.dart`
Expected: FAIL (`Routes.home` and `HomeScreen` don't exist).

- [ ] **Step 3: Implement the router**

In `lib/app/router.dart`, replace `Routes` with the block above and build:

```dart
final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final router = GoRouter(
  navigatorKey: rootKey,
  refreshListenable: onboardingComplete,
  redirect: (context, state) {
    final complete = onboardingComplete.value;
    if (complete == null) return null;
    final atOnboarding = state.matchedLocation == Routes.onboarding;
    if (!complete && !atOnboarding) return Routes.onboarding;
    if (complete && atOnboarding) return Routes.home;
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.debts,
              builder: (_, _) => const DebtsScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: rootKey,
                  builder: (_, _) => const DebtFormScreen(),
                ),
                GoRoute(
                  path: ':debtId',
                  parentNavigatorKey: rootKey,
                  builder: (_, state) =>
                      DebtFormScreen(debtId: state.pathParameters['debtId']),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.plans,
              builder: (_, _) => const StrategiesScreen(),
              routes: [
                // Before ':strategyId', so "scenarios" is never read as an id.
                GoRoute(
                  path: 'scenarios',
                  builder: (_, _) => const ScenariosScreen(),
                  routes: [
                    GoRoute(
                      path: ':scenarioId',
                      builder: (_, state) => ScenarioFormScreen(
                        scenarioId: state.pathParameters['scenarioId']!,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: ':strategyId',
                  redirect: (_, state) =>
                      _strategyId(state) == null ? Routes.plans : null,
                  builder: (_, state) =>
                      PlanDetailScreen(strategyId: _strategyId(state)!),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
    GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
  ],
);
```

`lib/app/app_shell.dart`:

```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The three tabs. Each keeps its own stack and scroll position.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: l10n.navHome),
          NavigationDestination(icon: const Icon(Icons.list_alt_outlined), selectedIcon: const Icon(Icons.list_alt), label: l10n.navDebts),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: l10n.navPlans),
        ],
      ),
    );
  }
}
```

Update every `Routes.strategies` to `Routes.plans`, and the scenarios paths to `Routes.scenarios` and `Routes.editScenario`. `DebtsScreen`'s "See plans" button calls `context.go(Routes.plans)` (a tab switch, not a push). In `pump_app.dart`, keep the default `location = Routes.debts` and navigate whenever `location != Routes.home`. Add the ARB keys, then run `./tool/codegen.sh`.

- [ ] **Step 4: Run the router tests, then the whole suite, and fix the location strings**

Run: `flutter test test/app/router_test.dart && flutter test`
Expected: router tests PASS. Fix other failures only where a test used an old path or the old "Compare strategies"/"Strategies" copy. Update those strings to the new copy (`See plans`/`Plans`), and don't change the behaviour being tested.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(app): three-tab shell (Home, Debts, Plans); Strategies becomes Plans"
```

---

### Task 7: Home screen

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`
- Create: `lib/core/widgets/hi_vis_block.dart` (the yellow hero container) and `lib/core/widgets/outlined_card.dart` (a card with a title row), both reused by Tasks 8–10
- Modify: `lib/l10n/app_en.arb`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `homePlanProvider` (Task 4); `totalOwedSeries`, `milestones`, `firstMonthPayments` (Task 3); `BalanceLineChart`, `HazardPainter` (Task 5); `debtColor` (Task 2); `clockProvider`; `formatLocaleProvider`.
- Produces:
  - `HiVisBlock({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)})`: `hiVis` fill, 2px `onHiVis` border, 6px radius, and a `DefaultTextStyle` in `onHiVis`.
  - `OutlinedCard({String? title, String? trailing, required Widget child})`: `Card` from the theme, 14px padding, with a title row in `displayStyle(17)` plus trailing text in `ink2`.
- New ARB keys:

```json
"homeDebtFreeBy": "Debt-free by",
"homeInDuration": "in {duration} · {strategy}",
"@homeInDuration": {"placeholders": {"duration": {"type": "String"}, "strategy": {"type": "String"}}},
"homeProjectionTitle": "Your burn-down",
"homeProjectionLabel": "Total owed falls from {start} today to nothing by {date}.",
"@homeProjectionLabel": {"placeholders": {"start": {"type": "String"}, "date": {"type": "String"}}},
"homeMinimumsLine": "Minimums only",
"homeNextUp": "Next up: {debt} gone",
"@homeNextUp": {"placeholders": {"debt": {"type": "String"}}},
"homeNextUpDetail": "{duration} to go. Then {amount} a month rolls onto {next}.",
"@homeNextUpDetail": {"placeholders": {"duration": {"type": "String"}, "amount": {"type": "String"}, "next": {"type": "String"}}},
"homeNextUpLast": "{duration} to go. That's the last one.",
"@homeNextUpLast": {"placeholders": {"duration": {"type": "String"}}},
"homeNoDebts": "Add your debts and we'll show you the fastest way to clear them.",
"homeAddFirstDebt": "Add your first debt",
"homeNeverClears": "At this budget, your debts would never be cleared. Try paying a little more each month.",
"homeAlreadyDebtFree": "You're debt-free. Nice work."
```

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/charts/balance_line_chart.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final debts = [
    testDebt(id: 'od', name: 'Overdraft', aprBps: 3990),
    testDebt(id: 'car', name: 'Car loan', aprBps: 790),
  ];

  testWidgets('shows the debt-free date, the chart and this month', (
    tester,
  ) async {
    await pumpApp(tester, location: Routes.home, debts: debts);
    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.byType(BalanceLineChart), findsOneWidget);
    expect(find.textContaining('Next up: Overdraft gone'), findsOneWidget);
    expect(find.text('Pay this month'), findsOneWidget);
    expect(find.text('Overdraft'), findsWidgets);
  });

  testWidgets('with no debts, invites the first one', (tester) async {
    await pumpApp(tester, location: Routes.home);
    await tester.tap(find.text('Add your first debt'));
    await tester.pumpAndSettle();
    expect(find.byType(DebtFormScreen), findsOneWidget);
  });

  testWidgets('a budget below the minimums shows the shortfall', (
    tester,
  ) async {
    await pumpApp(
      tester,
      location: Routes.home,
      debts: debts,
      settings: {SettingsKeys.monthlyBudget: 100},
    );
    expect(find.text('Change budget'), findsOneWidget);
    expect(find.byType(BalanceLineChart), findsNothing);
  });

  testWidgets('tapping the chart opens the plan', (tester) async {
    final app = await pumpApp(tester, location: Routes.home, debts: debts);
    await tester.tap(find.byType(BalanceLineChart));
    await tester.pumpAndSettle();
    expect(app.router.location, startsWith(Routes.plans));
  });

  testWidgets('large text does not overflow the hero', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: Routes.home, debts: debts);
    expect(tester.takeException(), isNull);
  });
}
```

(Check how existing tests seed a budget (`grep -rn "monthlyBudget" test/features/debts/debts_screen_test.dart`) and use the same key and value format.)

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Build `HomeScreen` as a `ConsumerWidget`:
- **App bar:** title `l10n.appTitle` (`displayStyle(19)`), and a gear `IconButton` pushing `Routes.settings`.
- **Body:** a `ListView` with 16px padding and 12px gaps, switching on `ref.watch(homePlanProvider)`:
  - `AsyncData(HomeFollowing(:result, :baseline))`:
    1. `HiVisBlock`:
       - "Debt-free by" (14px).
       - `DateFormat.yMMM(locale)` of `now + monthsToClear` in `displayStyle(50)` (split month and year onto two lines with `'\n'`, as in the comp).
       - `homeInDuration(formatDuration(...), strategyName(...))`.
    2. An `OutlinedCard` titled `homeProjectionTitle`, wrapped in `InkWell(onTap: () => context.go(Routes.plan(result.strategyId)))`, holding a `BalanceLineChart` with:
       - the plan's `totalOwedSeries` in `c.ink`, solid, width 3;
       - when the baseline is `Feasible`, the baseline's `totalOwedSeries` truncated to the plan's length + 12 months, in `c.faint`, `LineStyle.dashed`, width 2;
       - `semanticLabel: homeProjectionLabel(...)`;
       - `startLabel` "now" month (`DateFormat.MMMyy`), and `endLabel` the debt-free month.

       Below the chart, a legend row with two keys (solid ink = strategy name, dashed faint = `homeMinimumsLine`).
    3. The next milestone, `milestones(plan, nameOf).first`, in an `OutlinedCard`:
       - bold `homeNextUp(name)`, with the date trailing;
       - a 12px-high `CustomPaint(painter: HazardPainter())` inside a `FractionallySizedBox`, whose width fraction is the share of that debt's starting balance already covered by the months elapsed (`0` in Plan 7, since progress is Plan 8, so draw a 4% minimum sliver);
       - `homeNextUpDetail` or `homeNextUpLast`.
    4. Pay this month: an `OutlinedCard` titled `payThisMonth`, with the total trailing. It has one row per `firstMonthPayments` entry: a 10×10 colour square (`debtColor` with the user's list order from `debtsProvider`), the name, and the amount (bold, tabular figures).
  - `AsyncData(HomeFollowing)` with `plan.monthsToClear == 0`: a `HiVisBlock` with `homeAlreadyDebtFree`.
  - `AsyncData(HomeNoDebts())`: centred `homeNoDebts` text and a `FilledButton(onPressed: () => context.push(Routes.newDebt), child: Text(l10n.homeAddFirstDebt))`.
  - `AsyncData(HomeShortfall(:shortfall))`: the existing shortfall message `l10n.budgetShortfall(...)` in an `OutlinedCard`, plus a `FilledButton(l10n.changeBudget)` pushing `Routes.settings`.
  - `AsyncData(HomeNeverClears())`: `homeNeverClears`.
  - `AsyncError`: `ErrorRetryView`, invalidating `settingsControllerProvider` and `currentPlansProvider`.
  - Loading: `CircularProgressIndicator`.

Every `Row` holding text uses `Expanded`/`Flexible` so 200% text wraps instead of overflowing.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/home/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(home): debt-free date, burn-down chart, next milestone, this month"
```

---

### Task 8: Debts screen

**Files:**
- Modify: `lib/features/debts/presentation/debts_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/debts/debts_screen_test.dart` (extend; keep every existing behaviour test passing)

**Interfaces:**
- Consumes: `ShareDonut`, `SegmentBar` (Task 5); `debtColor` (Task 2); `aprHeat`, `payoffPosition` (Task 3); `homePlanProvider` (Task 4); `OutlinedCard` (Task 7).
- New ARB keys: `"debtsExtraAtWork": "{amount} extra goes to work each month"` (placeholder `amount`), `"debtsTotalCaption": "total owed"`, `"aprHeatHigh": "High"`, `"aprHeatMedium": "Med"`, `"aprHeatLow": "Low"`, `"debtClearsPosition": "clears {position}"` (placeholder `position`, String), `"debtsShareLabel": "What you owe: {parts}. Total {total}."` (placeholders `parts`, `total`), and `"ordinal"` as an ICU select-ordinal: `"{n, selectordinal, =1{1st} =2{2nd} =3{3rd} other{{n}th}}"` with `n` of type `int`. (Check that `flutter gen-l10n` accepts `selectordinal`. If not, write a Dart `ordinal(int)` for English in `labels.dart` with a unit test, and use the plain placeholder.)

- [ ] **Step 1: Add the failing tests to `debts_screen_test.dart`**

```dart
testWidgets('summarises with a donut and the budget bar', (tester) async {
  await pumpApp(tester, debts: [
    testDebt(id: 'a', name: 'Visa', aprBps: 2490),
    testDebt(id: 'b', name: 'Loan', aprBps: 790),
  ]);
  expect(find.byType(ShareDonut), findsOneWidget);
  expect(find.byType(SegmentBar), findsOneWidget);
  expect(find.textContaining('extra goes to work'), findsOneWidget);
});

testWidgets('each debt shows its rate band and when it clears', (
  tester,
) async {
  await pumpApp(tester, debts: [
    testDebt(id: 'a', name: 'Visa', aprBps: 2490),
    testDebt(id: 'b', name: 'Loan', aprBps: 790),
  ]);
  expect(find.text('High'), findsOneWidget);
  expect(find.text('Low'), findsOneWidget);
  expect(find.text('clears 1st'), findsOneWidget);
  expect(find.text('clears 2nd'), findsOneWidget);
});

testWidgets('large text does not overflow the rows', (tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpApp(tester, debts: [testDebt(id: 'a', name: 'A very long debt name indeed')]);
  expect(tester.takeException(), isNull);
});
```

Update the existing test `'compare opens the strategies'`: the button reads "See plans", and afterwards `StrategiesScreen` is showing inside the shell.

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/features/debts/debts_screen_test.dart`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement**

- **`_SummaryCard`:** an `OutlinedCard` with a `Row`:
  - `ShareDonut(size: 128, centre: formatMoney(total), caption: l10n.debtsTotalCaption)`, with one slice per debt (value = balance in major units, colour = `debtColor(c, d.id, ids)`) and `semanticLabel: debtsShareLabel(parts, total)`. Parts are "Visa 27%", ... in list order.
  - An `Expanded` column:
    - the "Minimums" and "Budget" rows (existing strings `minimumPayments`, `monthlyBudget`);
    - a `SegmentBar` with `[Segment(minimums, c.ink2), Segment(extra, c.hiVis)]` (extra = budget − minimums, when positive);
    - `debtsExtraAtWork(extra)`.
- **`_ShortfallBanner`:** unchanged behaviour. Restyle it as an `OutlinedCard` with the error colour for the icon.
- **`DebtTile`:** keep the class name, the `onTap` and the `Dismissible`/reorder wrapping. Its content becomes a `Card` (from the theme) with 10/12 padding:
  - a leading 38×38 rounded square filled with the debt's colour, holding the existing type icon in white;
  - the name (bold);
  - a heat chip: `High` is filled `c.ink` with `c.ground` text; `Med` and `Low` are outlined in `c.ink2`;
  - the balance in `displayStyle(18)` (right);
  - a 6px share bar (a `FractionallySizedBox` of `balance/total`, in the debt's colour, over `c.track`);
  - a bottom row: the existing `debtApr`/`debtMinimum` text, plus `debtClearsPosition(ordinal(pos))` when `payoffPosition(homePlan, d.id)` is non-null.

  Keep the transfer-offer marker text (`debtTransferOffer`) where it was in the subtitle line.
- **Bottom buttons:** `OutlinedButton.icon(add)` "Add debt" and `FilledButton` "See plans" (`context.go(Routes.plans)`). The banner stays in the screen's `bottomNavigationBar` slot, now above the shell's nav bar.
- **List spacing:** `ReorderableListView` items are separated by 10px (`Padding(bottom: 10)` in the item builder).

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/debts/`
Expected: PASS (old and new).

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(debts): donut summary, budget bar, colour avatars and payoff position"
```

---

### Task 9: Plans screen

**Files:**
- Modify: `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `BalanceLineChart`, `ChartLine`, `LineStyle` (Task 5); `totalOwedSeries` (Task 3); `HiVisBlock`, `OutlinedCard` (Task 7).
- New ARB keys: `"raceTitle": "Race to zero"`, `"raceLabel": "Total owed over time for each plan. {summary}"` (placeholder `summary`), `"raceMinimums": "Minimums"`, `"following": "Following"` (unused until Plan 8; add it now), `"alternativesShow": "Show alternatives"`, `"payMoreEffect": "{months} sooner, {interest} less interest"` (placeholders String `months`, String `interest`).

- [ ] **Step 1: Add the failing tests**

```dart
testWidgets('races the pay-off methods to zero', (tester) async {
  await pumpApp(tester, location: Routes.plans, debts: twoDebts);
  expect(find.text('Race to zero'), findsOneWidget);
  final chart = tester.widget<BalanceLineChart>(find.byType(BalanceLineChart).first);
  // avalanche, snowball, your order, plus the minimums line
  expect(chart.lines.length, greaterThanOrEqualTo(4));
  expect(chart.lines.last.style, LineStyle.dashed);
});

testWidgets('borrowing alternatives are collapsed until asked for', (
  tester,
) async {
  await pumpApp(tester, location: Routes.plans, debts: twoDebts);
  expect(find.text('Consolidation loan'), findsNothing);
  await tester.scrollUntilVisible(find.text('Show alternatives'), 200);
  await tester.tap(find.text('Show alternatives'));
  await tester.pumpAndSettle();
  expect(find.text('Consolidation loan'), findsOneWidget);
});

testWidgets('the slider says what paying more changes', (tester) async {
  await pumpApp(tester, location: Routes.plans, debts: twoDebts);
  await tester.drag(find.byKey(const ValueKey('payMore')), const Offset(120, 0));
  await tester.pumpAndSettle();
  expect(find.textContaining('less interest'), findsOneWidget);
});
```

`twoDebts` is whatever the file already uses (look at its top). Use the real strategy names from `app_en.arb` in the finders. The existing tests `'separates pay-off methods from borrowing alternatives'` and `'a borrowing alternative is never marked cheapest'` must first tap "Show alternatives"; add that step and nothing else.

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/features/strategies/strategies_screen_test.dart`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement**

The `ListView` children in order:
1. The scenario picker (unchanged; hidden until something is saved).
2. **Race card:** an `OutlinedCard(title: raceTitle)` holding a `BalanceLineChart`. For each `Feasible` result that is not a borrowing alternative, in ranked order, add one line with the `i`th style: solid width 3, then dashed, then dotted, then solid (card transfers), coloured `c.series[i]`. Then add the baseline (when `Feasible`) in `c.faint`, `LineStyle.dashed`, width 2. Below it, a `Wrap` legend with a line-style swatch plus the name for each line. `semanticLabel` = `raceLabel` with a summary like "Highest interest first clears in Nov 2028; …".
3. **Pay-more** inside a `HiVisBlock`: the existing `_PayMoreSlider` content, with the slider themed (`SliderTheme`: active track `onHiVis`, inactive `onHiVis.withValues(alpha: .25)`, thumb white with a navy border via `RoundSliderThumbShape` plus an overlay). Add a line under it, `payMoreEffect`, shown when the extra is above 0. Compare the best pay-off method now with the same method at extra = 0, using a second read of `currentPlansProvider` (Task 4). That's valid only when the active scenario is Current; otherwise hide the line.
4. `_SaveAsScenarioButton` and `_BaselineLine`: unchanged, placed after the cards (spec §4.5 item 6).
5. **`_StrategyCard`:** keep all existing text lines (tests depend on them) and add:
   - a leading rank number (`displayStyle(30)`, the 1-based position among pay-off methods);
   - on the right of the stats, a `BalanceLineChart(compact: true, height: 34)` sparkline of the plan in its race colour;
   - an interest bar (6px `FractionallySizedBox` of `totalInterest / maxInterest` among the feasible pay-off methods, in `c.ink2`).

   The cheapest card no longer uses `primaryContainer`. It shows a `hiVis` "Cheapest" badge (a container with a 2px `onHiVis` border and `onHiVis` text) in place of the `Chip`. Keep the text `l10n.cheapest`.
6. **Alternatives:** an `ExpansionTile(title: alternativesHeading, subtitle: alternativesNote, initiallyExpanded: false)`. Its trailing `TextButton` reads `alternativesShow`, or the tile's own tap works; the tests tap the text "Show alternatives", so put that text in the tile's `trailing`. It holds the alternative cards.

The banner stays at the bottom (the `Scaffold.bottomNavigationBar` of this screen).

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/strategies/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(plans): race-to-zero chart, hi-vis pay-more block, sparkline cards"
```

---

### Task 10: Plan detail as one scroll

**Files:**
- Modify: `lib/features/analysis/presentation/plan_detail_screen.dart`, `lib/l10n/app_en.arb`
- Delete: `plan_summary_tab.dart`, `plan_chart_tab.dart`, `plan_schedule_tab.dart` (move any widget still needed, like the schedule `DataTable`, into `plan_detail_screen.dart` or a `plan_schedule_table.dart`)
- Test: `test/features/analysis/plan_detail_test.dart`

**Interfaces:**
- Consumes: `StackedBalanceChart`, `SegmentBar` (Task 5); `stackedBalances`, `milestones`, `moneySplit`, `firstMonthPayments`, `groupPlanDebts` (Task 3); `HiVisBlock`, `OutlinedCard` (Task 7); `debtColor` (Task 2).
- New ARB keys: `"detailStatMonths": "Months"`, `"detailStatInterest": "Interest"`, `"detailStatSaves": "Saves"`, `"detailChartTitle": "What you owe, month by month"`, `"detailChartHint": "Drag across the chart to see any month. Tap a debt to hide it."`, `"detailChartLabel": "Balance of each debt over {months} months. {order}"`, `"detailTooltip": "Month {month} · {date}\nOwed {total}"`, `"milestonesTitle": "Milestones"`, `"milestoneCleared": "{debt} cleared"`, `"milestoneRollsOn": "{amount} a month rolls onto {next}"`, `"milestoneDebtFree": "Debt free"`, `"milestoneTotalPaid": "{amount} paid in total"`, `"moneySplitTitle": "Where your {total} goes"`, `"moneySplitDebts": "Your debts {amount}"`, `"moneySplitInterest": "Interest {amount}"`, `"moneySplitFees": "Fees {amount}"`, `"scheduleShowAll": "Show all {months} months"`. Remove `tabSummary`, `tabChart`, `tabSchedule`, `chartTitle` if nothing else uses them.

- [ ] **Step 1: Rewrite the tab-based tests (failing)**

In `plan_detail_test.dart`:
- `'charts the balance over time'`: expect `find.byType(StackedBalanceChart)` with no tab tap.
- `'shows the month-by-month schedule'`: scroll to "Full schedule", then tap `scheduleShowAll`, then expect the full table rows.
- `'summarises when and how the debts are cleared'`: expect `Debt-free by`, the three stat tiles and `Milestones` with one `… cleared` per debt.

Add:

```dart
testWidgets('says where the money goes, with interest hatched', (
  tester,
) async {
  await pumpApp(tester, debts: twoDebts, location: Routes.plan(StrategyId.avalanche));
  await tester.scrollUntilVisible(find.textContaining('Where your'), 200);
  final bar = tester.widget<SegmentBar>(find.byType(SegmentBar));
  expect(bar.segments.where((s) => s.hazard), hasLength(1));
});

testWidgets('a legend chip hides a debt from the chart', (tester) async {
  await pumpApp(tester, debts: twoDebts, location: Routes.plan(StrategyId.avalanche));
  await tester.tap(find.widgetWithText(FilterChip, 'Store').first);
  await tester.pumpAndSettle();
  final chart = tester.widget<StackedBalanceChart>(find.byType(StackedBalanceChart));
  expect(chart.hidden, isNotEmpty);
});
```

(Use the debts and names this test file already defines, such as `store`/`amex` at the top.)

- [ ] **Step 2: Run them and check they fail**

Run: `flutter test test/features/analysis/plan_detail_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`_PlanTabs` becomes `_PlanPage` (a `ConsumerStatefulWidget` holding the `Set<int> hidden` of legend-chip toggles). The `Scaffold` keeps the app bar: title, the nickname/scenario/extra subtitle lines as now, and the share `PopupMenuButton`, unchanged. There's no `TabBar`. The body is a `ListView` with 16px padding and 14px gaps:
1. **`HiVisBlock`:**
   - "Debt-free by", then `DateFormat.yMMMM` in `displayStyle(44)`;
   - a 3-column `GridView.count(shrinkWrap, physics: NeverScrollable, crossAxisCount: 3)` of white stat tiles (2px `onHiVis` border): months, total interest, and saves against minimums (`savingsAgainst(plan, baseline)?.money`; the tile is hidden when null);
   - the Follow button arrives in Plan 8, so there's none here.
2. **Chart:** an `OutlinedCard(title: detailChartTitle)` holding a `StackedBalanceChart`:
   - `stacks: stackedBalances(plan)`;
   - `colors`: per plan column, `debtColor(c, d.id, listOrderIds)`, so portions share their card's colour;
   - `names`: `planDebtName`;
   - `hidden`, and `tooltipTitle` from `detailTooltip`.

   Under it, a `Wrap` of `FilterChip(selected: !hidden.contains(g), label: name, avatar: a colour square)`, one per `groupPlanDebts` group; toggling adds or removes all of that group's columns. Then `detailChartHint`.
3. **Milestones:** an `OutlinedCard(title: milestonesTitle)`. One row per `milestones(...)`:
   - a 34px colour square with the type icon and a 2px connecting line;
   - the date line `"{MMM yyyy} · month {n}"`;
   - `milestoneCleared(name)`;
   - `milestoneRollsOn(amount, next)` when `next != null`.

   The final row has a hi-vis square with a check, `milestoneDebtFree` in `displayStyle(20)`, and `milestoneTotalPaid`.
4. **What changes** (existing block, in an `OutlinedCard`, only when `plan.change != null`).
5. **Where the money goes:** an `OutlinedCard(title: moneySplitTitle(total))` holding a `SegmentBar(height: 30)`:
   - `[Segment(principal, c.ink2), Segment(interest, c.ink, hazard: true)]`;
   - plus `Segment(fees, c.today)` when fees are positive.

   Below it, key rows with the amounts (`moneySplitDebts`/`Interest`/`Fees`).
6. **Pay this month:** an `OutlinedCard(title: payThisMonth)` with rows for `firstMonthPayments`: the name, a 10px bar (`amount / max`) in the debt's colour, and the amount.
7. **Full schedule:** `ExpansionTile(title: Text(l10n.fullSchedule))`, with a new key `"fullSchedule": "Full schedule"`. It shows the first 3 rows of the existing schedule table inside a horizontal `SingleChildScrollView`, plus a `TextButton(scheduleShowAll(n))` that expands the rest in place (a `bool _showAll`).

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/analysis/`
Expected: PASS, including the existing export, infeasible, card-move and scenario tests (their text doesn't change).

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(plan-detail): one scroll — hero, scrubbable chart, milestones, money split"
```

---

### Task 11: Scenarios Compare bars

**Files:**
- Modify: `lib/features/scenarios/presentation/scenarios_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/scenarios/scenarios_screen_test.dart`

**Interfaces:**
- Consumes: `ComparisonBars` (Task 5), `scenarioComparisonProvider` (existing).
- New ARB keys: `"compareChartTitle": "Interest paid, best plan in each"`, `"compareChartLabel": "Interest in each scenario's best plan. {summary}"`, `"scenariosEmptyHint"`: keep the existing `scenariosEmpty` copy.

- [ ] **Step 1: Failing test**

```dart
testWidgets('compares scenarios as bars', (tester) async {
  await pumpApp(tester, location: Routes.scenarios, debts: debts, scenarios: saved);
  await tester.tap(find.text('Compare'));
  await tester.pumpAndSettle();
  final bars = tester.widget<ComparisonBars>(find.byType(ComparisonBars));
  expect(bars.bars.length, saved.length + 1); // plus Current
  expect(bars.bars.where((b) => b.highlight), hasLength(1));
});
```

(Use the `debts` and `saved` fixtures this file already defines; check the tab label string in the ARB.)

- [ ] **Step 2: Run it and check it fails.** Run: `flutter test test/features/scenarios/scenarios_screen_test.dart`

- [ ] **Step 3: Implement.** In `_CompareList`, put an `OutlinedCard(title: compareChartTitle)` above the existing rows (keep the rows). It holds `ComparisonBars` with:
  - `label`: the name, or `scenarioCurrent`;
  - `value`: best interest in major units (0 when no plan);
  - `trailing`: the debt-free month `DateFormat.yMMM`, or `compareNoPlan`;
  - `highlight`: the cheapest.

  `semanticLabel` joins "name: interest, date" for each bar. Also restyle the cheapest row: no `primaryContainer`; use the hi-vis badge from Task 9, and extract it to `lib/core/widgets/cheapest_badge.dart` if it's still private.

- [ ] **Step 4: Run it.** Run: `flutter test test/features/scenarios/` and expect PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(scenarios): compare scenarios as a bar chart"
```

---

### Task 12: Ads check, docs and full verification

**Files:**
- Modify: `test/features/ads/ad_placement_test.dart`, `CLAUDE.md`, `docs/release.md`

- [ ] **Step 1: Update and extend the ad placement tests (failing first)**

- In `'banners appear on debts and strategies once allowed'`, rename "strategies" to "plans" and go to `Routes.plans`.
- In `'no banners on forms, plan detail, settings or onboarding'`, add `Routes.home` and `Routes.scenarios` to the list.

Add:

```dart
testWidgets('the banner sits above the bottom nav', (tester) async {
  final ads = FakeAdsService(canShowAds: true);
  await open(tester, ads);
  final banner = tester.getRect(find.text('Ad banner'));
  final nav = tester.getRect(find.byType(NavigationBar));
  expect(banner.bottom, lessThanOrEqualTo(nav.top));
});
```

Run: `flutter test test/features/ads/`
Expected: PASS once the Home and Scenarios expectations hold (they should, since neither has a banner). If `'the banner sits above the bottom nav'` fails, the Debts/Plans banner must move into the screen's own `Scaffold.bottomNavigationBar` (not the shell's).

- [ ] **Step 2: Docs**

- **`CLAUDE.md`:**
  - Tick a new checklist line, `- [x] Plan 7: v3 shell and charts (three tabs, Direction A theme, chart kit) (docs/superpowers/plans/2026-09-25-plan-7-shell-and-charts.md)`.
  - Update the gotchas: routes are now `Routes.home/debts/plans/…` under a `StatefulShellRoute`; the debt form, settings and onboarding use the root navigator.
  - Say charts take view data from `plan_series.dart`, and debt colours come from `debtColor` (list order, portions merged).
  - `pumpApp` still opens Debts by default.
  - Home uses `homePlanProvider` (Current settings, no slider).
- **`docs/release.md`:** add a step to the AdMob set-up: "In AdMob → Blocking controls, block the sensitive categories *Gambling & betting* and the *Payday loans / high-interest lending* (and similar get-rich or debt-relief schemes) for every ad unit."

- [ ] **Step 3: Full verification**

```bash
./tool/codegen.sh
dart format lib test
dart analyze --fatal-infos
flutter test
(cd packages/payoff_engine && dart test)
```

Expected: all clean and all passing. Then run `flutter run --flavor dev` on a simulator (use the `run` skill). Screenshot Home, Debts, Plans and Plan detail in light and dark, and compare them with the canvas page "A · Demolition crew". Fix any visible mismatch in spacing, fonts or colours before committing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(ads): banners only on Debts and Plans, above the nav; docs for Plan 7"
```
