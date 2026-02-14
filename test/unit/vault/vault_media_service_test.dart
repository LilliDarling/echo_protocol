import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/services/vault/vault_media_service.dart';

@GenerateNiceMocks([
  MockSpec<Reference>(),
])
import 'vault_media_service_test.mocks.dart';

void main() {
  group('VaultMediaService', () {
    group('shouldInlineThumbnail', () {
      test('returns true for small thumbnails', () {
        expect(VaultMediaService.shouldInlineThumbnail(50 * 1024), isTrue);
      });

      test('returns true at exactly 100KB', () {
        expect(VaultMediaService.shouldInlineThumbnail(100 * 1024), isTrue);
      });

      test('returns false for larger files', () {
        expect(VaultMediaService.shouldInlineThumbnail(100 * 1024 + 1), isFalse);
      });
    });

    group('downloadMediaFromVault', () {
      test('downloads from correct storage path', () async {
        final mockRef = MockReference();
        final mockChildRef = MockReference();
        final fakeData = Uint8List.fromList([1, 2, 3, 4]);

        when(mockRef.child(any)).thenReturn(mockChildRef);
        when(mockChildRef.getData(any)).thenAnswer((_) async => fakeData);

        final storage = _FakeFirebaseStorage(mockRef);
        final service = VaultMediaService(storage: storage);

        final result = await service.downloadMediaFromVault(
          userId: 'user123',
          mediaId: 'media_001',
        );

        expect(result, fakeData);
        verify(mockRef.child('vaults/user123/media/media_001')).called(1);
      });

      test('returns null when media not found', () async {
        final mockRef = MockReference();
        final mockChildRef = MockReference();

        when(mockRef.child(any)).thenReturn(mockChildRef);
        when(mockChildRef.getData(any)).thenAnswer((_) async => null);

        final storage = _FakeFirebaseStorage(mockRef);
        final service = VaultMediaService(storage: storage);

        final result = await service.downloadMediaFromVault(
          userId: 'user123',
          mediaId: 'nonexistent',
        );

        expect(result, isNull);
      });
    });
  });
}

class _FakeFirebaseStorage extends Fake implements FirebaseStorage {
  final Reference _rootRef;
  _FakeFirebaseStorage(this._rootRef);

  @override
  Reference ref([String? path]) => _rootRef;
}
