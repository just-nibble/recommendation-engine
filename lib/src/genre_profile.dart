/// Genre normalization and consensus profile for recommendations.

const Set<String> kGenericGenreDenyList = {
  'fiction',
  'book',
  'books',
  'manga',
  'comic',
  'comics',
  'novel',
  'novels',
  'ebook',
  'ebooks',
  'literature',
  'general',
};

/// Minimal synonym map (expand carefully; keep deterministic).
const Map<String, String> kGenreSynonyms = {
  'sci-fi': 'science fiction',
  'scifi': 'science fiction',
  'science-fiction': 'science fiction',
  'ya': 'young adult',
  'young-adult': 'young adult',
};

String normalizeGenre(String raw) {
  var g = raw.trim().toLowerCase();
  g = g.replaceAll(RegExp(r'\s+'), ' ');
  g = g.replaceAll('_', ' ');
  return kGenreSynonyms[g] ?? g;
}

List<String> parseGenreString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(RegExp(r'[,;/|]'))
      .map(normalizeGenre)
      .where((g) => g.isNotEmpty)
      .toList();
}

List<String> normalizeGenres(Iterable<String> raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final r in raw) {
    final g = normalizeGenre(r);
    if (g.isEmpty || seen.contains(g)) continue;
    seen.add(g);
    out.add(g);
  }
  return out;
}

bool isGenericGenre(String normalized) =>
    kGenericGenreDenyList.contains(normalized);

/// Weighted genre key from gated seeds.
class GenreProfile {
  final Map<String, double> weights;
  final List<String> keys;

  const GenreProfile({required this.weights, required this.keys});

  bool get isEmpty => keys.isEmpty;

  static const empty = GenreProfile(weights: {}, keys: []);
}

/// Build a consensus genre profile.
///
/// When multiple seeds are present, keep genres that appear in at least
/// `ceil(n/2)` seeds or at least twice. Generic-only genres are dropped.
GenreProfile buildGenreProfile(
  List<List<String>> genresPerSeed, {
  List<double>? seedWeights,
}) {
  final n = genresPerSeed.length;
  if (n == 0) return GenreProfile.empty;

  final weights = seedWeights ?? List<double>.filled(n, 1.0);
  assert(weights.length == n);

  final occurrence = <String, int>{};
  final weighted = <String, double>{};

  for (var i = 0; i < n; i++) {
    final unique = normalizeGenres(genresPerSeed[i]);
    final w = weights[i];
    for (final g in unique) {
      if (isGenericGenre(g)) continue;
      occurrence[g] = (occurrence[g] ?? 0) + 1;
      weighted[g] = (weighted[g] ?? 0) + w;
    }
  }

  final minCount = n == 1 ? 1 : (n + 1) ~/ 2; // ceil(n/2)
  final kept = <String, double>{};
  for (final e in weighted.entries) {
    final count = occurrence[e.key] ?? 0;
    if (count >= minCount || count >= 2) {
      kept[e.key] = e.value;
    }
  }

  final keys = kept.keys.toList()
    ..sort((a, b) {
      final cmp = kept[b]!.compareTo(kept[a]!);
      if (cmp != 0) return cmp;
      return a.compareTo(b);
    });

  return GenreProfile(weights: Map.unmodifiable(kept), keys: keys);
}
