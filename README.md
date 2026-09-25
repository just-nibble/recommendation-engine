# Recommendation Engine

Standalone Dart package that ranks related ebooks / manga from a host app's
catalog. **No Flutter, Isar, or Koma dependency** — the host implements
[CatalogSource] and calls [RecommendationService].

## Install (path dependency)

In the host `pubspec.yaml`:

```yaml
dependencies:
  recommendation_engine:
    path: ../Recommendation Engine
```

## Quick start

```dart
import 'package:recommendation_engine/recommendation_engine.dart';

final engine = RecommendationService(
  myCatalogSource,
  enricher: myMetadataEnricher, // optional — title → genres/author
);

final result = await engine.recommend(
  RecommendationRequest(
    seeds: [
      RecommendationSeed(title: 'The Name of the Wind'),
    ],
    limit: 5,
  ),
);

for (final item in result.items) {
  print('${item.title} (${item.score}) — ${item.reason}');
}
```

## Host responsibilities

Implement [CatalogSource] to map your library into [CatalogItem]s:

| Method | Purpose |
|--------|---------|
| `findById` | Resolve a seed that already has your opaque id |
| `findByTitle` | Resolve title (+ optional author / kind hint) |
| `listCandidates` | Library (or discover) pool to rank against |

Optionally implement [MetadataEnricher] so title-only seeds (or catalog rows with empty genres) can be filled from Open Library / Google Books / etc. The package never opens network sockets itself.

Opaque ids are host-defined strings (e.g. `book:42`, `manga:7`).

## Docs

- [Product requirements](docs/recommendation-engine-requirements.md)
- [Technical requirements](docs/recommendation-engine-technical-requirements.md)
- [Discover / extension candidates](docs/discover-extension-candidates.md)

## License

Same terms as agreed with the host project; this package is developed separately
from Koma application code.


#### FOR COMMIT LATER
Done. The private engine is at **0.3.0** with Discover/extension support, and Koma is wired to use it.

### Engine (`packages/recommendation_engine_private`)
- Scope: `libraryAndDiscover` (plus legacy `libraryAndMetadata`)
- `listCandidates` gets `genreHints` + `softLimit`
- `CatalogItem`: `inLibrary`, `sourceId`, `sourceUrl`
- Scoring: library penalty + external bonus; duplicate titles collapsed
- Docs: `docs/discover-extension-candidates.md`
- Tests: **19/19** passing (including Discover cases)

### Koma host
- Searches up to **4 pinned/active manga sources** with top genre hints as the query
- Skips titles already in the library
- Soft-fails per source (8s timeout)
- Rails use `libraryAndDiscover`; Discover hits open manga detail and show the source name as badge

### How you’ll see it
Same UI rails as before, but picks can now be **extension catalogue titles** (“Discover · shared genres”), not only library shelves — as long as seeds have genres and sources return hits for those genre queries.

**Note:** Library home may take longer on first load while sources are queried. If that’s too slow we can cache or show library-only first, then fill Discover.