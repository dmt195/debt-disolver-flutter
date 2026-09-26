import 'package:debt_destroyer/core/links.dart';

/// Records the pages the app opens; [succeed] false simulates a failure.
class FakeLinkOpener implements LinkOpener {
  FakeLinkOpener({this.succeed = true});

  final bool succeed;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeed;
  }
}
