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

final engine = RecommendationService(myCatalogSource);

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

Opaque ids are host-defined strings (e.g. `book:42`, `manga:7`).

## Docs

- [Product requirements](docs/recommendation-engine-requirements.md)
- [Technical requirements](docs/recommendation-engine-technical-requirements.md)

## License

Same terms as agreed with the host project; this package is developed separately
from Koma application code.
