/// The 25 world maps and map progression. Pure Dart — maps are pure data;
/// rendering interprets [Terrain] and [MapDecor] elsewhere.
library;

/// Silhouette profile families used to generate landscape layers.
enum Terrain {
  softHills,
  flatPlains,
  dunes,
  jaggedTreeline,
  cliffsSea,
  layeredMesas,
  verticalGrove,
  steppedHills,
  jaggedRidges,
  cloudLayers,
}

/// Small structural decor layered onto a terrain (trees).
enum MapDecor { none, loneTrees, orchardTrees }

/// The subtle ambient particle effect that gives each map its own air —
/// drifting pollen, blowing sand, sea spray, fireflies, rising embers, and so
/// on. Always understated, and never falling (those read poorly). The night
/// sky's stars are a separate, stationary dark-mode backdrop, not a per-map
/// particle.
enum MapParticle {
  none,
  pollen,
  dust,
  sand,
  mist,
  spray,
  fireflies,
  embers,
  drift,
}

class WorldMap {
  final String name;

  /// HSL hue in degrees — the single accent hue of the whole UI on this map.
  final double hue;

  /// Base saturation for the tonal ramp (0..1). Low values give the gray
  /// maps (Salt Flats, Misty Moors, Volcanic Fields) their hush.
  final double saturation;

  final Terrain terrain;
  final MapDecor decor;
  final MapParticle particle;

  const WorldMap(this.name, this.hue, this.saturation, this.terrain,
      [this.decor = MapDecor.none, this.particle = MapParticle.none]);
}

/// The 25 maps, in journey order. The cycle loops with subtle variation.
const List<WorldMap> kMaps = [
  WorldMap('The Garden', 100, 0.42, Terrain.softHills, MapDecor.none,
      MapParticle.pollen),
  WorldMap('Golden Plains', 45, 0.55, Terrain.flatPlains, MapDecor.none,
      MapParticle.dust),
  WorldMap('Dune Sea', 36, 0.52, Terrain.dunes, MapDecor.none,
      MapParticle.sand),
  WorldMap('Pine Ridge', 150, 0.38, Terrain.jaggedTreeline, MapDecor.none,
      MapParticle.mist),
  WorldMap('Coastal Cliffs', 212, 0.38, Terrain.cliffsSea, MapDecor.none,
      MapParticle.spray),
  WorldMap('Canyon', 16, 0.52, Terrain.layeredMesas, MapDecor.none,
      MapParticle.dust),
  WorldMap('Lavender Hills', 272, 0.36, Terrain.softHills, MapDecor.none,
      MapParticle.pollen),
  WorldMap('Salt Flats', 205, 0.10, Terrain.flatPlains, MapDecor.none,
      MapParticle.mist),
  WorldMap('Bamboo Grove', 160, 0.42, Terrain.verticalGrove, MapDecor.none,
      MapParticle.none),
  WorldMap('Misty Moors', 310, 0.13, Terrain.softHills, MapDecor.none,
      MapParticle.mist),
  WorldMap('Savanna', 38, 0.48, Terrain.flatPlains, MapDecor.loneTrees,
      MapParticle.dust),
  WorldMap('Fjords', 208, 0.44, Terrain.cliffsSea, MapDecor.none,
      MapParticle.mist),
  WorldMap('Cherry Orchard', 345, 0.40, Terrain.softHills,
      MapDecor.orchardTrees, MapParticle.pollen),
  WorldMap('Red Rock Mesa', 10, 0.52, Terrain.layeredMesas, MapDecor.none,
      MapParticle.dust),
  WorldMap('Rice Terraces', 175, 0.42, Terrain.steppedHills, MapDecor.none,
      MapParticle.mist),
  WorldMap('Tundra', 195, 0.32, Terrain.flatPlains, MapDecor.none,
      MapParticle.none),
  WorldMap('Olive Groves', 72, 0.36, Terrain.softHills, MapDecor.orchardTrees,
      MapParticle.pollen),
  WorldMap('Volcanic Fields', 12, 0.18, Terrain.jaggedRidges, MapDecor.none,
      MapParticle.embers),
  WorldMap('Glacier Pass', 187, 0.46, Terrain.jaggedRidges, MapDecor.none,
      MapParticle.mist),
  WorldMap('Painted Hills', 14, 0.52, Terrain.layeredMesas, MapDecor.none,
      MapParticle.dust),
  WorldMap('Mangrove Delta', 155, 0.38, Terrain.flatPlains, MapDecor.none,
      MapParticle.fireflies),
  WorldMap('Night Desert', 255, 0.42, Terrain.dunes, MapDecor.none,
      MapParticle.none),
  WorldMap('Starlit Steppe', 265, 0.42, Terrain.flatPlains, MapDecor.none,
      MapParticle.none),
  WorldMap('The Stratosphere', 228, 0.38, Terrain.cloudLayers, MapDecor.none,
      MapParticle.drift),
  WorldMap('Maple Wood', 28, 0.50, Terrain.jaggedTreeline, MapDecor.none,
      MapParticle.pollen),
];

/// Index into [kMaps] for a player at [level]. The map advances every level and
/// loops past the end — level 1 is map 0, level 25 is map 24, level 26 wraps to
/// map 0. Consecutive levels always differ (i+1 mod N != i for N > 1), so any
/// level-up changes the map.
int mapIndexForLevel(int level) => (level - 1) % kMaps.length;

/// How many full [kMaps]-length loops the player has completed at [level].
/// Cycles past the first re-render with subtle variation (shifted lightness,
/// reseeded terrain).
int mapCycleForLevel(int level) => (level - 1) ~/ kMaps.length;

WorldMap mapForLevel(int level) => kMaps[mapIndexForLevel(level)];

/// The accent palette (hue + saturation) for a player with [sessionsCompleted]
/// completed focus sessions. Unlike the map — which governs terrain shape and
/// advances every level — the accent steps through the curated map palettes (25)
/// once per completed session, so the colour refreshes every session
/// while the journey itself keeps its slow pace.
///
/// [seed] offsets the starting colour: the app rolls a fresh random seed on
/// each launch, so every time you open the app you land on a different place's
/// palette, and it keeps stepping from there as you complete sessions.
WorldMap accentForSession(int sessionsCompleted, {int seed = 0}) =>
    kMaps[(seed + sessionsCompleted) % kMaps.length];
