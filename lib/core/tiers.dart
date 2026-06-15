/// Pace tiers — the spine of the game. Pure Dart, no Flutter imports.
library;

import 'game_math.dart' as gm;

/// A named pace tier, unlocked at [level].
class PaceTier {
  final int level;
  final String name;
  const PaceTier(this.level, this.name);

  /// Pace at the tier's unlock level.
  double get paceKmh => gm.paceKmh(level);

  /// Index of this tier along the path (0 = First steps). Used for gait
  /// banding and the Journey tier path.
  int get index => level < kEternalLevel
      ? kBaseTiers.indexWhere((t) => t.level == level)
      : kBaseTiers.length - 1 + (level - kEternalLevel) ~/ kProceduralTierInterval;

  @override
  bool operator ==(Object other) =>
      other is PaceTier && other.level == level && other.name == name;

  @override
  int get hashCode => Object.hash(level, name);

  @override
  String toString() => 'PaceTier($level, $name)';
}

/// The 21 named tiers, level 1 through 200.
const List<PaceTier> kBaseTiers = [
  PaceTier(1, 'First steps'),
  PaceTier(10, 'Wanderer'),
  PaceTier(20, 'Strider'),
  PaceTier(30, 'Pathfinder'),
  PaceTier(40, 'Trailblazer'),
  PaceTier(50, 'Swift-foot'),
  PaceTier(60, 'Gale runner'),
  PaceTier(70, 'Windchaser'),
  PaceTier(80, 'Stormstrider'),
  PaceTier(90, 'Thunderfoot'),
  PaceTier(100, 'Lightning stride'),
  PaceTier(110, 'Sonic wayfarer'),
  PaceTier(120, 'Skyline runner'),
  PaceTier(130, 'Horizon breaker'),
  PaceTier(140, 'Meteor'),
  PaceTier(150, 'Comet'),
  PaceTier(160, 'Orbit runner'),
  PaceTier(170, 'Starstrider'),
  PaceTier(180, 'Moonbound'),
  PaceTier(190, 'Solar wind'),
  PaceTier(200, 'The Eternal Wayfarer'),
];

/// Level of the last named tier; procedural tiers continue past it.
const int kEternalLevel = 200;

/// Procedural tiers appear every 25 levels past [kEternalLevel]:
/// 225 → "The Eternal Wayfarer II", 250 → III, …
const int kProceduralTierInterval = 25;

const String _eternalName = 'The Eternal Wayfarer';

/// Roman numeral for n >= 1 (unbounded; thousands repeat M).
String romanNumeral(int n) {
  assert(n >= 1);
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const glyphs = [
    'M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I',
  ];
  final out = StringBuffer();
  var rest = n;
  for (var i = 0; i < values.length; i++) {
    while (rest >= values[i]) {
      out.write(glyphs[i]);
      rest -= values[i];
    }
  }
  return out.toString();
}

PaceTier _proceduralTier(int ordinal) => PaceTier(
      kEternalLevel + ordinal * kProceduralTierInterval,
      '$_eternalName ${romanNumeral(ordinal + 1)}',
    );

/// The tier active at [level] (the highest tier whose unlock level <= level).
PaceTier tierForLevel(int level) {
  assert(level >= 1);
  if (level >= kEternalLevel + kProceduralTierInterval) {
    final ordinal = (level - kEternalLevel) ~/ kProceduralTierInterval;
    return _proceduralTier(ordinal);
  }
  return kBaseTiers.lastWhere((t) => t.level <= level);
}

/// All tiers whose unlock level lies in (oldLevel, newLevel] — the tiers
/// reached by a level-up from [oldLevel] to [newLevel], in order.
List<PaceTier> tiersReachedBetween(int oldLevel, int newLevel) {
  final reached = <PaceTier>[
    for (final t in kBaseTiers)
      if (t.level > oldLevel && t.level <= newLevel) t,
  ];
  var ordinal = oldLevel <= kEternalLevel
      ? 1
      : (oldLevel - kEternalLevel) ~/ kProceduralTierInterval + 1;
  for (;; ordinal++) {
    final tier = _proceduralTier(ordinal);
    if (tier.level > newLevel) break;
    if (tier.level > oldLevel) reached.add(tier);
  }
  return reached;
}

/// The next tier after [level], for "path ahead" display. Always exists.
PaceTier nextTierAfter(int level) {
  for (final t in kBaseTiers) {
    if (t.level > level) return t;
  }
  final ordinal = (level - kEternalLevel) ~/ kProceduralTierInterval + 1;
  return _proceduralTier(ordinal);
}
