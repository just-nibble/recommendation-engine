import 'models.dart';

/// Normalized library / catalog / Discover row supplied by the host app.
class CatalogItem {
  /// Host-opaque stable id.
  ///
  /// Conventions:
  /// - library ebook: `book:{isarId}`
  /// - library manga: `manga:{isarId}`
  /// - extension hit: `ext:{urlEncodedSourceId}:{urlEncodedUrl}`
  final String id;
  final String title;
  final String? author;
  final RecommendationContentKind kind;
  final List<String> genres;
  final double? progress;
  final bool? finished;

  /// Host manga-style status: 0 unread / 1 reading / 2 read (optional).
  final int? readingStatus;
  final String? coverPathOrUrl;
  final String sourceLabel;

  /// True when already in the user's library. Discover hits should be `false`.
  final bool inLibrary;

  /// Extension / catalogue identity (Discover hits).
  final String? sourceId;
  final String? sourceUrl;

  const CatalogItem({
    required this.id,
    required this.title,
    this.author,
    required this.kind,
    this.genres = const [],
    this.progress,
    this.finished,
    this.readingStatus,
    this.coverPathOrUrl,
    this.sourceLabel = 'library',
    this.inLibrary = true,
    this.sourceId,
    this.sourceUrl,
  });
}

/// Host-implemented bridge between the engine and the app catalog.
abstract class CatalogSource {
  /// Resolve by opaque [id].
  Future<CatalogItem?> findById(String id);

  /// Resolve by title (case-insensitive), optional author and kind hint.
  Future<CatalogItem?> findByTitle({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  });

  /// Candidate pool for ranking.
  ///
  /// When [scope] is [RecommendationCandidateScope.libraryAndDiscover] (or the
  /// legacy [RecommendationCandidateScope.libraryAndMetadata] alias), the host
  /// SHOULD also return Discover / extension hits. Use [genreHints] (consensus
  /// genres from gated seeds) as search queries against installed sources.
  /// Cap roughly at [softLimit].
  Future<List<CatalogItem>> listCandidates({
    Set<RecommendationContentKind>? kinds,
    RecommendationCandidateScope scope =
        RecommendationCandidateScope.libraryOnly,
    List<String> genreHints = const [],
    int softLimit = 80,
  });
}

/// Simple in-memory [CatalogSource] for tests and demos.
class InMemoryCatalogSource implements CatalogSource {
  final List<CatalogItem> items;

  InMemoryCatalogSource(this.items);

  @override
  Future<CatalogItem?> findById(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<CatalogItem?> findByTitle({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  }) async {
    final key = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final matches = items.where((i) {
      if (kindHint != null && i.kind != kindHint) return false;
      final t = i.title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      return t == key;
    }).toList();
    if (matches.isEmpty) return null;
    if (author == null || author.trim().isEmpty) return matches.first;
    final a = author.trim().toLowerCase();
    for (final m in matches) {
      if ((m.author ?? '').trim().toLowerCase() == a) return m;
    }
    return matches.first;
  }

  @override
  Future<List<CatalogItem>> listCandidates({
    Set<RecommendationContentKind>? kinds,
    RecommendationCandidateScope scope =
        RecommendationCandidateScope.libraryOnly,
    List<String> genreHints = const [],
    int softLimit = 80,
  }) async {
    Iterable<CatalogItem> pool = items;
    if (!scopeWantsExternal(scope)) {
      pool = pool.where((i) => i.inLibrary);
    }
    if (kinds != null && kinds.isNotEmpty) {
      pool = pool.where((i) => kinds.contains(i.kind));
    }
    // When external is requested and genreHints are set, prefer items that
    // share at least one hint (library items always included).
    if (scopeWantsExternal(scope) && genreHints.isNotEmpty) {
      final hints = genreHints.map((g) => g.toLowerCase()).toSet();
      pool = pool.where((i) {
        if (i.inLibrary) return true;
        return i.genres.any((g) => hints.contains(g.toLowerCase()));
      });
    }
    return pool.take(softLimit).toList(growable: false);
  }
}

bool scopeWantsExternal(RecommendationCandidateScope scope) =>
    scope == RecommendationCandidateScope.libraryAndDiscover ||
    scope == RecommendationCandidateScope.libraryAndMetadata;
