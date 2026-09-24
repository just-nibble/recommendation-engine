/// Public DTOs for the recommendation engine.

enum RecommendationContentKind {
  ebook,
  manga, // includes manhwa / comics in v1
}

enum RecommendationCandidateScope {
  /// Only local library rows from [CatalogSource.listCandidates].
  libraryOnly,

  /// Library plus Discover / extension / metadata hits supplied by the host.
  ///
  /// The engine passes [genreHints] into [CatalogSource.listCandidates] so the
  /// host can search installed manga sources (and optional ebook metadata).
  libraryAndDiscover,

  /// Legacy alias of [libraryAndDiscover] (same behavior).
  libraryAndMetadata,
}

class ReadingSignals {
  final double? progress;
  final bool? finished;
  final int? openCount;
  final int? totalReadingSeconds;
  final double? avgSecondsPerPage;
  final int? currentPage;
  final int? totalPages;

  const ReadingSignals({
    this.progress,
    this.finished,
    this.openCount,
    this.totalReadingSeconds,
    this.avgSecondsPerPage,
    this.currentPage,
    this.totalPages,
  });
}

class RecommendationExclusion {
  final String? title;
  final String? author;
  final RecommendationContentKind? kind;

  /// Host-opaque id (e.g. `book:12`, `manga:3`, `ext:…`).
  final String? id;

  const RecommendationExclusion({
    this.title,
    this.author,
    this.kind,
    this.id,
  });
}

class RecommendationSeed {
  final String title;
  final String? author;
  final RecommendationContentKind? kind;
  final List<String> genres;

  /// Host-opaque id when known.
  final String? id;
  final ReadingSignals? signals;

  const RecommendationSeed({
    required this.title,
    this.author,
    this.kind,
    this.genres = const [],
    this.id,
    this.signals,
  });
}

class RecommendationRequest {
  final List<RecommendationSeed> seeds;
  final int limit;
  final int? limitEbook;
  final int? limitManga;
  final Set<RecommendationContentKind>? contentKinds;
  final List<RecommendationExclusion> exclude;
  final RecommendationCandidateScope scope;

  const RecommendationRequest({
    required this.seeds,
    this.limit = 5,
    this.limitEbook,
    this.limitManga,
    this.contentKinds,
    this.exclude = const [],
    this.scope = RecommendationCandidateScope.libraryOnly,
  });

  /// True when the host should also supply Discover / extension candidates.
  bool get wantsExternalCandidates =>
      scope == RecommendationCandidateScope.libraryAndDiscover ||
      scope == RecommendationCandidateScope.libraryAndMetadata;
}

class RecommendationItem {
  final String title;
  final String? author;
  final RecommendationContentKind kind;
  final double score;
  final List<String> matchedGenres;
  final String? reason;
  final String? id;
  final String? coverPathOrUrl;
  final String? sourceLabel;

  /// Extension source id when this is a Discover / catalogue hit.
  final String? sourceId;

  /// Extension manga URL when this is a Discover / catalogue hit.
  final String? sourceUrl;

  /// Whether the title is already in the user's library.
  final bool inLibrary;

  const RecommendationItem({
    required this.title,
    this.author,
    required this.kind,
    required this.score,
    this.matchedGenres = const [],
    this.reason,
    this.id,
    this.coverPathOrUrl,
    this.sourceLabel,
    this.sourceId,
    this.sourceUrl,
    this.inLibrary = true,
  });
}

class RecommendationResult {
  final List<RecommendationItem> items;
  final List<RecommendationItem> ebooks;
  final List<RecommendationItem> manga;
  final List<String> appliedGenreKeys;
  final List<String> diagnostics;

  const RecommendationResult({
    this.items = const [],
    this.ebooks = const [],
    this.manga = const [],
    this.appliedGenreKeys = const [],
    this.diagnostics = const [],
  });

  static const empty = RecommendationResult();
}
