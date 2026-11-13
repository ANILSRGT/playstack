#!/usr/bin/env bash
# Regenerates the typed native bridge for the Android and iOS packages from
# the single schema in pigeons/playstack_messages.dart.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run pigeon \
  --input pigeons/playstack_messages.dart \
  --package_name playstack_android \
  --dart_out packages/playstack_android/lib/src/messages.g.dart \
  --kotlin_out packages/playstack_android/android/src/main/kotlin/dev/playstack/android/Messages.g.kt \
  --kotlin_package dev.playstack.android

dart run pigeon \
  --input pigeons/playstack_messages.dart \
  --package_name playstack_ios \
  --dart_out packages/playstack_ios/lib/src/messages.g.dart \
  --swift_out packages/playstack_ios/ios/playstack_ios/Sources/playstack_ios/Messages.g.swift

dart format packages/playstack_android/lib/src/messages.g.dart packages/playstack_ios/lib/src/messages.g.dart
