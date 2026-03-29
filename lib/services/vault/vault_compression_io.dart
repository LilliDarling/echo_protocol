import 'dart:io';
import 'dart:typed_data';

Uint8List compressBytes(Uint8List data) {
  return Uint8List.fromList(ZLibCodec().encode(data));
}

Uint8List decompressBytes(Uint8List data) {
  return Uint8List.fromList(ZLibCodec().decode(data));
}
