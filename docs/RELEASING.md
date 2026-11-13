# Releasing

PlayStack is five packages released together with the same version. The
first preview, 0.1.0-dev.8, was published before the remaining items below;
they stay open for the first stable release.

## Open before 0.1.0

- [x] **License.** MIT, in the root `LICENSE` and in every package
      (`packages/*/LICENSE`, identical copies).
- [ ] **Physical devices.** Run the integration suite and the benchmark on
      at least one physical Android phone and one iPhone, and record the
      benchmark in [BENCHMARKS.md](BENCHMARKS.md).
- [x] **Web in a browser.** The integration suite passes in headless
      Chromium (see [Examples](guides/examples.md#on-the-web)). Still open:
      HLS.js, Safari and Firefox.

## Checklist for every release

1. Choose the version (`0.1.0-dev.N` while in preview, then semantic
   versioning) and set it in:
   - `packages/*/pubspec.yaml` (`version:`)
   - the internal dependency constraints (`playstack_*: ^<version>` in
     `playstack`, `playstack_android`, `playstack_ios`, `playstack_web` and the
     example), so no package resolves against an older sibling
   - `packages/playstack_android/android/build.gradle.kts` (`version`)
   - `packages/playstack_ios/ios/playstack_ios.podspec` (`s.version`)
2. Add a `## <version>` entry to each package's `CHANGELOG.md`.
3. If `pigeons/playstack_messages.dart` changed, run
   `./tool/generate_pigeons.sh` and commit the generated files.
4. Verify, from the repository root:

   ```bash
   flutter pub get
   flutter analyze
   dart format --output=none --set-exit-if-changed .
   flutter test packages/playstack/test packages/playstack_platform_interface/test \
     packages/playstack_android/test packages/playstack_ios/test
   (cd packages/playstack && dart doc --dry-run)
   (cd packages/playstack/example && flutter build apk --debug && \
     flutter build ios --simulator --debug && flutter build web --wasm)
   ```

5. Run the device suites (see [Examples](guides/examples.md)) on Android
   and iOS, and the benchmark when performance-related code changed.
6. Update the status lines in `README.md` and `packages/playstack/README.md`.
7. Commit, tag `v<version>`, push the tag.
8. Validate each package, then publish in dependency order, waiting for
   each to appear on pub.dev before the next:

   ```bash
   (cd packages/playstack_platform_interface && flutter pub publish --dry-run)
   # repeat --dry-run for the others, then without --dry-run in this order:
   # 1. playstack_platform_interface
   # 2. playstack_android, playstack_ios, playstack_web
   # 3. playstack
   ```

   The only acceptable dry-run warning is uncommitted files when running
   before the release commit.

## Compatibility rules

- The platform interface only grows: new methods on `PlayStackPlatform`
  get a default implementation that throws `UnimplementedError`, so older
  engines keep compiling. Removing or changing a method is a breaking
  change of `playstack_platform_interface` (a new major or, before 1.0, a
  new minor version).
- Pigeon messages are private to each engine and can change in any
  release, as long as the Dart and native sides are regenerated together.
