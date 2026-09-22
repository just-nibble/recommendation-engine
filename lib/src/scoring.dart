import 'genre_profile.dart';
import 'models.dart';

class ScoredCandidate {
  final String title;
  final String? author;
  final RecommendationContentKind kind;
  final List<String> genres;
  final String? id;
  final String? coverPathOrUrl;
  final String sourceLabel;
  final double score;
  final List<String> matchedGenres;

  const ScoredCandidate({
    required this.title,
    this.author,
    required this.kind,
    required this.genres,
    this.id,
    this.coverPathOrUrl,
    this.sourceLabel = 'library',
    required this.score,
    required this.matchedGenres,
  });
}

class ScoreBreakdown {
  final double score;
  final List<String> matchedGenres;
  final bool strongMatch;

  const ScoreBreakdown({
    required this.score,
    required this.matchedGenres,
    required this.strongMatch,
  });
}

/// Score a candidate against a genre [profile].
ScoreBreakdown scoreAgainstProfile({
  required GenreProfile profile,
  required List<String> candidateGenres,
  required List<String> seedAuthors,
  String? candidateAuthor,
  double kindMatchBonus = 0,
  double authorBonus = 0.5,
}) {
  if (profile.isEmpty) {
    return const ScoreBreakdown(
      score: 0,
      matchedGenres: [],
      strongMatch: false,
    );
  }

  final cand = normalizeGenres(candidateGenres)
      .where((g) => !isGenericGenre(g))
      .toSet();
  final matched = <String>[];
  var score = 0.0;

  for (final key in profile.keys) {
    if (cand.contains(key)) {
      matched.add(key);
      score += profile.weights[key] ?? 1.0;
    }
  }

  final meaningfulProfileCount =
      profile.keys.where((k) => !isGenericGenre(k)).length;
  final strongMatch = matched.length >= 2 ||
      (matched.length == 1 && meaningfulProfileCount == 1);

  if (matched.isEmpty) {
    return const ScoreBreakdown(
      score: 0,
      matchedGenres: [],
      strongMatch: false,
    );
  }

  if (!strongMatch && matched.length == 1) {
    score *= 0.25;
  }

  if (candidateAuthor != null &&
      candidateAuthor.trim().isNotEmpty &&
      seedAuthors.isNotEmpty) {
    final ca = _normAuthor(candidateAuthor);
    if (seedAuthors.any((a) => _normAuthor(a) == ca)) {
      score += authorBonus;
    }
  }

  score += kindMatchBonus;
  return ScoreBreakdown(
    score: score,
    matchedGenres: matched,
    strongMatch: strongMatch,
  );
}

String _normAuthor(String a) =>
    a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String normalizeTitleKey(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool titlesMatch(String a, String b) =>
    normalizeTitleKey(a) == normalizeTitleKey(b);
