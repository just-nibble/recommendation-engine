import 'package:recommendation_engine/recommendation_engine.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeGenre', () {
    test('trims, lowercases, and maps synonyms', () {
      expect(normalizeGenre('  Dark Fantasy '), 'dark fantasy');
      expect(normalizeGenre('Sci-Fi'), 'science fiction');
      expect(normalizeGenre('YA'), 'young adult');
    });
  });

  group('buildGenreProfile', () {
    test('keeps all non-generic genres for a single seed', () {
      final profile = buildGenreProfile([
        ['dark fantasy', 'supernatural', 'fiction'],
      ]);
      expect(profile.keys, containsAll(['dark fantasy', 'supernatural']));
      expect(profile.keys, isNot(contains('fiction')));
    });

    test('requires consensus across multiple seeds', () {
      final profile = buildGenreProfile([
        ['dark fantasy', 'supernatural', 'romance'],
        ['dark fantasy', 'supernatural', 'horror'],
        ['slice of life'],
      ]);
      expect(profile.keys, containsAll(['dark fantasy', 'supernatural']));
      expect(profile.keys, isNot(contains('romance')));
    });
  });

  group('evaluateSeedGate', () {
    test('excludes near-zero ebook progress', () {
      expect(
        evaluateSeedGate(
          kind: RecommendationContentKind.ebook,
          progress: 0.01,
        ),
        SeedGateDecision.exclude,
      );
    });

    test('excludes idle high-time low-progress signals', () {
      expect(
        evaluateSeedGate(
          kind: RecommendationContentKind.ebook,
          signals: const ReadingSignals(
            totalReadingSeconds: 5 * 3600,
            progress: 0.01,
          ),
        ),
        SeedGateDecision.exclude,
      );
    });
  });

  group('scoreAgainstProfile', () {
    test('ranks multi-tag overlap above single weak tag', () {
      final profile = buildGenreProfile([
        ['dark fantasy', 'supernatural'],
      ]);
      final strong = scoreAgainstProfile(
        profile: profile,
        candidateGenres: ['dark fantasy', 'supernatural', 'horror'],
        seedAuthors: const [],
      );
      final weak = scoreAgainstProfile(
        profile: profile,
        candidateGenres: ['dark fantasy'],
        seedAuthors: const [],
      );
      expect(strong.score, greaterThan(weak.score));
    });
  });
}
