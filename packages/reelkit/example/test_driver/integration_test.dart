import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host side of `flutter drive`. Writes `reportData` (test results and the
/// benchmark) to `build/integration_response_data.json`, prints the result
/// of every test and fails when no test ran.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    await writeResponseData(data);
    final results = data?['results'];
    if (results is! Map || results.isEmpty) {
      stderr.writeln('No test reported a result; setUpAll probably failed.');
      exit(1);
    }
    results.forEach((name, result) => stdout.writeln('$result: $name'));
  },
);
