/// Generates the bundled notification-channel chime ([synthesizeChime]). The
/// completion alert is the app's only sound, on both foreground and background
/// session ends. The output is an Android raw resource, the only way a
/// notification channel can use a custom sound.
///
/// Run from the project root:
///
///   dart run tool/generate_chime.dart
library;

import 'dart:io';

import 'package:wayfarer/core/chime_synth.dart';

void main() {
  final bytes = synthesizeChime(volume: 0.45);
  final out = File('android/app/src/main/res/raw/session_chime.wav');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${bytes.length} bytes to ${out.path}');
}
