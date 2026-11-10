#!/usr/bin/env bash
# Regenerates the typed native bridge for the Android and iOS packages from
# the single schema in pigeons/reelkit_messages.dart.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run pigeon \
  --input pigeons/reelkit_messages.dart \
  --package_name reelkit_android \
  --dart_out packages/reelkit_android/lib/src/messages.g.dart \
  --kotlin_out packages/reelkit_android/android/src/main/kotlin/dev/reelkit/android/Messages.g.kt \
  --kotlin_package dev.reelkit.android

dart run pigeon \
  --input pigeons/reelkit_messages.dart \
  --package_name reelkit_ios \
  --dart_out packages/reelkit_ios/lib/src/messages.g.dart \
  --swift_out packages/reelkit_ios/ios/reelkit_ios/Sources/reelkit_ios/Messages.g.swift

dart format packages/reelkit_android/lib/src/messages.g.dart packages/reelkit_ios/lib/src/messages.g.dart
