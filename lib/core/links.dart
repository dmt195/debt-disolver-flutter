import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'links.g.dart';

/// The app's hosted legal documents (diagnostics spec §3).
abstract final class LegalLinks {
  static final Uri privacyPolicy = Uri.parse(
    'https://countersunk.dev/apps/debt-destroyer/privacy-policy/',
  );
  static final Uri terms = Uri.parse(
    'https://countersunk.dev/apps/debt-destroyer/tos/',
  );
}

/// Opens a web page outside the app; false if it couldn't.
abstract interface class LinkOpener {
  Future<bool> open(Uri uri);
}

class UrlLauncherLinkOpener implements LinkOpener {
  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

@Riverpod(keepAlive: true)
LinkOpener linkOpener(Ref ref) => UrlLauncherLinkOpener();
