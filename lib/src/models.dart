/// Public DTOs for the recommendation engine.

enum RecommendationContentKind {
  ebook,
  manga, // includes manhwa / comics in v1
}

enum RecommendationCandidateScope {
  /// Only items returned by [CatalogSource.listCandidates] for library scope.
  libraryOnly,

  /// Library plus metadata / discover hits (host decides what to return).
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

  /// Host-opaque id (e.g. `book:12`, `manga:3`).
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
