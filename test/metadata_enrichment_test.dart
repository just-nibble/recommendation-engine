import 'package:recommendation_engine/recommendation_engine.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryCatalogSource catalog;

  setUp(() {
    catalog = InMemoryCatalogSource([
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
        kind: RecommendationContentKind.ebook,
        genres: ['Romance'],
        progress: 0.5,
      ),
      // In library but missing genres — seed will be enriched instead.
      const CatalogItem(
        id: 'book:1',
        title: 'Seed of Shadows',
        author: 'A. Author',
        kind: RecommendationContentKind.ebook,
        genres: [],
        progress: 1.0,
        finished: true,
      ),
    ]);
  });

  test('enriches seed with empty genres then ranks library overlap', () async {
    final enricher = InMemoryMetadataEnricher({
      InMemoryMetadataEnricher.keyFor('Seed of Shadows'):
          const MetadataEnrichment(
        author: 'A. Author',
        kind: RecommendationContentKind.ebook,
        genres: ['Dark Fantasy', 'Supernatural'],
        sourceLabel: 'open_library',
      ),
    });

    final service = RecommendationService(catalog, enricher: enricher);
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
        limit: 5,
      ),
    );

    expect(result.diagnostics, contains('enrichment:on'));
    expect(result.diagnostics.any((d) => d.startsWith('enriched:')), isTrue);
    expect(result.appliedGenreKeys, containsAll(['dark fantasy', 'supernatural']));
    expect(result.items.map((i) => i.title), contains('Night Covenant'));
    expect(result.items.map((i) => i.title), isNot(contains('Office Romance')));
  });

  test('title-only unknown seed works via enricher alone', () async {
    final enricher = InMemoryMetadataEnricher({
      InMemoryMetadataEnricher.keyFor('External Epic'):
          const MetadataEnrichment(
        genres: ['Dark Fantasy', 'Supernatural'],
      ),
    });

    final service = RecommendationService(catalog, enricher: enricher);
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'External Epic')],
      ),
    );

    expect(result.items, isNotEmpty);
    expect(result.diagnostics, contains('enriched:External Epic'));
  });

  test('skips enrichment when enableEnrichment is false', () async {
    final enricher = InMemoryMetadataEnricher({
      InMemoryMetadataEnricher.keyFor('Seed of Shadows'):
          const MetadataEnrichment(
        genres: ['Dark Fantasy', 'Supernatural'],
      ),
    });

    final service = RecommendationService(
      catalog,
      enricher: enricher,
      enableEnrichment: false,
    );
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [RecommendationSeed(title: 'Seed of Shadows')],
      ),
    );

    expect(result.diagnostics, contains('enrichment:off'));
    expect(result.items, isEmpty);
    expect(result.diagnostics, contains('no_genres:Seed of Shadows'));
  });

  test('does not call enricher when seed already has genres and author', () async {
    var calls = 0;
    final enricher = _CountingEnricher(() => calls++);

    final service = RecommendationService(catalog, enricher: enricher);
    final result = await service.recommend(
      const RecommendationRequest(
        seeds: [
          RecommendationSeed(
            title: 'Unknown Book',
            author: 'Someone',
            genres: ['dark fantasy', 'supernatural'],
          ),
        ],
      ),
    );

    expect(calls, 0);
    expect(result.items, isNotEmpty);
  });
}

class _CountingEnricher implements MetadataEnricher {
  final void Function() onCall;
  _CountingEnricher(this.onCall);

  @override
  Future<MetadataEnrichment?> enrich({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  }) async {
    onCall();
    return null;
  }
}
