/// Generates the bundled notification-channel chime from the same synthesizer
/// the app plays in the foreground, so foreground and background session-end
/// sounds are identical. The output is an Android raw resource, the only way a
/// notification channel can use a custom sound.
///
/// Run from the project root:
///
///   dart run tool/generate_chime.dart
library;

import 'dart:io';

import 'package:wayfarer/core/chime_synth.dart';

void main() {
  // Match the in-app chime volume (see ChimePlayer.play, lib/app/audio.dart).
  final bytes = synthesizeChime(volume: 0.45);
  final out = File('android/app/src/main/res/raw/session_chime.wav');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  stdout.writeln('Wrote ${bytes.length} bytes to ${out.path}');
}
