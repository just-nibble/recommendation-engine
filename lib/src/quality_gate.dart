import 'models.dart';

/// Tunable thresholds for the v1 progress-based quality gate.
class RecommendationGateConfig {
  final double minEbookProgress;
  final double finishedEbookProgress;

  const RecommendationGateConfig({
    this.minEbookProgress = 0.05,
    this.finishedEbookProgress = 0.98,
  });

  static const defaults = RecommendationGateConfig();
}

enum SeedGateDecision {
  exclude,
  weak,
  medium,
  strong,
}

extension SeedGateDecisionWeight on SeedGateDecision {
  double get weight {
    switch (this) {
      case SeedGateDecision.exclude:
        return 0;
      case SeedGateDecision.weak:
        return 0.35;
      case SeedGateDecision.medium:
        return 1.0;
      case SeedGateDecision.strong:
        return 1.75;
    }
  }
}

/// v1 gate from progress / status fields (+ optional [ReadingSignals]).
SeedGateDecision evaluateSeedGate({
  required RecommendationContentKind kind,
  double? progress,
  bool? finished,
  int? mangaReadingStatus,
  ReadingSignals? signals,
  RecommendationGateConfig config = RecommendationGateConfig.defaults,
}) {
  final prog = signals?.progress ?? progress;
  final done = signals?.finished ?? finished;

  final totalSeconds = signals?.totalReadingSeconds;
  final avgPerPage = signals?.avgSecondsPerPage;
  if (totalSeconds != null &&
      totalSeconds >= 3600 &&
      (prog == null || prog < 0.05)) {
    return SeedGateDecision.exclude;
  }
  if (avgPerPage != null && avgPerPage >= 1800 && (prog == null || prog < 0.1)) {
    return SeedGateDecision.exclude;
  }

  if (kind == RecommendationContentKind.ebook) {
    if (done == true ||
        (prog != null && prog >= config.finishedEbookProgress)) {
      return SeedGateDecision.strong;
    }
    if (prog == null) {
      return SeedGateDecision.medium;
    }
    if (prog < config.minEbookProgress) {
      return SeedGateDecision.exclude;
    }
    if (prog >= 0.5) return SeedGateDecision.medium;
    return SeedGateDecision.weak;
  }

  // Manga-style: readingStatus 0 unread / 1 reading / 2 read
  final status = mangaReadingStatus;
  if (done == true || status == 2) {
    return SeedGateDecision.strong;
  }
  if (status == 1 || (prog != null && prog >= config.minEbookProgress)) {
    return prog != null && prog >= 0.5
        ? SeedGateDecision.medium
        : SeedGateDecision.weak;
  }
  if (status == 0 && (prog == null || prog < config.minEbookProgress)) {
    if (signals == null && progress == null && finished == null) {
      return SeedGateDecision.medium;
    }
    return SeedGateDecision.exclude;
  }
  return SeedGateDecision.medium;
}
