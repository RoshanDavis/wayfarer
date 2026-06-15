import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/tiers.dart';

void main() {
  group('tier boundaries', () {
    test('base tiers activate exactly at their unlock level', () {
      expect(tierForLevel(1).name, 'First steps');
      expect(tierForLevel(9).name, 'First steps');
      expect(tierForLevel(10).name, 'Wanderer');
      expect(tierForLevel(19).name, 'Wanderer');
      expect(tierForLevel(20).name, 'Strider');
      expect(tierForLevel(60).name, 'Gale runner');
      expect(tierForLevel(199).name, 'Solar wind');
      expect(tierForLevel(200).name, 'The Eternal Wayfarer');
    });

    test('tier table covers levels 1..200 every 10', () {
      expect(kBaseTiers.length, 21);
      expect(kBaseTiers.first.level, 1);
      expect(kBaseTiers.last.level, 200);
      for (var i = 1; i < kBaseTiers.length; i++) {
        expect(kBaseTiers[i].level - kBaseTiers[i - 1].level,
            i == 1 ? 9 : 10);
      }
    });

    test('procedural tiers continue every 25 levels past 200', () {
      expect(tierForLevel(224).name, 'The Eternal Wayfarer');
      expect(tierForLevel(225).name, 'The Eternal Wayfarer II');
      expect(tierForLevel(249).name, 'The Eternal Wayfarer II');
      expect(tierForLevel(250).name, 'The Eternal Wayfarer III');
      expect(tierForLevel(300).name, 'The Eternal Wayfarer V');
      // Truly infinite — no content cliff.
      expect(tierForLevel(1200).name, 'The Eternal Wayfarer XLI');
      expect(tierForLevel(10200).name, 'The Eternal Wayfarer CDI');
    });

    test('roman numerals', () {
      expect(romanNumeral(1), 'I');
      expect(romanNumeral(4), 'IV');
      expect(romanNumeral(9), 'IX');
      expect(romanNumeral(14), 'XIV');
      expect(romanNumeral(40), 'XL');
      expect(romanNumeral(1987), 'MCMLXXXVII');
    });
  });

  group('tiersReachedBetween', () {
    test('single tier crossing', () {
      expect(tiersReachedBetween(9, 10), [const PaceTier(10, 'Wanderer')]);
      expect(tiersReachedBetween(10, 19), isEmpty);
    });

    test('multi-tier jump', () {
      final reached = tiersReachedBetween(28, 45);
      expect(reached.map((t) => t.name).toList(),
          ['Pathfinder', 'Trailblazer']);
    });

    test('crossing from base into procedural tiers', () {
      final reached = tiersReachedBetween(195, 230);
      expect(reached.map((t) => t.name).toList(),
          ['The Eternal Wayfarer', 'The Eternal Wayfarer II']);
    });

    test('procedural to procedural', () {
      final reached = tiersReachedBetween(226, 280);
      expect(reached.map((t) => t.name).toList(),
          ['The Eternal Wayfarer III', 'The Eternal Wayfarer IV']);
    });

    test('no crossing when level does not move past a boundary', () {
      expect(tiersReachedBetween(11, 19), isEmpty);
      expect(tiersReachedBetween(201, 224), isEmpty);
    });
  });

  group('tier metadata', () {
    test('next tier lookup', () {
      expect(nextTierAfter(1).name, 'Wanderer');
      expect(nextTierAfter(199).name, 'The Eternal Wayfarer');
      expect(nextTierAfter(200).name, 'The Eternal Wayfarer II');
      expect(nextTierAfter(225).name, 'The Eternal Wayfarer III');
    });

    test('tier index runs continuously into procedural tiers', () {
      expect(tierForLevel(1).index, 0);
      expect(tierForLevel(10).index, 1);
      expect(tierForLevel(200).index, 20);
      expect(tierForLevel(225).index, 21);
      expect(tierForLevel(250).index, 22);
    });

    test('tier pace matches the pace curve at unlock level', () {
      expect(tierForLevel(50).paceKmh, closeTo(27.5, 0.1));
      expect(tierForLevel(110).paceKmh, closeTo(1595, 1595 * 0.001));
    });
  });
}
