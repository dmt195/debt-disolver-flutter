#!/usr/bin/env bash
# Generates all build_runner code: the payoff_engine package first (the app
# imports its generated freezed classes), then the app.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd packages/payoff_engine && dart pub get && dart run build_runner build -d)
flutter pub get
flutter gen-l10n
dart run build_runner build -d
