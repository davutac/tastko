#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCHMARK_DIR="$ROOT_DIR/.build/SentenceBenchmark"
mkdir -p "$BENCHMARK_DIR"

source "$ROOT_DIR/script/swift_flags.sh"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos27.0" "${TASTKO_SWIFT_FLAGS[@]}" \
    "$ROOT_DIR/Tastko/Models/AccessibilityTextRange.swift" \
    "$ROOT_DIR/Tastko/Models/PredictionInput.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AIModels.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleCompletionBudget.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleCompletionTokenCache.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleFoundationModelProvider.swift" \
    "$ROOT_DIR/Tastko/Services/SentenceCompletionPrompt.swift" \
    "$ROOT_DIR/script/SentenceBenchmarkSupport.swift" \
    "$ROOT_DIR/script/SentenceBenchmarkSamples.swift" \
    "$ROOT_DIR/script/benchmark_sentence_parallel.swift" \
    "$ROOT_DIR/script/benchmark_sentences.swift" \
    -o "$BENCHMARK_DIR/sentence-benchmark"

if [[ "${1:-}" != --build-only ]]; then
    "$BENCHMARK_DIR/sentence-benchmark" "$@"
fi
