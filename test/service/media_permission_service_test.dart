import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_album/service/media_permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('limited access temporarily suspends but does not mutate whitelist', () {
    final saved = <String>['camera', 'family'];

    final effective = MediaPermissionService.effectiveAlbumWhitelist(
      state: PermissionState.limited,
      savedAlbumIds: saved,
    );

    expect(effective, isEmpty);
    expect(saved, <String>['camera', 'family']);
  });

  test('full access applies the saved album whitelist', () {
    final effective = MediaPermissionService.effectiveAlbumWhitelist(
      state: PermissionState.authorized,
      savedAlbumIds: <String>['camera', 'family', 'camera'],
    );

    expect(effective, <String>{'camera', 'family'});
  });

  test(
    'permission snapshot is available without calling photo_manager',
    () async {
      await MediaPermissionService.persistState(PermissionState.limited);

      final snapshot = await MediaPermissionService.readCachedSnapshot();

      expect(snapshot.state, PermissionState.limited);
      expect(snapshot.hasAccess, isTrue);
      expect(snapshot.isLimited, isTrue);
    },
  );
}
