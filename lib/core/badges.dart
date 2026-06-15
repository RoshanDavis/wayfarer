/// Badge catalog: pace tiers, maps, speed comparisons, odometer milestones.
/// Pure Dart. Badges are identified by stable string ids persisted in state.
library;

import 'comparisons.dart';
import 'maps.dart';
import 'tiers.dart';

enum BadgeCategory { tier, map, comparison, odometer }

/// A resolved badge for display.
class Badge {
  final String id;
  final BadgeCategory category;
  final String name;

  /// The quiet line shown when awarded and on the Journey screen.
  final String line;

  const Badge(this.id, this.category, this.name, this.line);
}

// ---------------------------------------------------------------------------
// Odometer milestones — famous real distances, human to cosmic.
// ---------------------------------------------------------------------------

class OdometerMilestone {
  final String id;
  final double km;
  final String name;
  final String line;
  const OdometerMilestone(this.id, this.km, this.name, this.line);
}

const List<OdometerMilestone> kOdometerMilestones = [
  OdometerMilestone('odo-1mi', 1.609, 'First Mile',
      'You have run your first mile.'),
  OdometerMilestone('odo-5', 5, 'First 5K',
      'You have run your first five kilometers.'),
  OdometerMilestone('odo-10', 10, 'First 10K',
      'You have run your first ten kilometers.'),
  OdometerMilestone('odo-21', 21.1, 'Half Marathon',
      'You have run a half marathon.'),
  OdometerMilestone('odo-42', 42.2, 'Marathon', 'You have run a marathon.'),
  OdometerMilestone('odo-50', 50, '50K Ultra',
      'You have run a fifty-kilometer ultramarathon.'),
  OdometerMilestone('odo-89', 89, 'Comrades Marathon',
      'You have run the Comrades Marathon.'),
  OdometerMilestone('odo-100', 100, '100 km Ultra',
      'You have run a hundred-kilometer ultramarathon.'),
  OdometerMilestone('odo-217', 217, 'Badwater 135',
      'You have run the length of the Badwater 135.'),
  OdometerMilestone('odo-250', 250, 'Marathon des Sables',
      'You have run the Marathon des Sables.'),
  OdometerMilestone('odo-800', 800, 'Camino de Santiago',
      'You have run the Camino de Santiago.'),
  OdometerMilestone('odo-1609', 1609, 'A Thousand Miles',
      'You have run a thousand miles.'),
  OdometerMilestone('odo-3500', 3500, 'Appalachian Trail',
      'You have run the length of the Appalachian Trail.'),
  OdometerMilestone('odo-4265', 4265, 'Pacific Crest Trail',
      'You have run the Pacific Crest Trail.'),
  OdometerMilestone('odo-6400', 6400, 'Silk Road',
      'You have run the Silk Road.'),
  OdometerMilestone('odo-9289', 9289, 'Trans-Siberian Railway',
      'You have run the length of the Trans-Siberian Railway.'),
  OdometerMilestone('odo-10500', 10500, 'Cape Town to Cairo',
      'You have run from Cape Town to Cairo.'),
  OdometerMilestone('odo-21196', 21196, 'Great Wall of China',
      'You have run the length of the Great Wall of China.'),
  OdometerMilestone('odo-30000', 30000, 'Pan-American Highway',
      'You have run the Pan-American Highway.'),
  OdometerMilestone('odo-35877', 35877, 'Coastline of Australia',
      'You have run the coastline of Australia.'),
  OdometerMilestone('odo-40075', 40075, "Earth's Circumference",
      'You have run all the way around the Earth.'),
  OdometerMilestone('odo-100000', 100000, '100,000 Kilometers',
      'You have run one hundred thousand kilometers.'),
  OdometerMilestone('odo-384400', 384400, 'Earth to the Moon',
      'You have run from the Earth to the Moon.'),
  OdometerMilestone('odo-1000000', 1000000, 'One Million Kilometers',
      'You have run one million kilometers.'),
];

/// Milestones crossed when the lifetime odometer rises from [oldKm]
/// (exclusive) to [newKm] (inclusive), ascending.
List<OdometerMilestone> milestonesCrossedBetween(double oldKm, double newKm) =>
    [
      for (final m in kOdometerMilestones)
        if (m.km > oldKm && m.km <= newKm) m,
    ];

/// The greatest milestone at or below [km], for the Journey comparison line
/// ("Farther than the Camino de Santiago"). Null before the first.
OdometerMilestone? milestonePassed(double km) {
  OdometerMilestone? passed;
  for (final m in kOdometerMilestones) {
    if (m.km <= km) passed = m;
  }
  return passed;
}

/// The next milestone past [km], if any remain.
OdometerMilestone? nextMilestone(double km) {
  for (final m in kOdometerMilestones) {
    if (m.km > km) return m;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Badge id scheme
// ---------------------------------------------------------------------------

String tierBadgeId(int tierLevel) => 'tier-$tierLevel';
String mapBadgeId(int mapIndex) => 'map-$mapIndex';
String comparisonBadgeId(String comparisonId) => 'cmp-$comparisonId';
// Odometer milestone ids are used directly ('odo-…').

/// Resolves any persisted badge id into a displayable [Badge].
/// Returns null for ids that no longer resolve (defensive; should not occur).
Badge? resolveBadge(String id) {
  if (id.startsWith('tier-')) {
    final level = int.tryParse(id.substring(5));
    if (level == null) return null;
    final tier = tierForLevel(level);
    return Badge(id, BadgeCategory.tier, tier.name,
        'You became ${_withArticle(tier.name)}.');
  }
  if (id.startsWith('map-')) {
    final index = int.tryParse(id.substring(4));
    if (index == null || index < 0 || index >= kMaps.length) return null;
    final map = kMaps[index];
    return Badge(id, BadgeCategory.map, map.name, 'Reached ${map.name}.');
  }
  if (id.startsWith('cmp-')) {
    final c = comparisonById(id.substring(4));
    if (c == null) return null;
    return Badge(id, BadgeCategory.comparison, c.name, c.line);
  }
  for (final m in kOdometerMilestones) {
    if (m.id == id) return Badge(id, BadgeCategory.odometer, m.name, m.line);
  }
  return null;
}

String _withArticle(String name) {
  if (name.startsWith('The ')) return name.replaceFirst('The ', 'the ');
  return name;
}
