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
        id: 'book:3',
        title: 'Office Romance',
        author: 'C. Soft',
        kind: RecommendationContentKind.ebook,
        genres: ['Romance', 'Fiction'],
        progress: 0.5,
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

  test('recommends catalog titles sharing seed genres', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [
          RecommendationSeed(
            title: 'Seed of Shadows',
            author: 'A. Author',
          ),
        ],
        limit: 5,
      ),
    );

    expect(
      result.appliedGenreKeys,
      containsAll(['dark fantasy', 'supernatural']),
    );
    expect(result.items.map((i) => i.title), contains('Night Covenant'));
    expect(result.items.map((i) => i.title), isNot(contains('Seed of Shadows')));
    expect(result.items.map((i) => i.title), isNot(contains('Office Romance')));
  });

  test('respects limit', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        limit: 1,
      ),
    );
    expect(result.items.length, 1);
  });

  test('supports per-kind limits', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        limitEbook: 1,
        limitManga: 1,
      ),
    );
    expect(result.ebooks.length, lessThanOrEqualTo(1));
    expect(result.manga.length, lessThanOrEqualTo(1));
    expect(result.manga.map((i) => i.title), contains('Shadow Blade'));
  });

  test('title-only seed with caller genres works without catalog match', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [
          RecommendationSeed(
            title: 'Unknown External Title',
            genres: ['dark fantasy', 'supernatural'],
          ),
        ],
        limit: 3,
      ),
    );
    expect(result.items, isNotEmpty);
  });

  test('honors exclusions by id', () async {
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        exclude: [RecommendationExclusion(id: 'book:2')],
      ),
    );
    expect(result.items.map((i) => i.title), isNot(contains('Night Covenant')));
  });
}
