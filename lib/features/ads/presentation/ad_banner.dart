import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The banner slot at the bottom of the Debts and Strategies screens. Empty
/// until consent allows ads.
class AdBanner extends ConsumerWidget {
  const AdBanner({this.respectsSafeArea = true, super.key});

  /// Pad for the home indicator. Turn off when a parent already does.
  final bool respectsSafeArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adsServiceProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: ads.canShowAds,
      builder: (context, canShow, _) {
        if (!canShow) return const SizedBox.shrink();
        final banner = Center(child: ads.buildBanner());
        return respectsSafeArea ? SafeArea(top: false, child: banner) : banner;
      },
    );
  }
}
