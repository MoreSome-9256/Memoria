import 'mobileclip_litert_service.dart';
import 'app_ai_settings_service.dart';

class MobileClipTextService {
  MobileClipTextService._internal();

  static final MobileClipTextService _instance =
      MobileClipTextService._internal();

  factory MobileClipTextService() => _instance;

  MobileClipLiteRtService _liteRtService = MobileClipLiteRtService();

  Future<void> warmUp() async {
    _liteRtService = await _resolveLiteRtService();
    await _liteRtService.warmUpText();
  }

  Future<List<double>> embedTextTokens(List<int> tokenIds) async {
    _liteRtService = await _resolveLiteRtService();
    return _liteRtService.embedTextTokens(tokenIds);
  }

  Future<void> dispose() async {
    await _liteRtService.dispose();
  }

  Future<MobileClipLiteRtService> _resolveLiteRtService() async {
    final settings = await AppAiSettingsService.instance.load();
    return MobileClipLiteRtService.withAccelerator(
      settings.inferenceAccelerator,
    );
  }
}
