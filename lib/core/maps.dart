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

class WorldMap {
  final String name;

  /// HSL hue in degrees — the single accent hue of the whole UI on this map.
  final double hue;

  /// Base saturation for the tonal ramp (0..1). Low values give the gray
  /// maps (Salt Flats, Misty Moors, Volcanic Fields) their hush.
  final double saturation;

  final Terrain terrain;
  final MapDecor decor;

  const WorldMap(this.name, this.hue, this.saturation, this.terrain,
      [this.decor = MapDecor.none]);
}

/// The 25 maps, in journey order. The cycle loops with subtle variation.
const List<WorldMap> kMaps = [
  WorldMap('The Garden', 100, 0.42, Terrain.softHills),
  WorldMap('Prairie', 45, 0.55, Terrain.flatPlains),
  WorldMap('Dune Sea', 36, 0.52, Terrain.dunes),
  WorldMap('Pine Ridge', 150, 0.38, Terrain.jaggedTreeline),
  WorldMap('Coastal Cliffs', 212, 0.38, Terrain.cliffsSea),
  WorldMap('Canyon', 16, 0.52, Terrain.layeredMesas),
  WorldMap('Wildflower Hills', 272, 0.36, Terrain.softHills),
  WorldMap('Salt Flats', 205, 0.10, Terrain.flatPlains),
  WorldMap('Bamboo Grove', 160, 0.42, Terrain.verticalGrove),
  WorldMap('Misty Moors', 310, 0.13, Terrain.softHills),
  WorldMap('Savanna', 38, 0.48, Terrain.flatPlains, MapDecor.loneTrees),
  WorldMap('Fjords', 208, 0.44, Terrain.cliffsSea),
  WorldMap('Blossom Orchard', 345, 0.40, Terrain.softHills,
      MapDecor.orchardTrees),
  WorldMap('Sandstone Mesa', 10, 0.52, Terrain.layeredMesas),
  WorldMap('Rice Terraces', 175, 0.42, Terrain.steppedHills),
  WorldMap('Tundra', 195, 0.32, Terrain.flatPlains),
  WorldMap('Hillside Grove', 72, 0.36, Terrain.softHills, MapDecor.orchardTrees),
  WorldMap('Volcanic Fields', 12, 0.18, Terrain.jaggedRidges),
  WorldMap('Glacier Pass', 187, 0.46, Terrain.jaggedRidges),
  WorldMap('Eroded Hills', 14, 0.52, Terrain.layeredMesas),
  WorldMap('Mangrove Delta', 155, 0.38, Terrain.flatPlains),
  WorldMap('Night Desert', 255, 0.42, Terrain.dunes),
  WorldMap('Starlit Steppe', 265, 0.42, Terrain.flatPlains),
  WorldMap('The Stratosphere', 228, 0.38, Terrain.cloudLayers),
  WorldMap('Maple Wood', 28, 0.50, Terrain.jaggedTreeline),
];

/// Index into [kMaps] for [level]: advances every level and loops (level 1 → 0,
/// level 26 → 0). Consecutive levels always differ, so any level-up changes it.
int mapIndexForLevel(int level) => (level - 1) % kMaps.length;

/// How many full [kMaps]-length loops the player has completed at [level].
/// Cycles past the first re-render with subtle variation (shifted lightness,
/// reseeded terrain).
int mapCycleForLevel(int level) => (level - 1) ~/ kMaps.length;

WorldMap mapForLevel(int level) => kMaps[mapIndexForLevel(level)];

/// Accent palette (hue + saturation) for [sessionsCompleted]: steps through the
/// 25 curated palettes once per session, independent of the terrain map. [seed]
/// (rolled fresh each launch) offsets the start, so each open lands on a new place.
WorldMap accentForSession(int sessionsCompleted, {int seed = 0}) =>
    kMaps[(seed + sessionsCompleted) % kMaps.length];
