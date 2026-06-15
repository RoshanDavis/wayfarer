import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/chime_synth.dart';

void main() {
  test('synthesized chime is a valid 16-bit mono PCM WAV', () {
    final wav = synthesizeChime();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + 44100 * 2 * 2); // header + 2 s of samples
    // Non-silent, and the declared data size matches.
    final dataSize = wav.buffer.asByteData().getUint32(40, Endian.little);
    expect(dataSize, wav.length - 44);
    expect(wav.skip(44).any((b) => b != 0), isTrue);
  });

  test('volume 0 produces silence', () {
    final wav = synthesizeChime(volume: 0);
    expect(wav.skip(44).every((b) => b == 0), isTrue);
  });
}
