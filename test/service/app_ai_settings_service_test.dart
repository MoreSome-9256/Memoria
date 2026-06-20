import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pending analysis prompt dismissal can be saved and cleared', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final service = AppAiSettingsService.instance;

    expect(await service.isPendingAnalysisPromptDismissed(), isFalse);

    await service.setPendingAnalysisPromptDismissed(true);
    expect(await service.isPendingAnalysisPromptDismissed(), isTrue);

    await service.setPendingAnalysisPromptDismissed(false);
    expect(await service.isPendingAnalysisPromptDismissed(), isFalse);
  });
}
