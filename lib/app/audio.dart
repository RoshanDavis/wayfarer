/// The single soft chime, synthesized at runtime — the app ships no audio
/// assets and plays nothing during focus.
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../core/chime_synth.dart';

class ChimePlayer {
  AudioPlayer? _player;
  Uint8List? _wav;

  Future<void> play() async {
    try {
      _wav ??= synthesizeChime(volume: 0.45);
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(BytesSource(_wav!, mimeType: 'audio/wav'));
    } catch (_) {
      // Sound is optional comfort; never let it break the app.
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
