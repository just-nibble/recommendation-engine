# Recommendation Engine — Requirements

Status: draft  
Consumers: host reader apps (e.g. Koma) via Dart package import  
Scope: standalone `recommendation_engine` package (not embedded in the host app, not a remote server)  
Technical requirements: [recommendation-engine-technical-requirements.md](./recommendation-engine-technical-requirements.md)

## 1. Overview

This repository is the **Recommendation Engine** — a Dart package that suggests related reading based on what a user has been reading. Host apps (such as Koma) **import** the package and supply a thin catalog adapter; they do not own the ranking logic.

The engine is **not** a separately deployed HTTP service, and it is **not** copied into the host codebase.

Recommendations cover:

- Ebooks / novels
- Manga
- Manhwa
- Comics (including DC / Marvel–style titles)

## 2. Goals

1. Given minimal input (typically a **title**), return a ranked list of recommended titles.
2. Do the heavy lifting inside the engine: resolve identity, content type, genres/tags, and related titles.
3. Optionally use reading-behavior signals so weak or fake engagement does not drive recommendations.
4. Stay portable across app surfaces (mobile today; web or other clients later) via a shared in-app API — not a separate microservice.
5. Respect Koma’s local-first posture: no accounts, no tracking; prefer local catalog and on-device signals; any external metadata lookup is for enrichment only, not user profiling.

## 3. Non-goals (v1)

- Collaborative filtering (“users like you also read…”) — deferred until multi-user history exists and fits privacy model.
- A standalone recommendation HTTP service or SaaS.
- Scraping or replacing the user’s full library UI; the app asks for N recommendations and renders them.
- Guaranteed availability of every recommended title in the user’s library or a store (unless a later “available only” filter is added).

## 4. Integration model

| Decision | Choice |
|----------|--------|
| Deployment | Standalone Dart package (`recommendation_engine`) |
| Call style | In-process API via `RecommendationService` + host `CatalogSource` |
| Clients | Any Dart/Flutter host (Koma first); web or other shells later |
| Catalog | Host-owned; engine never depends on host DB / models |

### 4.1 Conceptual interface

```text
recommend(request) → RecommendationResult
```

The app supplies what it knows. The engine fills gaps and returns ranked recommendations.

## 5. Inputs

### 5.1 Seed content (required minimum)

| Field | Required | Notes |
|-------|----------|--------|
| `title` | Yes (at least one seed) | Title of the book/manga/comic just completed or currently in focus |
| `author` | No | Use when provided; otherwise resolve if possible |
| `content_type` / tags | No | ebook, manga, manhwa, comic, etc. Engine infers if missing |
| `genres` / thematic tags | No | Engine infers from title/author/catalog when missing |

The app may send a **single** seed or a **list** of seeds (e.g. several recently finished titles). Seeds may mix ebooks and manga-style content.

### 5.2 Request controls

| Field | Required | Default | Notes |
|-------|----------|---------|--------|
| `limit` | No | `5` | Number of recommendations to return |
| `limit_per_content_kind` | No | — | Optional split, e.g. 5 ebook + 5 manga-style |
| `content_kinds` | No | all | Filter result kinds: ebook, manga, manhwa, comic |
| `exclude` | No | — | Titles/IDs already owned, already recommended, or the seed itself |

### 5.3 Reading signals (optional per seed)

Used to decide **whether** a seed should influence recommendations and how strongly — not as a substitute for content similarity.

| Signal | Purpose |
|--------|---------|
| Total time spent on the title | Engagement volume |
| Finished vs not finished | Completion is a strong positive signal |
| Current page / progress | Distinguish deep reading from abandonment |
| Open count | Frequency of return visits |
| Average time per page (or equivalent) | Detect stuck / idle sessions |

**Quality gate (required behavior):** If engagement looks invalid — e.g. many hours on a single page with no meaningful progress — that seed must **not** drive recommendations (or must be heavily down-weighted). The app cannot always detect this alone; the request should carry the raw signals and the engine applies the gate.

## 6. Engine responsibilities

1. **Resolve** the seed title (and author if present) to a canonical identity when possible.
2. **Classify** content type: novel/ebook vs manga vs manhwa vs comic, etc.
3. **Enrich** missing author, genres, and tags from local catalog first; fall back to external metadata lookup when needed.
4. **Match** candidates by shared genres/tags and other content relationships.
5. **Rank** candidates; apply `limit` / per-kind limits; exclude seeds and other exclusions.
6. **Gate** on reading-signal quality before treating a seed as preference evidence.
7. Return results the UI can render (title, author, kind, optional artwork URL / local ref, short reason).

## 7. Matching and ranking rules

### 7.1 Content-based similarity (primary for v1)

- Prefer candidates that share **multiple meaningful** tags/genres with the seed set (e.g. supernatural + dark fantasy).
- If a tag appears on only one or two books in the seed set and is not otherwise strong, **ignore or heavily down-weight** it.
- Generic tags alone (e.g. “fiction”) must not dominate ranking.
- Same author / same series may be used as additional soft signals when available.

### 7.2 Multi-seed consensus

When several seeds are provided:

- Emphasize tags/genres that are **common across** the seeds.
- Do not recommend solely from outlier tags present on a minority of seeds.

### 7.3 Mixed ebook + manga requests

- Accept combined lists (ebook seeds + manga-style seeds).
- Support returning a single mixed list **or** separate lists per content kind when requested (e.g. five ebook recommendations and five manga-style recommendations).

### 7.4 Behavior weighting

| Situation | Effect |
|-----------|--------|
| Finished title | Strong boost for similar titles |
| High progress, healthy time-per-page | Positive weight |
| Opened often but little progress | Low weight |
| Extreme time on one page / idle pattern | Exclude or near-zero weight |

## 8. Outputs

Each recommendation item should include at least:

| Field | Notes |
|-------|--------|
| Title | Required |
| Author | When known |
| Content kind | ebook / manga / manhwa / comic / … |
| Score or rank | Internal; may be omitted from UI |
| Reason (optional) | e.g. shared genres — useful for “Because you like …” |
| Metadata refs | IDs, cover, source — as available in Koma |

Batch result:

- Ordered list of length ≤ `limit`, and/or
- Grouped lists when `limit_per_content_kind` is set.

## 9. Privacy and local-first constraints

Aligned with Koma (no accounts, no tracking):

- Reading signals stay on-device / in the local app data plane unless the user explicitly enables a feature that requires otherwise.
- External lookups, if used, should request **title/author metadata only**, not a user identity or full reading history upload.
- No building of cross-user profiles in v1.

## 10. Acceptance criteria (v1)

1. Calling the module with only a **title** returns up to N recommendations without requiring the caller to supply genres.
2. Providing **author** improves resolution accuracy when the title is ambiguous.
3. Caller can set **N** (default 5).
4. Caller can request recommendations for **ebook** and **manga-style** content separately or together.
5. Shared multi-tag overlap ranks above weak single-tag overlap; weak/rare tags are ignored per §7.
6. Seeds that fail the reading-quality gate do not produce recommendations based on that seed alone.
7. Module lives in the Koma codebase and is invoked in-process (or via existing Flutter↔Rust bridge), not as an independent remote product.

## 11. Open decisions

- Exact external metadata sources (and offline behavior when network is unavailable).
- Whether recommendations must be restricted to titles already in the user’s library, discoverable extensions, or open web/catalog results.
- Persistence of “already shown” recommendations and dismissal history.
- Implementation home: Dart-only vs Rust (via flutter_rust_bridge) for matching/enrichment.
- Thresholds for the reading-quality gate (time-per-page, minimum progress, etc.) — to be tuned with real usage.

## 12. Suggested v1 delivery order

1. Title/author resolve → content kind + tags (local catalog, then optional enrichment).
2. Tag-overlap ranking with strong-shared-tag rule.
3. `limit` and optional ebook / manga-style split.
4. Reading-signal quality gate and weighting.
5. UI surfacing (“Recommended for you” / after finish) using the module API.
