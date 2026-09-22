# Recommendation Engine — Technical Requirements

Status: draft  
Product requirements: [recommendation-engine-requirements.md](./recommendation-engine-requirements.md)  
Package: `recommendation_engine` (pure Dart; no Flutter / Isar / Koma dependency)  
Host integration: [host-integration.md](./host-integration.md)

## 1. Purpose

Define the technical contract for a **standalone** recommendation package that host apps import. The package owns ranking; the host owns persistence and UI. This document implements the product requirements; it does not redefine product goals.

## 2. System context

```text
┌─────────────────────────────────────────────────────────────┐
│ Host app (e.g. Koma) — UI, Isar, Riverpod                   │
│   CatalogSource adapter (thin)                              │
└───────────────────────────┬─────────────────────────────────┘
                            │ package import
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ recommendation_engine                                       │
│   RecommendationService                                     │
│   genre profile / quality gate / scoring                    │
└─────────────────────────────────────────────────────────────┘
```

**Hard constraints:**
- No standalone recommendation server.
- No dependency on Koma (or any host) source trees.
- Host implements `CatalogSource` and maps opaque string ids (e.g. `book:12`).

## 3. Placement in the codebase

| Concern | Location (proposed) |
|---------|---------------------|
| Public Dart API / DTOs | `lib/core/models/recommendation.dart` (or `lib/core/recommendations/`) |
| Orchestration | `lib/core/services/recommendation_service.dart` |
| Persistence access | `lib/core/repositories/recommendation_repository.dart` (if caching/history needed) |
| Riverpod | `lib/features/recommendations/` and/or providers in `lib/core/providers.dart` |
| Isar schema additions | `lib/core/isar/collections/` + register in `lib/core/isar/isar.dart` |
| Heavy / shared enrichment (optional) | extend `rust/src/api/metadata.rs` + FRB regen into `lib/src/rust/` |

Follow existing patterns: domain models → Isar collections → repositories → services → feature Riverpod → UI.

## 4. Content-kind model

Koma today has **two parallel libraries**, not a unified content enum:

- Ebooks: `Book` + optional `BookMetadata` (`lib/core/models/book.dart`, `book_metadata.dart`)
- Manga-style: `Manga` + chapters (`lib/core/models/manga.dart`) — used for manga / manhwa / comics from extensions

### 4.1 Technical `RecommendationContentKind`

Introduce an explicit enum for the recommendation API (does not replace Isar schemas):

```dart
enum RecommendationContentKind {
  ebook,
  manga,   // includes manhwa / comics unless later subdivided
}
```

**v1 mapping rules:**

| Source | Kind |
|--------|------|
| `Book` / ebook metadata hit | `ebook` |
| `Manga` / extension detail | `manga` |

Subdivision (manhwa vs comic vs DC/Marvel) is **out of band for v1 ranking keys**; optional heuristic tags may be attached as string labels later. Do not invent a third Isar collection for v1.

## 5. Public API contract

### 5.1 Entry point

```dart
abstract class RecommendationService {
  Future<RecommendationResult> recommend(RecommendationRequest request);
}
```

- Must be safe to call from Riverpod (`async`); no UI imports.
- Must not throw for “no matches”; return empty lists with optional diagnostics.
- Must be cancellable where practical (`CancelToken` / ignore late results) when used from UI.

### 5.2 Request

```dart
class RecommendationRequest {
  final List<RecommendationSeed> seeds; // >= 1
  final int limit;                      // default 5, min 1, max 50
  final int? limitEbook;                // optional per-kind caps
  final int? limitManga;
  final Set<RecommendationContentKind>? contentKinds; // null = all
  final List<RecommendationExclusion> exclude;
  final RecommendationCandidateScope scope;
}

enum RecommendationCandidateScope {
  libraryOnly,   // only local Book / Manga in library
  libraryAndMetadata, // library + enrichment/discover hits (default proposal)
}
```

### 5.3 Seed

```dart
class RecommendationSeed {
  final String title;                   // required
  final String? author;
  final RecommendationContentKind? kind; // hint; engine may override after resolve
  final List<String> genres;            // optional caller-supplied
  final String? localBookId;            // Isar Book id if known
  final String? localMangaId;           // Isar Manga id if known
  final ReadingSignals? signals;
}
```

### 5.4 Reading signals

```dart
class ReadingSignals {
  final double? progress;           // 0.0–1.0
  final bool? finished;
  final int? openCount;
  final int? totalReadingSeconds;
  final double? avgSecondsPerPage;  // or per-progress-unit
  final int? currentPage;
  final int? totalPages;
}
```

**Today’s gap:** Isar stores book `progress` / manga `readingStatus` and chapter page flags, but **not** per-title `openCount`, `totalReadingSeconds`, or `avgSecondsPerPage` (`StatsService.trackReading` aggregates daily only). Technical requirement:

1. **v1 gate (ship without new telemetry):** derive from existing fields only — `Book.progress`, completion via reader completion path, `Manga.readingStatus`, chapter `isRead` / `lastPageRead`.
2. **v1.1 schema (required to fully meet product §5.3):** add per-title engagement collection (see §7).

### 5.5 Result

```dart
class RecommendationResult {
  final List<RecommendationItem> items;       // when mixed / single list
  final List<RecommendationItem> ebooks;      // populated when per-kind split requested
  final List<RecommendationItem> manga;
  final List<String> appliedGenreKeys;        // consensus tags used
  final List<String> diagnostics;             // debug / logging; not shown by default
}

class RecommendationItem {
  final String title;
  final String? author;
  final RecommendationContentKind kind;
  final double score;
  final List<String> matchedGenres;
  final String? reason;              // short, UI-safe
  final String? localBookId;
  final String? localMangaId;
  final String? coverPathOrUrl;
  final String? sourceLabel;         // e.g. library | open_library | extension
}
```

## 6. Pipeline (normative)

Every `recommend()` call SHALL execute these stages in order:

1. **Validate** — non-empty seeds; clamp limits; normalize titles (trim, collapse whitespace, casefold for matching).
2. **Resolve seeds** — map each seed to a `ResolvedSeed` (kind, author, genres, local ids).
3. **Quality gate** — drop or down-weight seeds that fail engagement rules (§8).
4. **Build preference profile** — consensus genres/tags across gated seeds (§9).
5. **Gather candidates** — from scope (§10); exclude seeds and `exclude` list.
6. **Score & rank** — §11.
7. **Truncate** — apply `limit` / per-kind caps.
8. **Map** — `RecommendationItem` for UI.

Stages 2–5 may use local DB without network. Network enrichment is allowed only when local genres/identity are insufficient **and** connectivity is available **and** scope permits.

## 7. Persistence

### 7.1 Existing stores (read)

| Entity | Use |
|--------|-----|
| `Book` | Seed resolve, library candidates, `title` / `author` / `genre` / `progress` |
| `BookMetadata` | Prefer `genres: List<String>` over `Book.genre` when present |
| `Manga` | Seed resolve, library candidates, `genres`, `readingStatus`, `inLibrary` |
| `MangaChapter` | Progress / finished heuristics (`isRead`, `lastPageRead`) |
| `ReadingStat` | Not sufficient for per-title gating (daily aggregates only) |

### 7.2 New collection: `TitleEngagement` (v1.1)

Required to implement full product reading-quality gate.

| Field | Type | Notes |
|-------|------|--------|
| `id` | Id | |
| `contentKind` | byte / enum | ebook vs manga |
| `bookId` / `mangaId` | long? | Exactly one set |
| `openCount` | int | Increment on reader open |
| `totalReadingSeconds` | int | From reader timers |
| `progressSnapshot` | double | Last known progress |
| `finished` | bool | |
| `lastPageOrChapter` | int | For idle detection |
| `secondsOnLastUnit` | int | Time on current page/chapter without progress |
| `updatedAt` | DateTime | |

**Writers:** ebook `reader_provider` and manga reader screen timers (existing 30s ticks) MUST update this collection when v1.1 ships.

**Migration:** additive Isar schema only; default zeros for existing titles.

### 7.3 Optional: recommendation cache / dismissals

If UI needs “don’t show again”:

| Field | Notes |
|-------|--------|
| fingerprint | hash(title|author|kind) or local id |
| dismissedAt / shownAt | |

Not required for ranking correctness in v1.

## 8. Quality gate (technical)

### 8.1 v1 (existing fields only)

| Condition | Action |
|-----------|--------|
| Ebook `progress < 0.05` and not finished | Exclude seed (or weight ≈ 0) |
| Manga `readingStatus == 0` (unread) and no chapter `isOpened`/`lastPageRead > 0` | Exclude |
| Ebook finished / `progress >= 0.98` OR manga `readingStatus == 2` | Strong weight |
| Mid progress with recent chapter activity | Medium weight |

### 8.2 v1.1 (with `TitleEngagement`)

| Condition | Action |
|-----------|--------|
| `secondsOnLastUnit` high AND progress delta ≈ 0 over session | Exclude (idle / stuck page) |
| `totalReadingSeconds` high AND `progress` very low | Exclude or near-zero |
| `openCount` high AND `progress` very low | Low weight |
| Finished + healthy seconds/progress ratio | Strong weight |

Exact numeric thresholds MUST be named constants in code (e.g. `RecommendationGateConfig`) and tunable without schema migration.

## 9. Genre profile

1. Collect genres from each gated `ResolvedSeed`.
2. Normalize: trim, casefold, dedupe; optional synonym map (e.g. `sci-fi` → `science fiction`) — start minimal.
3. **Consensus filter:** keep genres that appear in at least `ceil(n/2)` seeds when `n >= 2`, OR appear at least twice; always keep genres from a single strong seed when `n == 1`.
4. Drop ultra-generic tokens from a deny-list (`fiction`, `book`, `manga`, `comic` as sole signal).
5. Profile = weighted multiset of remaining genres (finish boost applies as seed weight).

If profile is empty after enrichment attempts → return empty result (or optional popular-in-library fallback — **default off** for v1).

## 10. Candidate sources

### 10.1 Library

- All `Book` rows (ebook path).
- All `Manga` with `inLibrary == true` (manga path), unless product later includes non-library browse results.

### 10.2 Metadata enrichment (ebooks)

Reuse:

- Dart: `MetadataEnrichmentService` / discover metadata cache patterns
- Rust: `lookup_books` → Open Library, Google Books fallback (`rust/src/api/metadata.rs`)

Use to fill missing seed genres/author and, when `scope == libraryAndMetadata`, to propose related titles **only if** a concrete related-title API exists or search-by-subject is added. **v1 minimum:** enrichment for seed genres; candidates primarily from **local library** overlap.

### 10.3 Manga enrichment

Use extension `getDetail` / existing genres on `Manga` when seed is library manga. Do not call Open Library for manga in v1.

### 10.4 Offline

If network unavailable:

- Skip remote enrichment.
- Rank using local `Book.genre` / `BookMetadata.genres` / `Manga.genres` only.
- Still return library matches when possible.

## 11. Scoring

For each candidate not excluded:

```text
score =
  Σ (seedWeight_i * genreOverlap(profile, candidateGenres))
  + authorBonus          // same author as any gated seed
  + kindMatchBonus       // preferred when contentKinds filtered
  − alreadyOwnedPenalty  // optional, if recommending discover hits later
```

**genreOverlap:**

- Count intersection of meaningful genres.
- Require **≥ 2** matched non-generic genres for a “strong” recommendation; allow 1 only if that genre is rare/specific (not on deny-list) and no stronger candidates fill `limit`.
- Prefer higher intersection size, then higher seed weights, then recency of seed activity if available.

Sort descending by `score`; stable tie-break by title.

## 12. Dart ↔ Rust boundary

| Work | Owner |
|------|--------|
| Request validation, gate, profile, library candidate scan, ranking, Riverpod | **Dart** |
| Title/author → remote metadata (existing) | **Rust** `lookup_books` (unchanged or thin extension) |
| Optional later: subject/related search | Rust metadata API **only if** OL/GB endpoints are added cleanly |

Do not move ranking into Rust for v1 unless profiling proves Dart is too slow on large libraries (unlikely at typical personal-library sizes).

## 13. Concurrency, performance, UX

| Requirement | Detail |
|-------------|--------|
| Main isolate | Ranking over library MUST NOT block UI frame budget; use `compute` / background isolate if library scan + scoring exceeds ~16ms on mid devices, or chunk work |
| Time budget | Soft target: p95 `< 300ms` for library-only; enrichment may take longer — UI shows cached/local first when possible |
| Deduping | Concurrent identical requests should share in-flight `Future` |
| Idempotency | Same request → same ordering given same DB snapshot |

## 14. Privacy & networking

1. No analytics user id; no upload of full reading history.
2. Remote calls send **title/author (and API keys already used for Google Books)** only, matching current enrichment.
3. Honor existing user settings for network/metadata if present; do not add silent background scrapers.
4. Log diagnostics locally; do not include chapter text payloads in recommendation requests.

## 15. UI integration points (non-visual contract)

Call sites (implementation may phase):

| Trigger | Seed source |
|---------|-------------|
| After ebook completion | Completed `Book` + signals |
| After manga marked read | `Manga` + signals |
| Library / home “Recommended” | Recent gated seeds from history |
| Book/manga detail | Current title as single seed |

UI consumes `RecommendationResult` only; it must not reimplement ranking.

## 16. Testing requirements

| Layer | Cases |
|-------|--------|
| Unit | Genre normalization; consensus filter; deny-list; scoring order; limit / per-kind split; exclusion |
| Unit | Quality gate v1 heuristics; v1.1 idle/stuck cases |
| Unit | Title normalize + duplicate candidate collapse |
| Widget/notifier (light) | Provider returns items / empty / error-as-empty |
| Integration | Seed with only title → enrich genres (mocked HTTP/Rust) → library overlap ranks correctly |
| Regression | Offline path returns library matches without calling network |

Fixtures: small in-memory lists of `Book`/`Manga`-like DTOs; do not require full Isar for pure ranking tests.

## 17. Observability

- Debug-only `diagnostics` on `RecommendationResult` (gated seeds, applied genres, candidate counts, enrich used yes/no).
- Optional `debugPrint` / app logger behind a flag; no PII beyond titles already on device.

## 18. Acceptance criteria (technical)

1. `RecommendationService.recommend` exists in-process and is callable from a Riverpod provider without a network dependency for library-only scope.
2. Dual catalog supported: ebook seeds resolve via `Book`/`BookMetadata`; manga seeds via `Manga`.
3. Default `limit == 5`; per-kind limits populate `ebooks` / `manga` lists as specified.
4. Consensus genre filter and generic deny-list are covered by unit tests.
5. v1 quality gate uses existing progress/status fields; `TitleEngagement` schema + writers are specified for v1.1 and tracked as follow-up work.
6. Offline mode never fails the call solely due to lack of network.
7. Reuses existing Rust `lookup_books` for ebook enrichment rather than a new remote stack.
8. No new standalone service process, port, or public HTTP recommendation API.

## 19. Implementation phases

| Phase | Deliverable |
|-------|-------------|
| **P0** | DTOs + `RecommendationService`; library-only genre overlap; limits; exclusions |
| **P1** | Optional `MetadataEnricher` for seed genre/author fill; diagnostics (`enrichment:on`, `enriched:…`) |
| **P2** | v1 quality gate from progress/status; diagnostics polish |
| **P3** | Host `TitleEngagement` schema + reader instrumentation; full product gate |
| **P4** | Optional discover/metadata candidates beyond library; dismissals cache |

## 20. Open technical decisions

1. Default `RecommendationCandidateScope`: confirm `libraryOnly` vs `libraryAndMetadata` for first UI ship.
2. Whether manga recommendations may include non-`inLibrary` extension search hits in v1.
3. Isolate strategy threshold (library size) for background scoring.
4. Synonym / localization handling for genres across extension languages.
5. Whether to extend Rust metadata with subject-based related books or keep Dart-only library overlap for v1.
