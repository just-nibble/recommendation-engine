# Example: wiring Discover / extension candidates (Koma)

When [RecommendationRequest.scope] is `libraryAndDiscover`, the engine calls:

```dart
catalog.listCandidates(
  scope: RecommendationCandidateScope.libraryAndDiscover,
  genreHints: profile.keys, // consensus genres from gated seeds
  softLimit: 120,
);
```

Host responsibilities:

1. Return library rows as before (`inLibrary: true`).
2. Search installed manga sources with the top genre hint(s) as the query.
3. Map hits to [CatalogItem] with:
   - `inLibrary: false`
   - `sourceId` / `sourceUrl` for navigation
   - `id`: `ext:{urlEncodedSourceId}:{urlEncodedUrl}`
   - `genres`: hit genres **plus** the genre hints used for the query
4. Skip titles already in the library.
5. Fail soft — one source error must not fail `recommend()`.

The engine never opens sockets. Ranking applies an `alreadyOwnedPenalty` to
library rows and an `externalBonus` to Discover rows, then collapses duplicate
titles.
