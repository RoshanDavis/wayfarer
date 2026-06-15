/// Real-world speed references and crossing detection. Pure Dart.
library;

/// A real reference speed the runner can overtake.
class SpeedComparison {
  final String id;
  final String name;
  final double kmh;

  /// The quiet line shown once on the session-end screen.
  final String line;

  const SpeedComparison(this.id, this.name, this.kmh, this.line);
}

/// Reference speeds, ascending — all real figures (top/typical speeds).
/// Crossing one awards a badge and a single understated session-end line.
const List<SpeedComparison> kComparisons = [
  SpeedComparison('walking-human', 'Walking human', 5,
      'You now outpace a walking human.'),
  SpeedComparison('bicycle', 'Bicycle', 18, 'You now outpace a bicycle.'),
  SpeedComparison('sprinting-human', 'Sprinting human', 37,
      'You now outpace a sprinting human at full tilt.'),
  SpeedComparison('galloping-horse', 'Galloping horse', 40,
      'You now outrun a galloping horse.'),
  SpeedComparison('ostrich', 'Ostrich', 70,
      'You now outrun an ostrich, the fastest runner on two legs.'),
  SpeedComparison('cheetah', 'Cheetah', 100, 'You now outrun a cheetah.'),
  SpeedComparison('highway-car', 'Highway car', 120,
      'You now outrun a car at highway speed.'),
  SpeedComparison('bullet-train', 'Bullet train', 300,
      'You now outrun a bullet train.'),
  SpeedComparison('peregrine-falcon', 'Peregrine falcon', 390,
      'You now outrun a diving peregrine falcon, the fastest animal alive.'),
  SpeedComparison('jet-airliner', 'Jet airliner', 900,
      'You now outrun a jet airliner.'),
  SpeedComparison('speed-of-sound', 'The speed of sound', 1235,
      'You now outrun sound itself.'),
  SpeedComparison('blackbird', 'SR-71 Blackbird', 3540,
      'You now outrun the fastest jet ever flown.'),
  SpeedComparison('orbital-velocity', 'Orbital velocity', 28000,
      'You now outrun a satellite in orbit.'),
  SpeedComparison('escape-velocity', 'Escape velocity', 40270,
      'You now outrun escape velocity. The Earth could not hold you.'),
  SpeedComparison('voyager-1', 'Voyager 1', 61200,
      'You now outrun Voyager 1, the farthest craft we have ever flown.'),
  SpeedComparison('parker-probe', 'Parker Solar Probe', 692000,
      'You now outrun the fastest machine humans have ever built.'),
];

/// Comparisons crossed when pace rises from [oldPaceKmh] (exclusive) to
/// [newPaceKmh] (inclusive), in ascending order. With monotonic pace each
/// reference is crossed exactly once in a lifetime.
List<SpeedComparison> crossingsBetween(double oldPaceKmh, double newPaceKmh) =>
    [
      for (final c in kComparisons)
        if (c.kmh > oldPaceKmh && c.kmh <= newPaceKmh) c,
    ];

SpeedComparison? comparisonById(String id) {
  for (final c in kComparisons) {
    if (c.id == id) return c;
  }
  return null;
}
