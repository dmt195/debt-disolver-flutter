import 'package:debt_destroyer/core/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the legal pages live on countersunk.dev', () {
    expect(
      LegalLinks.privacyPolicy.toString(),
      'https://countersunk.dev/apps/debt-destroyer/privacy-policy/',
    );
    expect(
      LegalLinks.terms.toString(),
      'https://countersunk.dev/apps/debt-destroyer/tos/',
    );
  });
}
