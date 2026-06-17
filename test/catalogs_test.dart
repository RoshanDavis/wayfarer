import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/badges.dart';
import 'package:wayfarer/core/comparisons.dart';
import 'package:wayfarer/core/game_math.dart';
import 'package:wayfarer/core/maps.dart';

void main() {
  group('speed comparisons', () {
    test('table is ascending and ids unique', () {
      for (var i = 1; i < kComparisons.length; i++) {
        expect(kComparisons[i].kmh, greaterThan(kComparisons[i - 1].kmh));
      }
      expect(kComparisons.map((c) => c.id).toSet().length, kComparisons.length);
    });

    test('crossing is exclusive of old pace, inclusive of new', () {
      expect(crossingsBetween(4.9, 5.0).map((c) => c.id), ['walking-human']);
      expect(crossingsBetween(5.0, 5.1), isEmpty);
      expect(crossingsBetween(4.9, 4.95), isEmpty);
    });

    test('a large jump crosses several at once', () {
      final crossed = crossingsBetween(30, 150).map((c) => c.id).toList();
      expect(crossed, [
        'sprinting-human',
        'galloping-horse',
        'ostrich',
        'cheetah',
        'highway-car'
      ]);
    });

    test('galloping horse falls around level 55-56 as paces compound', () {
      expect(paceKmh(55), lessThan(40));
      expect(paceKmh(56), greaterThan(40));
      expect(crossingsBetween(paceKmh(55), paceKmh(56)).map((c) => c.id),
          ['galloping-horse']);
    });
  });

  group('maps', () {
    test('there are 25 maps with the spec names in order', () {
      expect(kMaps.length, 25);
      expect(kMaps.first.name, 'The Garden');
      expect(kMaps[2].name, 'Dune Sea');
      expect(kMaps[23].name, 'The Stratosphere');
      expect(kMaps[24].name, 'Maple Wood');
    });

    test('the map advances every level and loops past the end', () {
      expect(mapIndexForLevel(1), 0);
      expect(mapIndexForLevel(2), 1);
      expect(mapIndexForLevel(25), 24);
      expect(mapIndexForLevel(26), 0); // wraps to the first map
      expect(mapIndexForLevel(27), 1);
      expect(mapForLevel(26).name, 'The Garden');
    });

    test('consecutive levels always land on a different map', () {
      for (var l = 1; l <= 200; l++) {
        expect(mapIndexForLevel(l), isNot(mapIndexForLevel(l + 1)));
      }
    });

    test('cycle counter rises once per full loop of the maps', () {
      expect(mapCycleForLevel(1), 0);
      expect(mapCycleForLevel(25), 0);
      expect(mapCycleForLevel(26), 1);
      expect(mapCycleForLevel(50), 1);
      expect(mapCycleForLevel(51), 2);
    });
  });

  group('odometer milestones', () {
    test('milestones are ascending famous distances', () {
      for (var i = 1; i < kOdometerMilestones.length; i++) {
        expect(kOdometerMilestones[i].km,
            greaterThan(kOdometerMilestones[i - 1].km));
      }
      expect(kOdometerMilestones.first.km, closeTo(1.609, 1e-9));
      expect(kOdometerMilestones.last.km, 1000000);
    });

    test('crossing detection is exclusive-inclusive', () {
      expect(milestonesCrossedBetween(0, 5).map((m) => m.id),
          ['odo-1mi', 'odo-5']);
      expect(milestonesCrossedBetween(5, 9.9), isEmpty);
      expect(milestonesCrossedBetween(4.9, 45).map((m) => m.id),
          ['odo-5', 'odo-10', 'odo-21', 'odo-42']);
    });

    test('passed and next milestone lookups', () {
      expect(milestonePassed(1), isNull);
      expect(milestonePassed(900)!.name, 'Camino de Santiago');
      expect(nextMilestone(900)!.name, 'A Thousand Miles');
      expect(nextMilestone(2000000), isNull);
    });
  });

  group('badge resolution', () {
    test('every badge id form resolves to a displayable badge', () {
      expect(resolveBadge('tier-60')!.name, 'Gale runner');
      expect(resolveBadge('tier-225')!.name, 'The Eternal Wayfarer II');
      expect(resolveBadge('map-2')!.line, 'Reached Dune Sea.');
      expect(resolveBadge('cmp-galloping-horse')!.line,
          'You now outrun a galloping horse.');
      expect(resolveBadge('odo-800')!.line,
          'You have run the Camino de Santiago.');
    });

    test('unknown ids resolve to null, not a crash', () {
      expect(resolveBadge('nonsense'), isNull);
      expect(resolveBadge('map-99'), isNull);
    });
  });
}
