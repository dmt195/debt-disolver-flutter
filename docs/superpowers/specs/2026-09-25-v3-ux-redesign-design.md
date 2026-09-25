# Debt Destroyer v3: Engaging UX, Progress and Reminders, Design

Date: 2026-09-25
Status: Draft for review
Builds on: the v1 spec (`2026-09-24-flutter-rebuild-design.md`), the v2 spec (`2026-09-24-v2-planning-design.md`) and the card-transfers spec (`2026-09-25-card-transfers-design.md`). Where this spec says nothing, they still apply.
Wireframes (lo-fi, agreed): https://claude.ai/artifact/V7Fq1gxCxmMd7J2RT2Gv4b

## 1. Intent

The app works, but it reads like a form and a spreadsheet. The one chart is hidden behind a tab, two taps deep. v3 makes the app **visual and motivating**:
- Charts sit on every main screen.
- Flat vector illustrations give the app a personality.
- People can **track their progress** against their plan, be **reminded** what to pay each month, and **celebrate** each debt they clear.

**In scope**
- New navigation: a bottom nav with three tabs (Home, Debts, Plans), replacing the chain of pushed screens.
- A new Home tab: the debt-free date, progress, a chart of the plan against actual balances, the next milestone, and what to pay this month.
- Chart-first redesigns of Debts, Plans (renamed from Strategies), Plan detail and Scenarios Compare.
- Illustrated onboarding (three pages plus setup), debt-type avatars, empty states, and celebration art.
- Progress tracking: a "followed" plan, check-ins that record balances, a starting point, ahead/behind, and cleared debts.
- A celebration screen when a debt is cleared (and when every debt is).
- Local notifications: a monthly pay-day reminder and an optional check-in nudge.

**Out of scope**
- Logging individual payments or transactions (a check-in records balances, not payments).
- Bank connections, sync, accounts, anything server-side (every notification is local).
- Changes to `payoff_engine` (v3 is app-only; §9 lists what the engine already provides).
- New strategies, lump sums, budgets that change over time.
- Any ad format other than the existing banner. There are no interstitial, native or rewarded ads.
- Themes other than Direction A's light and dark (§5).

**Unchanged constraints:** local-only data, integer money (minor units, basis points, half-even), a pure-Dart engine, TDD, the `AdsService` and consent flow, and borrowing alternatives that are never marked cheapest.

**Success criteria**
- From a cold start, the debt-free date and a chart are visible with no taps (Home).
- A user can check in in under 30 seconds with nothing to change: the check-in screen is pre-filled.
- Every chart has a text summary for screen readers (§8.3).
- v2 users upgrade with debts, settings and scenarios intact. Their first launch records a starting point (§6.3).

## 2. Decisions taken in review

| Question | Decision |
|---|---|
| Navigation | Bottom nav: Home · Debts · Plans. Settings behind a gear icon in every tab's app bar. |
| Naming | "Plans" replaces "Strategies" in the UI. Code names (`StrategyId`, `strategies/` feature folder) stay. |
| Imagery | Direction A ("Demolition crew"): geometric flat illustrations drawn in-house as animated `CustomPainter`s. No photos, no Lottie (§5). |
| Ads | Bottom-anchored banner on **Debts and Plans only**. No ads on Home, detail screens, check-in, onboarding, celebrations or Scenarios. Never between list items. |
| Progress | A "Check in now" action whenever the user likes, plus an optional monthly pay-day reminder and a check-in nudge. |
| Ahead / behind | Measured against the followed plan as it stood at the **latest starting point** (§6.3). |
| Changes of tack | Switching plan, or adding or deleting a debt, records a new starting point and **keeps all history**. The chart projects forwards from the change, keeps the **original projection** as a faint reference line, and marks the change on the timeline (§6.7). |
| Restart | **Restart from here** is a separate, deliberate fresh start ("too much noise", "it hasn't gone well so far"). By default it **clears the progress history**; the user can choose to keep it instead (§6.8). |
| Reminder settings | A Reminders section in the existing Settings screen, not a new page: turn reminders on or off, change the day, or turn them on later after skipping them in setup (§4.11). |

## 3. Navigation

`go_router` `StatefulShellRoute.indexedStack` with three branches. Each tab keeps its own stack and scroll position.

| Route | Screen | Shell |
|---|---|---|
| `/` | Home | tab 1 |
| `/debts` | Debts | tab 2 |
| `/debts/new`, `/debts/:debtId` | Debt form | tab 2 (nav hidden) |
| `/plans` | Plans | tab 3 |
| `/plans/:strategyId` | Plan detail | tab 3 |
| `/plans/scenarios`, `/plans/scenarios/:scenarioId` | Scenarios, scenario form | tab 3 |
| `/settings` | Settings | root (full screen) |
| `/check-in` | Check in | root (full screen) |
| `/check-in/result` | Check-in result | root |
| `/cleared/:debtId`, `/debt-free` | Celebration | root (full-screen dialog) |
| `/onboarding` | Welcome pages plus setup | root; the existing redirect rules stay |

- `Routes` constants change to match. `/strategies/...` paths are removed (there are no external links to keep).
- The debt form and anything pushed from it hide the nav bar (a focused task). Plan detail and Scenarios keep it.
- A notification tap opens `/check-in` (§7). If onboarding isn't complete, the existing redirect wins.

## 4. Screens

Figures and copy in the wireframes are illustrative. All text goes in `app_en.arb`, and all money and percentages go through `money_format.dart`.

### 4.1 Onboarding
1. **Welcome, three swipeable pages**, each with an illustration, a headline and one sentence. The copy reuses `onboardingIntro1–3`, with new headlines ("See your way out", "Highest rate first", "Payments roll on"). A page indicator, Next, and Skip (which goes to setup).
2. **Set up:** currency, monthly budget (as now), and the **pay-day reminder** switch plus day of the month (default: on, the 28th). Turning the switch on requests notification permission at that moment. If permission is refused, the switch turns back off with a one-line explanation.
3. The primary button, **"Add my first debt"**, completes onboarding and opens the debt form. **"I'll do it later"** completes onboarding and goes Home.

### 4.2 Home (new)
From top to bottom:
1. **Hero card:**
   - A progress ring (percentage paid off, §6.4).
   - "Debt-free by {month year}".
   - "£X paid off since {start month}".
   - An ahead/behind chip: "1 month ahead", "£110 ahead", "On track" or "£80 behind" (§6.5).
   - Before the first check-in after a starting point, the chip reads "Check in to track progress".
2. **Plan vs actual chart** (§6.7):
   - The check-in totals as a solid line with square markers, from the first starting point to today.
   - The current projection (from the latest starting point forwards), drawn dashed.
   - The original projection (from the first starting point), drawn as a faint dotted reference line. It's hidden while there is only one starting point.
   - A small tick on the time axis at each change of tack or kept-history restart, labelled on touch ("Switched to Snowball", "Added Visa", "Restarted").
   - A "today" marker, and circles where each debt is cleared in the current projection.
   - The followed plan's name (a tap on the name switches plans, §6.2).
   - Tapping the chart opens that plan's detail.
3. **Check-in card:** "Last check-in {date}" and a **Check in now** button. Beneath it, a quieter **Restart from here** text button, which opens the restart sheet (§6.8).
4. **Next milestone:** the next debt the plan clears, its avatar, its date, a progress bar (that debt's paid-off fraction since the latest starting point) and "then £X/mo rolls onto {next debt}". Tapping it opens plan detail, scrolled to Milestones.
5. **Pay this month:** each debt's payment in the followed plan's current month, the total, and "due {day}" when the reminder is on.

States:
- **No debts:** an illustration plus "Add your first debt" (opens the debt form).
- **Plan infeasible** (the budget is less than the minimums): the shortfall card that Debts shows today, with a "Change budget" button, in place of 1, 2 and 4.
- **All debts cleared:** the debt-free illustration, the total paid off, and an "Add a debt" link.

Home always uses **Current** settings (not a saved scenario) and ignores the Plans pay-more slider. Both of those are what-ifs.

### 4.3 Debts
- **Summary card:**
  - A donut chart of balances by debt, with the total in the middle.
  - Minimums and budget.
  - A **budget bar**: the minimums against the extra, labelled "£X extra goes to work each month".
  - A shortfall turns the bar red and shows the existing shortfall message and button.
- **Debt rows:**
  - A type avatar (§5.2), name, balance and a rate "heat" chip (High ≥ 20%, Med ≥ 10%, Low below that; APR in basis points).
  - A thin bar showing the debt's share of the total.
  - "{APR} · min £X" and "clears {nth}" (its position in the followed plan's payoff order).
  - Swipe to delete and drag to reorder stay as they are.
- **Cleared section** (collapsed): debts marked cleared, each with its cleared date. They can be deleted, or reopened by editing the balance.
- Add debt and **See plans** (which switches to the Plans tab) sit above the banner, as now.
- **Banner:** anchored at the bottom, above the nav bar.

### 4.4 Debt form
- The debt-type dropdown becomes a **grid of illustrated tiles** (4 × 2). The rest of the form is unchanged from v2 and card transfers.
- An existing, uncleared debt gains a **"Mark as paid off"** action (the same effect as a check-in with £0, §6.6).

### 4.5 Plans (was Strategies)
1. The scenario picker (unchanged behaviour).
2. **Race-to-zero chart:** the total balance over time for each pay-off method (avalanche, snowball, your order, card transfers when applicable), plus minimums-only as a dashed grey line.
   - Each line ends with a dot and its debt-free month.
   - A legend with line-style keys, so the lines are told apart by more than colour.
   - Borrowing alternatives aren't drawn. They keep their own section below.
3. **Pay-more slider** (unchanged logic). A live line shows "{n} months sooner · £X less interest" against the slider at £0, and the chart redraws when a value is committed (the existing 250 ms debounce).
4. **Plan cards:**
   - A rank, name and nickname, a **sparkline** of the total balance, "Debt-free {month}" and "Interest £X".
   - An **interest bar** scaled to the most expensive feasible plan.
   - The **Cheapest** chip as now, plus a **Following** chip on the followed plan.
   - The savings line, transfer notes and the not-applicable, infeasible and never-clears states stay as they are.
5. **Borrowing alternatives**, in their own section, collapsed by default, with the existing caveat.
6. The minimums-only baseline line stays, below the cards.
7. "Save as scenario" is unchanged.
8. **Banner:** anchored at the bottom, above the nav bar.

### 4.6 Plan detail
The Summary / Chart / Schedule tabs are replaced by **one scrolling page**:
1. **Header:**
   - Nickname and scenario line (as now).
   - "Debt-free {month year}".
   - Three stat tiles: months, interest, and saved against minimums.
   - A **Follow this plan** button (hidden when this is already the followed plan, or when a saved scenario is active, or for minimums-only). Following asks for confirmation inside the page ("Your history stays. We'll project from today with this plan.") and records a `planSwitched` starting point (§6.3).
2. **Stacked area chart** of balances by debt (today's chart), now **touchable**: dragging scrubs a vertical line with a tooltip showing month, date, total owed and each debt's balance. Legend chips toggle a debt's band on or off.
3. **Milestones:** a vertical timeline, one row per debt in clearing order. Each row has the month and date, the avatar, "{debt} cleared" and "£X/mo rolls onto {next}". The last row is "Debt free".
4. **What changes** (transfer and consolidation plans; as now).
5. **Where your money goes:** one horizontal bar split into principal, interest and fees (fees only when there are any), with amounts.
6. **Pay this month:** each debt's payment with a small bar.
7. **Full schedule:** collapsed. It shows the first three rows and "Show all {n} months", which expands the existing table inside a horizontal scroller.

Export (CSV and XLSX) stays in the app bar's share menu. No ads.

### 4.7 Scenarios
- Saved tab: unchanged, plus an **illustrated empty state**.
- Compare tab:
  - A **horizontal bar chart** of each scenario's best-plan interest, labelled with its debt-free date, with the cheapest marked.
  - Below it, a small race-to-zero chart of each scenario's best plan.
- No ads.

### 4.8 Check in (new)
- The intro line "How much do you owe today? We've filled in what the plan expected."
- One card per **uncleared** debt: avatar, name, "plan: £X" (the expected balance, §6.5), and an amount field pre-filled with that expected balance.
- Entering **0** marks the debt cleared (a "Paid off" chip appears). A value above the previous balance shows a gentle note ("£70 more than expected. New spending?").
- A "+ A new debt since last time?" link opens the debt form. Saving that debt records a `debtAdded` starting point (§6.3).
- **Save check-in** is validated like the debt form's balance field (a positive amount or 0, and no more than `kMaxAmountMinor`).

### 4.9 Check-in result (new)
- An illustration.
- The headline: "You're £X ahead of plan", "Right on track" or "You're £X behind plan". The sub-line gives the change in debt-free date ("Nov 2028 → Oct 2028") when there is one.
- A plan vs actual chart (as on Home).
- Notes: balances that went up.
- **Continue:** if any debt was cleared by this check-in, it opens the celebration for each one in turn (then debt-free, if all are cleared); otherwise it goes Home.

### 4.10 Celebration (new)
A full-screen dialog:
- The animated wrecking-ball illustration (§5.2), on a `hiVis` ground.
- "{Debt} destroyed!" and "That's £X gone. Its £Y a month now rolls onto {next debt}" (from the followed plan).
- "{k} of {n} debts cleared".
- **Share** (a plain-text message through `share_plus`; no image in v3) and **Keep going**.
- **Debt free** variant: shown when the last debt is cleared, with the total paid off since the first starting point and the months taken.

It is shown only once per debt, recorded by the debt's `clearedAt`.

### 4.11 Settings
Settings gains a **Reminders** section:
- The pay-day reminder switch and its day (1–28, plus "Last day").
- The check-in nudge: Off, or every 1, 2 or 3 months (default 2).

The rest is unchanged.

## 5. Visual language: Direction A, "Demolition crew"

Chosen in the hi-fi pass (canvas page "A · Demolition crew"). The debt is a brick wall, and every payment knocks bricks out of it. The look is loud where it celebrates and calm everywhere else.

### 5.1 Theme tokens
Material 3 with a hand-built `ColorScheme`, plus a `ThemeExtension` (`DestroyerColors`) for what M3 has no slot for.

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | `#14213D` | `#EEF1F6` | Text, 2px outlines, the navy CTA (light) |
| `ink2` | `#4A5568` | `#A9B4C7` | Secondary text, neutral bars |
| `ground` | `#F3F4F6` | `#0E1628` | Scaffold background |
| `surface` | `#FFFFFF` | `#17223A` | Cards and sheets |
| `outline` | `#14213D` | `#3A4B6E` | Card borders (2px) |
| `track` | `#E6E8EC` | `#24314D` | Empty bar tracks, the ad slot |
| `hiVis` | `#FFC400` | `#FFC400` | One hero block per screen, the slider block, the Cheapest badge, the celebration ground. Always with `#14213D` text; never used as a text colour |
| `navBar` | `#14213D` | `#0A1120` | Bottom nav (active item is `hiVis`) |
| `primary` button | `#14213D` on white text | `#FFC400` with `#14213D` text | Main action |

- **Shape:** 2px outlines, 6px corners on cards and buttons, 4px on chips. No shadows or elevation tints.
- **Hazard stripes** (a −45° repeating `hiVis`/navy pattern) mean only "still to knock down": milestone progress, and the interest share of "where your money goes".
- **Type:** Bricolage Grotesque ExtraBold (800) for headings and big numbers, with tight negative tracking at display sizes. Atkinson Hyperlegible (400/700) for everything else, with tabular figures for amounts. Both are bundled under `assets/fonts/` (OFL); there's no runtime font fetching.
- **Debt colours:** a fixed categorical palette of 6. A debt keeps one colour everywhere, taken from its index in the user's list order, modulo 6. Both sets pass the colour-blindness check (lightness band, chroma, adjacent-pair separation for colour-blind and normal vision, and 3:1 contrast against the surface):
  - Light: `#1F4FD1 #D9590B #0F9D7A #7A5AF8 #C23B8A #A87A00`
  - Dark: `#4F83F5 #E0661A #16A080 #8E78F5 #DE559F #B08A00`
- **Chart chrome:**
  - The actual line is `series[0]`-blue at 3px, with square markers.
  - The plan line is `ink`, dashed 6/5.
  - The original projection is a faint dotted grey (`#9AA3B2` light, `#5E6C88` dark).
  - The "today" line is `#D9590B` (light) or `#E0661A` (dark).
  - Grid lines are `track`, with a single baseline in `ink`.
  - Series are also told apart by line style (solid, dashed, dotted), never by colour alone.

### 5.2 Illustrations and motion
- **Drawing:** illustrations are drawn **in-house** in the same geometric style (2px navy outlines, flat fills, `hiVis` as the only highlight): bricks, walls, a wrecking ball, a cleared plot for "debt free". That settles the question of where they come from: nothing is commissioned or licensed.
- **Code:** they are `CustomPainter`s under `lib/core/illustrations/`, not SVG assets, so they can be animated and themed. There's no `flutter_svg`.
- **The set:**
  - Welcome × 3 and setup.
  - The Home hero wall (its knocked-out bricks track the percentage paid off).
  - Empty states for Home, Debts, Plans and Scenarios.
  - Check-in result.
  - Debt cleared and debt free.
  - The eight debt-type glyphs (drawn as icons on a square filled with the debt's colour).
- **Motion** uses Flutter animations, not Lottie (no `lottie` dependency):
  - **Debt cleared:** the ball swings, bricks scatter, then the headline slams in.
  - **Check-in result:** bricks drop out one at a time while the amount counts up.
  - **Charts:** each draws left to right once, on first view.
  - With `MediaQuery.disableAnimations` on, only the final frame is shown.

### 5.3 Charts
All charts use `fl_chart`, with one shared widget per kind under `lib/core/charts/`:
- `BalanceLineChart`: plan vs actual, race-to-zero and sparklines.
- `StackedBalanceChart`: plan detail.
- `ShareDonut`: debts.
- `SegmentBar`: budget bar and where your money goes.
- `ComparisonBars`: scenarios.

Each chart takes pure view data built by a tested function in the feature's `domain/` (like `stackedBalances` today), so the maths is unit-tested and the widget only draws. Each chart wraps itself in `Semantics(label: …)` with a one-sentence summary (§8.3).

## 6. Progress tracking

### 6.1 Concepts
- **Followed plan:** the strategy the user is working to. Home, reminders, check-in expectations and milestones all use it.
- **Starting point:** a dated record of every uncleared debt's balance, the followed plan, why it was recorded, and that plan's **projected total balance for each month** from then on. Starting points form a timeline. The **latest** is the reference for ahead/behind and the forward projection. The **first** is the original projection, kept as a reference.
- **Check-in:** a dated record of every uncleared debt's balance at that time. Saving one also updates each `Debt.balance`.
- **Cleared debt:** a debt whose balance reached 0 through a check-in or "Mark as paid off". It keeps its row, with `clearedAt` set. The engine never sees it.

### 6.2 Followed plan
- Stored in `AppSettings.followedStrategy` (`StrategyId?`).
- When it is null, the app uses `bestPayOffMethod(ranked)` (the cheapest pay-off method; never a borrowing alternative or minimums-only), and saves that choice at the first starting point.
- The user switches plans from Plan detail ("Follow this plan") or from Home's plan name (a sheet listing the pay-off methods). Borrowing alternatives can be followed too; the confirmation repeats their caveat.
- If the followed plan becomes `NotApplicable`, `Infeasible` or `NeverClears` (for example, after the budget changes), Home shows that state and offers "Choose another plan". The app never switches silently.

### 6.3 Starting point
A new starting point is recorded (its `reason` in brackets):
- **First** (`initial`): on the first launch after upgrade or onboarding, once there is at least one uncleared debt and the followed plan is `Feasible`.
- **Automatically**, when a debt is added (`debtAdded`, which includes reopening a cleared debt, §6.6), a debt is deleted (`debtDeleted`), or the followed plan is switched (`planSwitched`).
- **By a restart** (§6.8): `initial` again when the history is cleared, or `restarted` when it's kept.

Editing a debt's other fields, or changing the budget or strategy settings, does **not** record one automatically. The old projection then goes out of date, and ahead/behind shows the effect of the change until the user restarts (§6.8).

A change of tack never deletes anything. Every check-in and every earlier starting point is kept, and the chart shows them (§6.7). Only the forward projection and the ahead/behind reference move to the new starting point. A cleared debt doesn't record a starting point: clearing is progress. Only a restart that clears history deletes anything (§6.8).

A starting point is recorded only when the followed plan is `Feasible`. Otherwise an automatic one is deferred until it is, and Home says so; Restart from here is disabled, with the reason shown.

Every starting point also counts as a check-in (with `isStart = true`), so the chart's actual line starts from it.

### 6.4 Paid off
Measured from the **first** starting point, so it survives changes of tack and kept-history restarts. A restart that clears history starts it again from zero.
- `paidOff = Σ over debts that still exist (the debt's first recorded balance − its current balance)`.
- A debt's first recorded balance is its balance in the earliest check-in that includes it.
- A debt added later counts from its own first balance. A deleted debt drops out.
- `percent = paidOff / Σ first recorded balances`, clamped to 0–100%.
- If `paidOff` is negative, the hero reads "£X more owed than at the start" and the ring shows 0%.

### 6.5 Expected balance and ahead/behind
- **Month index** of a date: whole calendar months between the latest starting point's month and the date's month, using the injected clock.
- **Expected total** at month *m*: the latest starting point's projected total for month *m* (0 at and after the plan's last month).
- **Ahead/behind** at the latest check-in: `expected − actual total`. A positive figure is ahead.
  - Within ±1% of the expected total, or ±1 major unit, it reads "On track".
  - It is expressed in months ("1 month ahead") when the actual total is at or below the expected total of a later month; otherwise in money.
- **Check-in pre-fill:** for each debt, the balance the **current** followed plan (computed from current balances) projects for *k* months ahead, where *k* is the number of calendar months since the last check-in, from 0 up to the plan's length. With *k* = 0 it is simply the current balance.
- **Debt-free date change** on the result screen: the followed plan's end month before saving compared with after.

### 6.6 Clearing a debt
- A check-in value of 0, or "Mark as paid off", sets `balanceMinor = 0` and `clearedAt = now`, records the check-in, and queues the celebration.
- Cleared debts are filtered out before `validateDebts` and the engine (`balance > 0` validation stays as it is).
- Editing a cleared debt's balance to a positive amount clears `clearedAt` (the debt is active again) and records a `debtAdded` starting point, as for an added debt.

### 6.7 The progress chart
Built by one tested function, `progressChartData(startingPoints, checkIns, now)`, which returns:
- **actual:** every check-in's `(date, total)`, oldest first, across all starting points.
- **current projection:** the latest starting point's projected totals, from its month to the plan's end.
- **original projection:** the first starting point's projected totals (null when only one starting point exists).
- **markers:** every starting point after the first, as `(date, reason, strategy, debt name?)`. They become axis ticks with labels: "Switched to Snowball", "Added Visa", "Deleted Car loan", "Restarted".

Projections of starting points between the first and the latest aren't drawn: two dashed lines is the limit before the chart stops being readable. Plan detail doesn't show progress; its chart is always the plan from today.

### 6.8 Restart from here
A fresh start, separate from a change of tack. It's for when the history has become noise, or the user wants to stop being reminded of a bad stretch.

The **restart sheet** offers two choices:
1. **Start fresh** (the default, and the primary button):
   - Deletes every check-in and starting point.
   - Records a new `initial` starting point from today's balances and the followed plan.
   - Home then looks as it did on the first day: paid off from zero, no original projection, no markers.
   - Before anything is deleted, the sheet asks again inside the page: "This clears your check-in history and progress. Your debts and plans aren't changed. This can't be undone."
2. **Keep my history:** records a `restarted` starting point. It behaves like a change of tack, with a "Restarted" marker.

What a restart never touches:
- Debts (including the cleared list and each `clearedAt`, so celebrations aren't shown again).
- Settings, the followed plan and saved scenarios.
- Reminders. They are rescheduled, and the nudge counts from the new starting point.

## 7. Notifications

- Package: `flutter_local_notifications` with `timezone` / `flutter_timezone`. Local only, and never exact alarms (no `SCHEDULE_EXACT_ALARM` permission).
- A `NotificationsService` interface sits in `lib/core/`, with a no-op fake for tests (following the pattern of `AdsService` and `CrashReporter`).
- **Pay-day reminder:**
  - Scheduled for the chosen day at 09:00 local time ("Last day" is the month's last day; day 29–31 isn't offered).
  - The body lists the followed plan's payments for that month: "Overdraft £169 · Visa £96 · Car loan £210 · Store card £25", truncated to fit.
  - Because the content is computed when the reminder is scheduled, the app schedules **the next three occurrences** individually. It reschedules them whenever the app starts, a check-in is saved, debts or settings change, or the followed plan changes. The second and third use a generic body ("Time to pay your debts: open the app to see how much").
- **Check-in nudge:** one notification, "It's been {n} months: check in to see if you're on track", at the last check-in + *n* months at 09:00. It is rescheduled on every check-in.
- Tapping either notification opens `/check-in`. No action buttons in v3 (the wireframe's "Remind me tomorrow" is dropped).
- **Permission:**
  - Requested only when a reminder switch is turned on (setup or Settings).
  - Android 13+ `POST_NOTIFICATIONS`, and the iOS authorization request.
  - A denial turns the switch off and shows how to enable notifications in system settings.
- There are no reminders while there are no uncleared debts or the plan is infeasible; pending ones are cancelled.
- Notification copy goes in `app_en.arb`. The app formats amounts when it schedules.

## 8. Data, state and migration

### 8.1 Schema 3 → 4
- `debts` gains `clearedAt` (nullable `DateTime`).
- New table `check_ins`:
  - `id` (uuid) and `at` (DateTime).
  - `isStart` (bool).
  - `totalMinor` (the sum of uncleared balances after this check-in).
- New table `check_in_balances`: `checkInId`, `debtId`, `balanceMinor`; primary key (`checkInId`, `debtId`). Deleting a debt deletes its rows. `check_ins.totalMinor` keeps the history of totals intact.
- New table `starting_points`:
  - `id`, `checkInId` (its `isStart` check-in).
  - `strategy` (text enum).
  - `reason` (text enum: `initial`, `debtAdded`, `debtDeleted`, `planSwitched`, `restarted`), plus `debtName` (nullable text, copied at the time so the label survives the debt's deletion).
  - `projectedTotalsJson` (a JSON array of integer minor units, month 0 onwards).
  - The latest row is the reference, and the first is the original projection. Every row is kept (§6.7).
- Migration: add the column and the tables. The starting point is recorded at runtime (§6.3), not in the migration, because it needs the engine.
- The usual `make-migrations` schemas and generated tests are committed.

### 8.2 Currency change
`DriftDebtRepository.convertAmounts` also rescales `check_ins.totalMinor`, `check_in_balances.balanceMinor` and every element of `projectedTotalsJson`, in the same transaction. The in-memory test repository mirrors this for check-ins, unlike scenarios (which it doesn't rescale).

### 8.3 Accessibility
- Every chart has a `Semantics` label that summarises it. For example: "Plan versus actual. You owe £11,650, £110 less than the plan expected. Debt-free November 2028."
- Charts are never the only place a figure appears.
- Chart series differ in line style or pattern, not only colour.
- Touch targets are at least 48 dp.
- Text scales to 200% without clipping. Tiles and cards wrap.

### 8.4 Providers (sketch, for the plan to refine)
- `followedStrategyProvider`
- `startingPointProvider`
- `checkInsProvider` (a stream)
- `progressProvider`: paid off, percent, ahead/behind, expected pre-fill; pure functions in `lib/features/progress/domain/`.
- `homePlanProvider`: the followed plan on Current settings, with no slider extra.
- `notificationSchedulerProvider`: listens to all of the above and reschedules.

The new feature folder is `lib/features/progress/` (check-ins, starting point, celebration), and `lib/features/home/` is for the Home screen.

## 9. Engine

No engine changes. v3 uses what already exists:
- `PayoffPlan.months[].closingBalances` and `payments`, for projected totals, check-in pre-fill, this month's payments and milestone dates.
- `PayoffPlan.debts` in clearing order, for milestones.
- `bestPayOffMethod` and `isBorrowingAlternative`.

Card-transfer portion debts (`<card>#from-<source>`) are grouped with their card for display. Charts, milestones and "pay this month" show one row per real card, using the existing `planDebtName` and grouping helpers.

## 10. Testing

TDD as always.
- **Domain (unit):**
  - Paid off and percent, including added, deleted and cleared debts and a negative figure.
  - Month index across year boundaries.
  - Expected pre-fill for *k* = 0, 1, and beyond the plan's end.
  - Ahead/behind thresholds and the months-versus-money wording.
  - Starting-point triggers (each automatic reason, deferred while infeasible).
  - Restart: clearing history leaves exactly one `initial` starting point and its check-in, and resets paid off; keeping history adds a `restarted` marker; cleared debts and the followed plan are untouched either way.
  - `progressChartData`: one starting point; a plan switch mid-way (actual continuous, original kept, one tick); several changes of tack (only first and latest projections); a debt deleted after the change that added it.
  - Projected totals built from a plan.
  - Chart view-data builders.
  - Notification body and schedule dates (day 28, "Last day" in February and leap years, clock in December).
- **Repository:**
  - Migration 3 → 4 (generated tests plus data kept).
  - A check-in writes balances, the total and debt balances in one transaction.
  - Cleared debts are excluded from `loadAll` for planning, and listed separately.
  - `convertAmounts` rescales check-ins and starting points.
- **Widget** (`pumpApp`, fixed clock of 24 Sep 2026, a fake `NotificationsService`):
  - Tab switching keeps each tab's state.
  - Home states: no debts, infeasible, first run, ahead, behind, all cleared.
  - The check-in pre-fill; entering 0 → result → celebration → Home.
  - The "Follow this plan" confirmation records a starting point and keeps the history.
  - The restart sheet: the default clears history after the in-page confirmation, and "Keep my history" keeps it.
  - Banners appear only on Debts and Plans.
  - The Plan detail scrubber, via semantics.
  - The permission-denied path turns the switch off.
- **Golden tests:** none in v3 (visuals are still settling); they could come after the hi-fi pass.

## 11. Order of work

1. **Hi-fi design pass** (done 2026-09-25: Direction A, §5):
   - Palette, type, the chart palette, illustration style and source.
   - Hi-fi comps of Home, Debts, Plans, Plan detail, Check in and Celebration, in light and dark.
   - The result updates §5 with exact tokens.
2. **Plan 7: Shell and charts.**
   - The theme tokens, the three-tab shell and routes, and the Plans rename.
   - `lib/core/charts/`.
   - The redesigned Debts, Plans, Plan detail and Scenarios Compare.
   - A Home that shows the cheapest plan, with no progress yet.
3. **Plan 8: Progress.**
   - Schema 4, the followed plan, starting point, check-in and result.
   - Cleared debts and the celebration.
   - Home's progress hero and plan vs actual chart.
4. **Plan 9: Reminders.** `NotificationsService`, scheduling, the reminder step in setup, and the Settings section.
5. **Plan 10: Imagery.** The illustration painters and their animations (§5.2): welcome and setup, the Home wall, empty states, check-in result, cleared and debt free. Plans 7–9 ship simple static placeholders until then.

`docs/release.md` gains a step to block the sensitive ad categories in AdMob (gambling, and payday or high-interest lending).
