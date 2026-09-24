import 'dart:async';

import 'package:debt_destroyer/features/ads/presentation/banner_slot.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// An anchored adaptive AdMob banner sized to the screen width.
class AdMobBanner extends StatelessWidget {
  const AdMobBanner({required this.adUnitId, super.key});

  final String adUnitId;

  @override
  Widget build(BuildContext context) => BannerSlot(load: _load);

  Future<LoadedBanner?> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null) return null;
    final loaded = Completer<LoadedBanner?>();
    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => loaded.complete(_AdMobLoaded(ad as BannerAd)),
        onAdFailedToLoad: (ad, _) {
          unawaited(ad.dispose());
          loaded.complete(null);
        },
      ),
    );
    await ad.load();
    return await loaded.future;
  }
}

class _AdMobLoaded implements LoadedBanner {
  _AdMobLoaded(this._ad);

  final BannerAd _ad;

  @override
  Size get size => Size(_ad.size.width.toDouble(), _ad.size.height.toDouble());

  @override
  Widget get widget => AdWidget(ad: _ad);

  @override
  void dispose() => unawaited(_ad.dispose());
}
