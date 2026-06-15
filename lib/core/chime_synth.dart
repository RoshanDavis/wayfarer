/// Runtime synthesis of the session-end chime as a WAV byte buffer.
/// Pure Dart (dart:typed_data only) — the app ships no audio assets.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Synthesizes a soft two-partial chime (a warm E5 with a quiet octave),
/// ~2 seconds, 44.1 kHz 16-bit mono WAV.
Uint8List synthesizeChime({double volume = 0.5}) {
  const sampleRate = 44100;
  const seconds = 2.0;
  final n = (sampleRate * seconds).round();
  final samples = Float64List(n);

  const f0 = 659.255; // E5
  const partials = [
    (freq: f0, amp: 1.0, decay: 2.4),
    (freq: f0 * 2.0, amp: 0.35, decay: 3.4),
    (freq: f0 * 2.99, amp: 0.12, decay: 4.6), // slightly inharmonic shimmer
  ];

  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    // Gentle 8 ms attack so the onset is soft, then exponential decay.
    final attack = t < 0.008 ? t / 0.008 : 1.0;
    var v = 0.0;
    for (final p in partials) {
      v += p.amp * math.exp(-p.decay * t) * math.sin(2 * math.pi * p.freq * t);
    }
    samples[i] = v * attack;
  }

  // Normalize and scale.
  var peak = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  final scale = peak > 0 ? (volume.clamp(0.0, 1.0) / peak) : 0.0;

  final data = ByteData(44 + n * 2);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  // RIFF/WAVE header (PCM, mono, 16-bit).
  writeString(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  data.setUint32(40, n * 2, Endian.little);

  for (var i = 0; i < n; i++) {
    final v = (samples[i] * scale * 32767.0).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}
