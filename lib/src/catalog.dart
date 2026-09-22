import 'models.dart';

/// Normalized library / catalog row supplied by the host app.
class CatalogItem {
  /// Host-opaque stable id (e.g. `book:42`, `manga:7`).
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

  /// Candidate pool for ranking (typically the user's library).
  Future<List<CatalogItem>> listCandidates({
    Set<RecommendationContentKind>? kinds,
    RecommendationCandidateScope scope = RecommendationCandidateScope.libraryOnly,
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
    RecommendationCandidateScope scope = RecommendationCandidateScope.libraryOnly,
  }) async {
    if (kinds == null || kinds.isEmpty) return List.unmodifiable(items);
    return items.where((i) => kinds.contains(i.kind)).toList(growable: false);
  }
}
