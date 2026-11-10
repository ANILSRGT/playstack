import 'package:integration_test/integration_test_driver.dart';

/// Host side of `flutter drive`; writes `reportData` (the benchmark results)
/// to `build/integration_response_data.json`.
Future<void> main() => integrationDriver();
