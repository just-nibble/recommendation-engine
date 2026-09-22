# Example: wiring this package into a host reader (e.g. Koma)

The host owns persistence (Isar, SQLite, …). This package only needs a
`CatalogSource` adapter.

```dart
import 'package:recommendation_engine/recommendation_engine.dart';

class KomaCatalogSource implements CatalogSource {
  // Inject your repositories / DB here.

  @override
  Future<CatalogItem?> findById(String id) async {
    if (id.startsWith('book:')) {
      final book = await books.getBook(int.parse(id.substring(5)));
      return book == null ? null : _fromBook(book);
    }
    if (id.startsWith('manga:')) {
      final manga = await mangas.getMangaById(int.parse(id.substring(6)));
      return manga == null ? null : _fromManga(manga);
    }
    return null;
  }

  @override
  Future<CatalogItem?> findByTitle({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  }) async {
    // Map title/author lookup onto your library APIs.
    throw UnimplementedError();
  }

  @override
  Future<List<CatalogItem>> listCandidates({
    Set<RecommendationContentKind>? kinds,
    RecommendationCandidateScope scope =
        RecommendationCandidateScope.libraryOnly,
  }) async {
    final out = <CatalogItem>[];
    if (kinds == null || kinds.contains(RecommendationContentKind.ebook)) {
      for (final b in await books.getBooks()) {
        out.add(_fromBook(b));
      }
    }
    if (kinds == null || kinds.contains(RecommendationContentKind.manga)) {
      for (final m in await mangas.getMangasInLibrary()) {
        out.add(_fromManga(m));
      }
    }
    return out;
  }

  CatalogItem _fromBook(dynamic book) => CatalogItem(
        id: 'book:${book.id}',
        title: book.title,
        author: book.author,
        kind: RecommendationContentKind.ebook,
        genres: /* parse book.genre / metadata */ const [],
        progress: book.progress,
        coverPathOrUrl: book.coverPath,
      );

  CatalogItem _fromManga(dynamic manga) => CatalogItem(
        id: 'manga:${manga.id}',
        title: manga.name,
        author: manga.author,
        kind: RecommendationContentKind.manga,
        genres: List<String>.from(manga.genres),
        readingStatus: manga.readingStatus,
        coverPathOrUrl: manga.imageUrl,
      );
}

/// Optional: wrap your existing Open Library / Google Books lookup.
class KomaMetadataEnricher implements MetadataEnricher {
  @override
  Future<MetadataEnrichment?> enrich({
    required String title,
    String? author,
    RecommendationContentKind? kindHint,
  }) async {
    // e.g. final hits = await lookupBooks(title: title, author: author);
    // map first hit → MetadataEnrichment(genres: ..., author: ..., ...)
    return null;
  }
}

// Usage in the host:
// final engine = RecommendationService(
//   KomaCatalogSource(...),
//   enricher: KomaMetadataEnricher(...),
// );
```

Do **not** copy recommendation ranking logic into the host. Keep adapters thin.

Riverpod / UI wiring stays in the host app (not this package).
