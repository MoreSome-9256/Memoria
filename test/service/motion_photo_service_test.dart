import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/motion_photo_service.dart';

void main() {
  test('findEmbeddedMp4Offset skips the container ftyp at offset zero', () {
    final bytes = Uint8List(64);
    _writeFtyp(bytes, 0);
    _writeFtyp(bytes, 24);

    expect(MotionPhotoService.findEmbeddedMp4Offset(bytes), 24);
  });

  test('findEmbeddedMp4Offset rejects malformed ftyp boxes', () {
    final bytes = Uint8List(64);
    _writeFtyp(bytes, 24, boxSize: 4);

    expect(MotionPhotoService.findEmbeddedMp4Offset(bytes), isNull);
  });
}

void _writeFtyp(Uint8List bytes, int offset, {int boxSize = 24}) {
  ByteData.sublistView(bytes).setUint32(offset, boxSize, Endian.big);
  bytes.setRange(offset + 4, offset + 8, const <int>[0x66, 0x74, 0x79, 0x70]);
}
