# Plan 10: Illustrations and Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholders with Direction A's in-house illustrations, drawn as themeable, animatable `CustomPainter`s:
- the Home brick wall, which loses bricks as you pay;
- welcome pages and setup art;
- empty states;
- the check-in result;
- the wrecking-ball celebration and the debt-free scene;
- picture tiles for debt types.

Add the few purposeful animations the spec names. When reduced motion is on, only the final frame is shown.

**Architecture:**
- **Painters:** `lib/core/illustrations/` holds small painters built from shared parts: `BrickPainter` helpers, a wrecking ball, a flag and the ground line. They all use the fixed Direction A inks (navy `#14213D`, hi-vis `#FFC400`, white). The only thing they take from the theme is the surface colour behind them.
- **Placement:** each illustration is a `StatelessWidget` or `StatefulWidget` wrapping a `CustomPaint` with a `progress` (0–1) parameter. That way one painter draws any frame of its animation, and tests can paint a single frame.
- **Timing:** animations are driven by `AnimationController`s in the widgets. `MediaQuery.disableAnimationsOf(context)` jumps straight to `progress = 1`.
- **Pure maths:** everything numeric is a pure, tested function (bricks knocked out for a percentage, which bricks drop, the count-up values).

**Tech Stack:** Flutter `CustomPainter`, `AnimationController`, `PageView`. There are no new dependencies (no SVG, no Lottie).

**Spec:** `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md`: §5.2 (all), §4.1 (the welcome pages), §4.4 (the debt-type tile grid), §4.2 (the Home hero wall), §4.9 (the check-in result illustration), §4.10 (celebration and debt-free). Designs: canvas page "A · Demolition crew" (Welcome, Home, Check-in result, Debt cleared) and "A · Debt cleared".

## Global Constraints

- **Ink:** navy `#14213D` outlines at 2 logical px, hi-vis `#FFC400` as the only highlight, flat fills, no gradients or shadows.
- **Semantics:** every illustration is decorative (`ExcludeSemantics`) unless it carries information; the Home wall's paid-off share is already announced by the ring.
- **Motion:**
  - One orchestrated moment per screen, lasting under 1.2 s.
  - Nothing loops forever.
  - With `MediaQuery.disableAnimationsOf(context)`, show the final frame immediately.
  - Charts draw left to right once, on first view only.
- **Tests:**
  - Widget tests paint each illustration (no exceptions) at progress 0, 0.5 and 1, in light and dark.
  - Tests with reduced motion (`MediaQueryData(disableAnimations: true)`) see the final frame after a single `pump`.
  - Pure maths gets unit tests.
- **Process:**
  - TDD.
  - `dart analyze --fatal-infos` and `dart format` clean.
  - Commit trailer:
    ```
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
    ```

## Review Focus

1. **Reduced motion:** every animated widget shows its final frame at once, and `pumpAndSettle` never times out, because there are no repeating animations. Test: every task.
2. **Size extremes:** painters must stay inside their box, never overflow or divide by zero, at tiny (40×40) and huge (800×600) sizes and at a 2.0 text scale where they sit beside text. Test: Task 1.
3. **The wall at 0% and 100%:** 0% has no bricks missing; 100% has all of them gone, and doesn't crash with an empty wall. Test: Task 2.
4. **Replays:** the celebration animation runs once per screen, not again on a rebuild (for example, a theme change). Test: Task 6.
5. **Onboarding:** swiping, Skip, and the page dots with TalkBack/VoiceOver labels; the existing setup tests still pass behind the new pages. Test: Task 4.

---

### Task 1: Illustration kit

**Files:**
- Create: `lib/core/illustrations/kit.dart` (colours, `drawBrick(Canvas, Rect, {Color fill, double turn})`, `drawGround`, `drawBall`, `drawFlag`)
- Create: `lib/core/illustrations/illustration.dart` (`Illustration` widget: a fixed aspect ratio, `ExcludeSemantics`, `CustomPaint` sized to its constraints)
- Test: `test/core/illustrations_test.dart`

**Interfaces:**
- `const kInk = Color(0xFF14213D)`, `kHiVis`, `kBrickFill = Color(0xFFE3E6EB)`.
- `class Illustration extends StatelessWidget { const Illustration({required this.painter, this.aspectRatio = 1.6, this.semanticLabel}); }`: wraps it in `Semantics(label:)` when a label is given, and in `ExcludeSemantics` otherwise.

- [ ] **Test:** an `Illustration` with a test painter paints inside 40×40 and 800×600 boxes without exceptions, and has no semantics node unless labelled.
- [ ] **Implement, run and commit:** `feat(illustrations): shared kit — bricks, ball, flag, ground`.

### Task 2: The Home brick wall

**Files:** `lib/core/illustrations/brick_wall.dart`, `lib/features/home/presentation/home_screen.dart` (the hero keeps the ring and adds the wall on the right, as in the canvas, when the hero is at least 340 logical px wide), test `test/core/illustrations/brick_wall_test.dart`

**Interfaces:**
- `List<(int row, int col)> knockedOut(int percent, {int rows = 5, int cols = 6})`: which bricks are gone, taken from the top right and working down and left.
  - `percent` is clamped to 0–100.
  - Count = `(rows × cols × percent / 100).round()`.
  - Deterministic.
- `BrickWall({required int percent, double progress = 1})`: paints the wall with those bricks missing, plus two tumbling hi-vis bricks when `percent > 0`. `progress` animates the latest bricks falling (used after a check-in).

- [ ] **Tests:**
  - `knockedOut(0)` is empty.
  - `knockedOut(100)` has all 30.
  - `knockedOut(11)` has 3, and they are the top-right ones.
  - Painting at 0, 50 and 100 has no exceptions.
  - Home shows `BrickWall` in the hero at phone width.
  - Large text at phone width: no overflow. The wall hides below 340 logical px of hero width.
- [ ] **Commit:** `feat(home): brick wall that loses bricks as you pay`.

### Task 3: Debt-type picture tiles

**Files:** `lib/features/debts/presentation/debt_type_tiles.dart`, `debt_form_screen.dart` (replace the type dropdown), test `test/features/debts/debt_form_test.dart`

**Behaviour** (spec §4.4, lo-fi board "5 · Add / edit debt"):
- A 4×2 grid of tiles, one per `DebtType`. Each has its glyph on a rounded square and the label (`debtTypeLabel`).
- The selected tile is filled `ink` with white text, and the others are outlined.
- Tiles are `Semantics(button: true, selected: …, label: …)`, at least 48 dp tall, and wrap to 2 columns below 360 logical px.
- The glyphs come from `debtTypeIcon`, keeping the icons already used on Debts rows, so a debt's picture is the same everywhere.

- [ ] **Tests:**
  - Update the existing form tests that choose a type through the dropdown (`find.byKey(ValueKey('type'))`) to tap the tile instead. Keep `ValueKey('type-<name>')` on each tile.
  - The selected tile has `selected` semantics.
  - At phone width with 2.0 text: no overflow.
- [ ] **Commit:** `feat(debts): pick the kind of debt from picture tiles`.

### Task 4: Welcome pages and setup art

**Files:** `lib/core/illustrations/welcome_art.dart` (three painters: `TangleToPath`, `HighestRateFirst`, `PaymentsRollOn`; plus `SetupArt`), `lib/features/onboarding/presentation/onboarding_screen.dart`, `lib/l10n/app_en.arb`, test `test/features/onboarding/onboarding_screen_test.dart`

**Behaviour** (spec §4.1, canvas "Welcome"):
- The onboarding screen becomes a `PageView` of four pages.
- **Pages 1–3 (welcome):**
  - An `Illustration` on a hi-vis panel.
  - A headline in `displayStyle(42)`: `welcomeTitle1–3` = "Knock down your debt, brick by brick", "Highest rate first", "Payments roll on".
  - A body: the existing `onboardingIntro1–3`.
  - Page dots with semantics "Page {n} of 3".
  - A "Next" `FilledButton`, and "Skip" in the app bar, which jumps to setup.
- **Page 4 (setup):** today's form with `SetupArt` above it. Its buttons are unchanged ("Add my first debt" / "I'll do it later").
- Returning users never see onboarding (the redirect is unchanged).

- [ ] **Tests:**
  - The first page shows `welcomeTitle1`.
  - "Next" twice then shows page 3.
  - "Skip" reaches setup.
  - Swiping works.
  - Existing setup tests: add an `openSetup(tester)` helper that taps Skip first.
  - Large text at phone width: no overflow on any page.
- [ ] **Commit:** `feat(onboarding): illustrated welcome pages`.

### Task 5: Empty states and the check-in result art

**Files:** `lib/core/illustrations/scenes.dart` (`EmptyLot` for no debts, `Signpost` for no scenarios, `ClimbWall` for the check-in result, `ClearedPlot` for debt free), and use them in:
- Home `HomeNoDebts` (above the message);
- Debts empty (above `debtsEmpty`);
- Plans empty (`strategiesEmpty`);
- Scenarios Saved empty (`scenariosEmpty`);
- the check-in result (beside the headline, replacing nothing);
- Home `HomeAllCleared`.

Tests: widget tests find the illustration in each state.

**Motion on the check-in result** (spec §5.2): the headline amount counts up from 0 over 800 ms, and bricks drop out of the `ClimbWall` in step. Show the final value at once with reduced motion.
- Pure: `List<double> countUp(double target, int frames)` isn't needed; use a `TweenAnimationBuilder<double>` with the final text formatted with `formatMoney` at the end.
- Test: under reduced motion, the exact final amount text shows after one pump. With animations on, after `pumpAndSettle`, the final text shows.

- [ ] **Commit:** `feat(illustrations): empty states and check-in result, with count-up`.

### Task 6: Celebration and debt-free motion

**Files:** `lib/core/illustrations/wrecking_ball.dart` (`WreckingBallScene(progress)`: the ball swings in from the left over 0–0.5, bricks scatter over 0.4–0.9, and the ground settles), `lib/features/progress/presentation/celebration_screen.dart` (replace `_BricksPainter`; the headline "slams in", scaling from 1.3 to 1.0 with a fade over the last 30% of the timeline), `DebtFreeScene` (a flag rises on a cleared plot), tests `test/features/progress/celebration_screen_test.dart`

**Behaviour:**
- **The celebration:** a single `AnimationController` (1100 ms, `forward()` once in `initState`) drives the scene and the headline. It doesn't restart on rebuild (the state is kept). With reduced motion, `value = 1` at once. Keep going and Share are enabled immediately.
- **Debt-free:** the flag rises over 900 ms, the same way.

- [ ] **Tests:**
  - After one pump under reduced motion, the scene's progress is 1 and the title is at full scale.
  - With animations on, `pumpAndSettle` completes.
  - Rebuilding (a `setState` in a parent, or a theme change through `platformBrightnessTestValue`) doesn't reset the controller (the progress stays at 1).
  - The existing celebration tests pass.
- [ ] **Commit:** `feat(progress): wrecking-ball celebration and debt-free scenes`.

### Task 7: Charts draw in once

**Files:** `lib/core/charts/balance_line_chart.dart`, `stacked_balance_chart.dart` (wrap each in a `ClipRect` reveal driven by a one-shot `AnimationController` (600 ms, left to right) that runs on first build only, and not on data changes, which `fl_chart` already animates). Reduced motion shows everything at once.

- [ ] **Tests:**
  - The reveal widget's factor starts at 0 and reaches 1 after `pumpAndSettle`.
  - Under reduced motion it's 1 after one pump.
  - Updating the data doesn't replay the reveal.
- [ ] **Commit:** `feat(charts): draw in once, left to right`.

### Task 8: Docs and verification

- [ ] **`CLAUDE.md`:**
  - Tick Plan 10 and the v3 migration.
  - Gotcha: illustrations are `CustomPainter`s under `lib/core/illustrations/`, animated through a `progress` value, with reduced motion meaning `progress = 1`.
- [ ] **Full verification:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`, plus `flutter build apk --flavor dev --debug`.
- [ ] **Simulator screenshots:** Welcome (fresh install), Home with the wall, the debt form tiles, Plans empty and Debts empty (fresh install, "I'll do it later"). Compare them with the canvas.
- [ ] **Commit:** `docs: Plan 10 illustrations and motion; v3 complete`.
