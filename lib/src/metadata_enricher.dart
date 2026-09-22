import 'models.dart';

/// Result of a host-side metadata lookup (Open Library, Google Books, etc.).
class MetadataEnrichment {
  final String? title;
  final String? author;
  final RecommendationContentKind? kind;
  final List<String> genres;
  final String? coverUrl;
  final String sourceLabel;

  const MetadataEnrichment({
    this.title,
    this.author,
    this.kind,
    this.genres = const [],
    this.coverUrl,
    this.sourceLabel = 'metadata',
  });

  bool get hasGenres => genres.isNotEmpty;
}

/// Optional host-implemented enricher. The engine never performs HTTP itself.
///
/// Typical Koma wiring: call existing Rust `lookup_books` / metadata services
/// and map the hit into [MetadataEnrichment].
abstract class MetadataEnricher {
  Future<MetadataEnrichment?> enrich({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  });
}

/// In-memory enricher for tests and demos.
class InMemoryMetadataEnricher implements MetadataEnricher {
  /// Keys are normalized titles (`trim` + lower case + collapsed spaces).
  final Map<String, MetadataEnrichment> byTitle;

  InMemoryMetadataEnricher(this.byTitle);

  static String keyFor(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Future<MetadataEnrichment?> enrich({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  }) async {
    return byTitle[keyFor(title)];
  }
}
