import 'catalog.dart';
import 'genre_profile.dart';
import 'metadata_enricher.dart';
import 'models.dart';
import 'quality_gate.dart';
import 'scoring.dart';

class _ResolvedSeed {
  final String title;
  final String? author;
  final RecommendationContentKind kind;
  final List<String> genres;
  final String? id;
  final SeedGateDecision gate;
  final double weight;
  final bool enriched;

  const _ResolvedSeed({
    required this.title,
    this.author,
    required this.kind,
    required this.genres,
    this.id,
    required this.gate,
    required this.weight,
    this.enriched = false,
  });
}

/// In-process recommendation engine. Depends only on a host [CatalogSource]
/// and an optional [MetadataEnricher].
class RecommendationService {
  final CatalogSource catalog;
  final MetadataEnricher? enricher;
  final RecommendationGateConfig gateConfig;

  /// When true (default) and [enricher] is set, fill missing seed genres/author.
  final bool enableEnrichment;

  RecommendationService(
    this.catalog, {
    this.enricher,
    this.gateConfig = RecommendationGateConfig.defaults,
    this.enableEnrichment = true,
  });

  Future<RecommendationResult> recommend(RecommendationRequest request) async {
    final diagnostics = <String>[];

    if (request.seeds.isEmpty) {
      diagnostics.add('no_seeds');
      return RecommendationResult(diagnostics: diagnostics);
    }

    final limit = request.limit.clamp(1, 50);
    final kinds = request.contentKinds;
    final allowEnrich = enableEnrichment && enricher != null;
    diagnostics.add(allowEnrich ? 'enrichment:on' : 'enrichment:off');

    final resolved = <_ResolvedSeed>[];
    for (final seed in request.seeds) {
      final r = await _resolveSeed(seed, allowEnrich: allowEnrich);
      if (r == null) {
        diagnostics.add('unresolved:${seed.title}');
        continue;
      }
      if (r.gate == SeedGateDecision.exclude) {
        diagnostics.add('gated_out:${r.title}');
        continue;
      }
      if (r.enriched) {
        diagnostics.add('enriched:${r.title}');
      }
      if (r.genres.isEmpty) {
        diagnostics.add('no_genres:${r.title}');
        continue;
      }
      resolved.add(r);
    }

    if (resolved.isEmpty) {
      diagnostics.add('no_gated_seeds');
      return RecommendationResult(diagnostics: diagnostics);
    }

    final profile = buildGenreProfile(
      resolved.map((s) => s.genres).toList(),
      seedWeights: resolved.map((s) => s.weight).toList(),
    );
    if (profile.isEmpty) {
      diagnostics.add('empty_genre_profile');
      return RecommendationResult(diagnostics: diagnostics);
    }
    diagnostics.add('genres:${profile.keys.join("|")}');

    final seedAuthors = resolved
        .map((s) => s.author)
        .whereType<String>()
        .where((a) => a.trim().isNotEmpty)
        .toList();

    final candidates = await catalog.listCandidates(
      kinds: kinds,
      scope: request.scope,
    );
    diagnostics.add('candidates:${candidates.length}');

    final scored = <ScoredCandidate>[];
    for (final c in candidates) {
      if (_isExcluded(c, resolved, request.exclude)) continue;

      final breakdown = scoreAgainstProfile(
        profile: profile,
        candidateGenres: c.genres,
        seedAuthors: seedAuthors,
        candidateAuthor: c.author,
      );
      if (breakdown.score <= 0) continue;

      scored.add(
        ScoredCandidate(
          title: c.title,
          author: c.author,
          kind: c.kind,
          genres: c.genres,
          id: c.id,
          coverPathOrUrl: c.coverPathOrUrl,
          sourceLabel: c.sourceLabel,
          score: breakdown.score,
          matchedGenres: breakdown.matchedGenres,
        ),
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return normalizeTitleKey(a.title).compareTo(normalizeTitleKey(b.title));
    });

    final split = request.limitEbook != null || request.limitManga != null;
    if (split) {
      final ebookCap = (request.limitEbook ?? 0).clamp(0, 50);
      final mangaCap = (request.limitManga ?? 0).clamp(0, 50);
      final ebooks = scored
          .where((s) => s.kind == RecommendationContentKind.ebook)
          .take(ebookCap)
          .map(_toItem)
          .toList();
      final manga = scored
          .where((s) => s.kind == RecommendationContentKind.manga)
          .take(mangaCap)
          .map(_toItem)
          .toList();
      return RecommendationResult(
        items: [...ebooks, ...manga],
        ebooks: ebooks,
        manga: manga,
        appliedGenreKeys: profile.keys,
        diagnostics: diagnostics,
      );
    }

    final items = scored.take(limit).map(_toItem).toList();
    return RecommendationResult(
      items: items,
      ebooks: items
          .where((i) => i.kind == RecommendationContentKind.ebook)
          .toList(),
      manga: items
          .where((i) => i.kind == RecommendationContentKind.manga)
          .toList(),
      appliedGenreKeys: profile.keys,
      diagnostics: diagnostics,
    );
  }

  RecommendationItem _toItem(ScoredCandidate s) {
    final reason = s.matchedGenres.isEmpty
        ? null
        : 'Shared: ${s.matchedGenres.take(3).join(', ')}';
    return RecommendationItem(
      title: s.title,
      author: s.author,
      kind: s.kind,
      score: s.score,
      matchedGenres: s.matchedGenres,
      reason: reason,
      id: s.id,
      coverPathOrUrl: s.coverPathOrUrl,
      sourceLabel: s.sourceLabel,
    );
  }

  Future<_ResolvedSeed?> _resolveSeed(
    RecommendationSeed seed, {
    required bool allowEnrich,
  }) async {
    final title = seed.title.trim();
    if (title.isEmpty) return null;

    CatalogItem? item;
    if (seed.id != null && seed.id!.isNotEmpty) {
      item = await catalog.findById(seed.id!);
    }
    item ??= await catalog.findByTitle(
      title: title,
      author: seed.author,
      kindHint: seed.kind,
    );

    var genres = normalizeGenres([
      ...seed.genres,
      ...?item?.genres,
    ]);
    var author = seed.author ?? item?.author;
    var kind = item?.kind ?? seed.kind ?? RecommendationContentKind.ebook;
    var resolvedTitle = item?.title ?? title;
    var id = item?.id ?? seed.id;
    var enriched = false;

    final needsEnrich = allowEnrich &&
        (genres.isEmpty || author == null || author.trim().isEmpty);

    if (needsEnrich && enricher != null) {
      final hit = await enricher!.enrich(
        title: resolvedTitle,
        author: author,
        kindHint: kind,
      );
      if (hit != null) {
        if (hit.hasGenres && genres.isEmpty) {
          genres = normalizeGenres(hit.genres);
          enriched = true;
        } else if (hit.hasGenres) {
          genres = normalizeGenres([...genres, ...hit.genres]);
          enriched = true;
        }
        author ??= hit.author;
        kind = hit.kind ?? kind;
        if (hit.title != null && hit.title!.trim().isNotEmpty) {
          resolvedTitle = hit.title!.trim();
        }
      }
    }

    // Catalog miss + no genres after enrichment → cannot recommend from seed.
    if (item == null && genres.isEmpty) {
      return null;
    }

    // Synthetic seed from enrichment / caller genres only.
    if (item == null) {
      final gate = evaluateSeedGate(
        kind: kind,
        signals: seed.signals,
        config: gateConfig,
      );
      return _ResolvedSeed(
        title: resolvedTitle,
        author: author,
        kind: kind,
        genres: genres,
        id: id,
        gate: gate,
        weight: gate.weight,
        enriched: enriched,
      );
    }

    final progress = seed.signals?.progress ?? item.progress;
    var finished = seed.signals?.finished ?? item.finished;
    if (finished == null) {
      if (item.kind == RecommendationContentKind.ebook) {
        finished =
            (item.progress ?? 0) >= gateConfig.finishedEbookProgress;
      } else {
        finished = item.readingStatus == 2;
      }
    }

    final gate = evaluateSeedGate(
      kind: kind,
      progress: progress,
      finished: finished,
      mangaReadingStatus: item.readingStatus,
      signals: seed.signals,
      config: gateConfig,
    );

    return _ResolvedSeed(
      title: resolvedTitle,
      author: author,
      kind: kind,
      genres: genres,
      id: item.id,
      gate: gate,
      weight: gate.weight,
      enriched: enriched,
    );
  }

  bool _isExcluded(
    CatalogItem c,
    List<_ResolvedSeed> seeds,
    List<RecommendationExclusion> exclude,
  ) {
    for (final s in seeds) {
      if (s.id != null && c.id == s.id) return true;
      if (titlesMatch(c.title, s.title) && c.kind == s.kind) return true;
    }

    for (final e in exclude) {
      if (e.id != null && c.id == e.id) return true;
      if (e.title != null && titlesMatch(c.title, e.title!)) {
        if (e.kind == null || e.kind == c.kind) {
          if (e.author == null ||
              e.author!.trim().isEmpty ||
              (c.author ?? '').trim().toLowerCase() ==
                  e.author!.trim().toLowerCase()) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
