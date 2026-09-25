import 'package:recommendation_engine/recommendation_engine.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryCatalogSource catalog;
  late RecommendationService service;

  setUp(() {
    catalog = InMemoryCatalogSource([
      const CatalogItem(
        id: 'book:1',
        title: 'Seed of Shadows',
        author: 'A. Author',
        kind: RecommendationContentKind.ebook,
        genres: ['Dark Fantasy', 'Supernatural'],
        progress: 1.0,
        finished: true,
      ),
      const CatalogItem(
        id: 'book:2',
        title: 'Night Covenant',
        author: 'B. Writer',
        kind: RecommendationContentKind.ebook,
        genres: ['Dark Fantasy', 'Supernatural', 'Horror'],
        progress: 0.2,
      ),
      const CatalogItem(
        id: 'ext:src1:shadow-blade',
        title: 'Shadow Blade Online',
        author: 'M. Artist',
        kind: RecommendationContentKind.manga,
        genres: ['dark fantasy', 'action'],
        inLibrary: false,
        sourceLabel: 'ExtSource',
        sourceId: 'src1',
        sourceUrl: 'https://example.com/shadow-blade',
      ),
      const CatalogItem(
        id: 'manga:1',
        title: 'Shadow Blade',
        author: 'M. Artist',
        kind: RecommendationContentKind.manga,
        genres: ['dark fantasy', 'action'],
        readingStatus: 2,
        finished: true,
      ),
      const CatalogItem(
        id: 'manga:2',
        title: 'Cafe Days',
        kind: RecommendationContentKind.manga,
        genres: ['slice of life'],
        readingStatus: 1,
      ),
    ]);
    service = RecommendationService(catalog);
  });

  test('libraryOnly ignores extension hits', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        scope: RecommendationCandidateScope.libraryOnly,
        limit: 10,
      ),
    );
    expect(
      result.items.any((i) => i.id?.startsWith('ext:') == true),
      isFalse,
    );
    expect(result.diagnostics, contains('scope:library'));
  });

  test('libraryAndDiscover ranks extension hits with genre overlap', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        scope: RecommendationCandidateScope.libraryAndDiscover,
        limit: 10,
      ),
    );
    expect(result.diagnostics, contains('scope:discover'));
    expect(result.diagnostics.any((d) => d.startsWith('external:')), isTrue);
    expect(
      result.items.map((i) => i.title),
      contains('Shadow Blade Online'),
    );
    final ext = result.items.firstWhere((i) => i.title == 'Shadow Blade Online');
    expect(ext.inLibrary, isFalse);
    expect(ext.sourceId, 'src1');
    expect(ext.reason, startsWith('Discover'));
  });

  test('libraryAndMetadata alias behaves like discover scope', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        scope: RecommendationCandidateScope.libraryAndMetadata,
        limit: 5,
      ),
    );
    expect(result.diagnostics, contains('scope:discover'));
  });

  test('collapse prefers higher score across library vs ext same title', () {
    final collapsed = collapseDuplicateTitles([
      const ScoredCandidate(
        title: 'Shadow Blade',
        kind: RecommendationContentKind.manga,
        genres: ['dark fantasy'],
        inLibrary: true,
        score: 1.0,
        matchedGenres: ['dark fantasy'],
      ),
      const ScoredCandidate(
        title: 'Shadow Blade',
        kind: RecommendationContentKind.manga,
        genres: ['dark fantasy', 'action'],
        inLibrary: false,
        score: 2.5,
        matchedGenres: ['dark fantasy', 'action'],
        sourceId: 'src1',
      ),
    ]);
    expect(collapsed, hasLength(1));
    expect(collapsed.single.inLibrary, isFalse);
    expect(collapsed.single.score, 2.5);
  });
}
