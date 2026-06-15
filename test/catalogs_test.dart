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
    test('there are 24 maps with the spec names in order', () {
      expect(kMaps.length, 24);
      expect(kMaps.first.name, 'The Garden');
      expect(kMaps[2].name, 'Dune Sea');
      expect(kMaps[23].name, 'The Stratosphere');
    });

    test('map advances exactly every 3 completed sets', () {
      expect(mapIndexForSets(0), 0);
      expect(mapIndexForSets(1), 0);
      expect(mapIndexForSets(2), 0);
      expect(mapIndexForSets(3), 1);
      expect(mapIndexForSets(5), 1);
      expect(mapIndexForSets(6), 2);
      expect(mapIndexForSets(35), 11);
    });

    test('mapChangedAtSet flags only multiples of 3', () {
      expect(mapChangedAtSet(0), isFalse);
      expect(mapChangedAtSet(1), isFalse);
      expect(mapChangedAtSet(3), isTrue);
      expect(mapChangedAtSet(4), isFalse);
      expect(mapChangedAtSet(6), isTrue);
    });

    test('cycle loops past 24 maps with a rising cycle counter', () {
      expect(mapIndexForSets(72), 0); // 72 sets = 24 maps later, wrapped
      expect(mapCycleForSets(71), 0);
      expect(mapCycleForSets(72), 1);
      expect(mapForSets(75).name, 'Golden Plains');
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
