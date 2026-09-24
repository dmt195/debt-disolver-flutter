import 'dart:async';

import 'package:flutter/material.dart';

/// A loaded banner ad: what to show, how big it is, and how to release it.
abstract interface class LoadedBanner {
  Size get size;
  Widget get widget;
  void dispose();
}

/// Loads a banner for a screen [width]; null if none could be loaded.
typedef BannerLoader = Future<LoadedBanner?> Function(int width);

/// Shows a banner sized to the screen width, reloading when the width
/// changes (rotation, split screen). Takes no space until an ad has loaded
/// and none if loading fails. Only the latest load is ever shown; late ones
/// are released.
class BannerSlot extends StatefulWidget {
  const BannerSlot({required this.load, super.key});

  final BannerLoader load;

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  LoadedBanner? _banner;
  int? _width;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      unawaited(_reload(width));
    }
  }

  Future<void> _reload(int width) async {
    final generation = ++_generation;
    final old = _banner;
    if (old != null) {
      _banner = null;
      old.dispose();
      if (mounted) setState(() {});
    }
    final loaded = await widget.load(width);
    if (!mounted || generation != _generation) {
      loaded?.dispose();
      return;
    }
    setState(() => _banner = loaded);
  }

  @override
  void dispose() {
    _generation++;
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (banner == null) return const SizedBox.shrink();
    return SizedBox.fromSize(size: banner.size, child: banner.widget);
  }
}
