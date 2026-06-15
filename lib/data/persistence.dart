/// Versioned, migration-safe persistence of the entire game state as one
/// JSON document in shared_preferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class Persistence {
  static const String storageKey = 'wayfarer.state';
  static const int schemaVersion = 1;

  final SharedPreferences _prefs;
  Persistence(this._prefs);

  static Future<Persistence> open() async =>
      Persistence(await SharedPreferences.getInstance());

  /// Loads and migrates persisted state. Any corruption falls back to a
  /// fresh state rather than crashing — the journey must always open.
  GameState load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return GameState.initial;
    try {
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final migrated = _migrate(doc);
      return GameState.fromJson(
          (migrated['state'] as Map).cast<String, Object?>());
    } catch (_) {
      return GameState.initial;
    }
  }

  Future<void> save(GameState state) => _prefs.setString(
        storageKey,
        jsonEncode({'schemaVersion': schemaVersion, 'state': state.toJson()}),
      );

  Future<void> reset() => _prefs.remove(storageKey);

  /// Migration ladder: each step upgrades one version. Version 1 is current.
  Map<String, dynamic> _migrate(Map<String, dynamic> doc) {
    var version = doc['schemaVersion'] as int? ?? 1;
    var current = doc;
    while (version < schemaVersion) {
      switch (version) {
        // case 1: current = _migrateV1toV2(current); break;
        default:
          break;
      }
      version++;
    }
    return current;
  }
}
