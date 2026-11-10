import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Initializes the integration test binding and attaches the per-test
/// results to the report data, so `test_driver/integration_test.dart` can
/// fail a run in which no test executed (for example when `setUpAll` threw
/// on the web, which the driver otherwise reports as passing).
IntegrationTestWidgetsFlutterBinding ensureBindingWithResults() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() {
    binding.reportData = <String, dynamic>{
      ...?binding.reportData,
      'results': <String, String>{
        for (final entry in binding.results.entries)
          entry.key: entry.value is String ? entry.value as String : 'failed',
      },
    };
  });
  return binding;
}
