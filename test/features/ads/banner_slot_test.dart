import 'dart:async';

import 'package:debt_destroyer/features/ads/presentation/banner_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBanner implements LoadedBanner {
  _FakeBanner(this.label);

  final String label;
  bool disposed = false;

  @override
  Size get size => const Size(320, 50);

  @override
  Widget get widget => Text(label);

  @override
  void dispose() => disposed = true;
}

/// Loads that complete when the test says so, in any order.
class _Loads {
  final pending = <Completer<LoadedBanner?>>[];
  final widths = <int>[];

  Future<LoadedBanner?> load(int width) {
    widths.add(width);
    final c = Completer<LoadedBanner?>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  late _Loads loads;

  Future<void> pumpSlot(WidgetTester tester, {double width = 400}) async {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BannerSlot(load: loads.load)),
      ),
    );
  }

  setUp(() => loads = _Loads());

  testWidgets('takes no space until an ad loads', (tester) async {
    await pumpSlot(tester);
    expect(loads.widths, [400]);
    expect(find.byType(Text), findsNothing);

    loads.pending.single.complete(_FakeBanner('ad 1'));
    await tester.pump();
    expect(find.text('ad 1'), findsOneWidget);
  });

  testWidgets('takes no space when loading fails', (tester) async {
    await pumpSlot(tester);
    loads.pending.single.complete(null);
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a width change drops the old ad at once', (tester) async {
    await pumpSlot(tester);
    final first = _FakeBanner('ad 1');
    loads.pending.first.complete(first);
    await tester.pump();

    tester.view.physicalSize = const Size(700, 800);
    await tester.pump();
    expect(loads.widths, [400, 700]);
    expect(first.disposed, isTrue);
    expect(find.text('ad 1'), findsNothing);

    // The new ad fails: nothing is left behind.
    loads.pending.last.complete(null);
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a load that finishes late is thrown away', (tester) async {
    await pumpSlot(tester);
    tester.view.physicalSize = const Size(700, 800);
    await tester.pump();

    final latest = _FakeBanner('new');
    loads.pending.last.complete(latest);
    await tester.pump();
    final stale = _FakeBanner('old');
    loads.pending.first.complete(stale);
    await tester.pump();

    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
    expect(stale.disposed, isTrue);
    expect(latest.disposed, isFalse);
  });

  testWidgets('removing the slot releases its ad', (tester) async {
    await pumpSlot(tester);
    final ad = _FakeBanner('ad');
    loads.pending.single.complete(ad);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(ad.disposed, isTrue);
  });
}
