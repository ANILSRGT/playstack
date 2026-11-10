# Releasing

ReelKit is five packages released together with the same version. They
are marked `publish_to: none` until the blockers below are resolved.

## Blockers before the first publication

- [ ] **License.** Every package's `LICENSE` is a placeholder. Choose a
      license, put its full text in the root and in each package
      (`packages/*/LICENSE`); pub.dev rejects packages without a valid
      license.
- [ ] **Physical devices.** Run the integration suite and the benchmark on
      at least one physical Android phone and one iPhone, and record the
      benchmark in [BENCHMARKS.md](BENCHMARKS.md).
- [ ] **Web in a browser.** Run the integration suite with chromedriver
      (`flutter drive -d chrome`), including HLS.js and the Fullscreen API.
- [ ] Remove `publish_to: none` from the five `pubspec.yaml` files.

## Checklist for every release

1. Choose the version (`0.1.0-dev.N` while in preview, then semantic
   versioning) and set it in:
   - `packages/*/pubspec.yaml` (`version:`)
   - the internal dependency constraints (`reelkit_*: ^<version>` in
     `reelkit`, `reelkit_android`, `reelkit_ios`, `reelkit_web` and the
     example), so no package resolves against an older sibling
   - `packages/reelkit_android/android/build.gradle.kts` (`version`)
   - `packages/reelkit_ios/ios/reelkit_ios.podspec` (`s.version`)
2. Add a `## <version>` entry to each package's `CHANGELOG.md`.
3. If `pigeons/reelkit_messages.dart` changed, run
   `./tool/generate_pigeons.sh` and commit the generated files.
4. Verify, from the repository root:

   ```bash
   flutter pub get
   flutter analyze
   dart format --output=none --set-exit-if-changed .
   flutter test packages/reelkit/test packages/reelkit_platform_interface/test \
     packages/reelkit_android/test packages/reelkit_ios/test
   (cd packages/reelkit && dart doc --dry-run)
   (cd packages/reelkit/example && flutter build apk --debug && \
     flutter build ios --simulator --debug && flutter build web --wasm)
   ```

5. Run the device suites (see [Examples](guides/examples.md)) on Android
   and iOS, and the benchmark when performance-related code changed.
6. Update the status lines in `README.md` and `packages/reelkit/README.md`.
7. Commit, tag `v<version>`, push the tag.
8. Validate each package, then publish in dependency order, waiting for
   each to appear on pub.dev before the next:

   ```bash
   (cd packages/reelkit_platform_interface && flutter pub publish --dry-run)
   # repeat --dry-run for the others, then without --dry-run in this order:
   # 1. reelkit_platform_interface
   # 2. reelkit_android, reelkit_ios, reelkit_web
   # 3. reelkit
   ```

   The only acceptable dry-run warning is uncommitted files when running
   before the release commit.

## Compatibility rules

- The platform interface only grows: new methods on `ReelKitPlatform`
  get a default implementation that throws `UnimplementedError`, so older
  engines keep compiling. Removing or changing a method is a breaking
  change of `reelkit_platform_interface` (a new major or, before 1.0, a
  new minor version).
- Pigeon messages are private to each engine and can change in any
  release, as long as the Dart and native sides are regenerated together.
