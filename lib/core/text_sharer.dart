import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'text_sharer.g.dart';

/// Shares a short message through the platform share sheet.
abstract interface class TextSharer {
  Future<void> share(String text);
}

class SharePlusTextSharer implements TextSharer {
  @override
  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

@Riverpod(keepAlive: true)
TextSharer textSharer(Ref ref) => SharePlusTextSharer();
