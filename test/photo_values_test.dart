import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/photo_values.dart';

void main() {
  const blob = '/api/blobs/0d21bf6e-5215-4671-aa64-a58d95cf949f';

  test('recognises both photo forms', () {
    expect(isPhotoValue('data:image/webp;base64,AAAA'), isTrue);
    expect(isPhotoValue(blob), isTrue);
    expect(isBlobPhotoPath(blob), isTrue);
  });

  test('rejects anything that is not exactly a blob path', () {
    expect(isPhotoValue('/api/blobs/not-a-uuid'), isFalse);
    expect(isPhotoValue('https://evil.example/api/blobs/0d21bf6e-5215-4671-aa64-a58d95cf949f'), isFalse);
    expect(isPhotoValue('$blob?x=1'), isFalse);
    expect(isPhotoValue('swerve'), isFalse);
    expect(isPhotoValue(42), isFalse);
    expect(isPhotoValue(null), isFalse);
  });
}
