import 'dart:typed_data';

/// Encode PCM float samples as a 16-bit mono WAV file.
///
/// Pure Dart so it can run inside the TTS isolate and be unit-tested.
Uint8List encodeWavPcm16(Float32List samples, int sampleRate) {
  const headerLength = 44;
  final dataLength = samples.length * 2;
  final byteLength = headerLength + dataLength;

  final out = ByteData(byteLength);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  out.setUint32(4, byteLength - 8, Endian.little);
  writeAscii(8, 'WAVE');

  writeAscii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // PCM chunk size
  out.setUint16(20, 1, Endian.little); // audio format: PCM
  out.setUint16(22, 1, Endian.little); // channels: mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample

  writeAscii(36, 'data');
  out.setUint32(40, dataLength, Endian.little);

  var offset = headerLength;
  for (final sample in samples) {
    final clamped = sample < -1.0 ? -1.0 : (sample > 1.0 ? 1.0 : sample);
    out.setInt16(offset, (clamped * 32767).round(), Endian.little);
    offset += 2;
  }

  return out.buffer.asUint8List();
}
