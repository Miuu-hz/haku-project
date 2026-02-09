// integration_test/app_test.dart
// 🧪 Main Integration Test Runner
// รันทุก test suites

import 'package:integration_test/integration_test.dart';

// Import all test suites
import 'tests/chat_test.dart' as chat_tests;
import 'tests/map_test.dart' as map_tests;
import 'tests/battery_test.dart' as battery_tests;
import 'tests/ai_actions_test.dart' as ai_actions_tests;
import 'tests/calendar_test.dart' as calendar_tests;
import 'tests/llm_test.dart' as llm_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run all tests
  chat_tests.main();
  map_tests.main();
  battery_tests.main();
  ai_actions_tests.main();
  calendar_tests.main();
  llm_tests.main();
}
