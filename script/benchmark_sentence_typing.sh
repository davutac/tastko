#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCHMARK_DIR="$ROOT_DIR/.build/SentenceTypingBenchmark"
mkdir -p "$BENCHMARK_DIR"
# Compile the real service and focus-value declarations without the live AX service.
python3 - "$ROOT_DIR" "$BENCHMARK_DIR" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'Tastko/Services/AccessibilityService.swift').read_text()
parts = [('AccessibilityFocusRoute', 'KeyboardTargetDebugSnapshot'),
         ('FocusedTextValue', 'FocusedKeyboardContext')]
values = 'import AppKit\nimport ApplicationServices\n'
for start, end in parts:
    values += source.split('// MARK: - ' + start, 1)[1].split('// MARK: - ' + end, 1)[0]
(output / 'FocusTypes.swift').write_text(values)
PY
source "$ROOT_DIR/script/swift_flags.sh"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos27.0" "${TASTKO_SWIFT_FLAGS[@]}" \
    "$ROOT_DIR/Tastko/Models/AccessibilityTextRange.swift" \
    "$ROOT_DIR/Tastko/Models/PredictionInput.swift" \
    "$ROOT_DIR/Tastko/Models/PredictionContext.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AIModels.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleCompletionBudget.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleCompletionTokenCache.swift" \
    "$ROOT_DIR/Tastko/Features/AI/AppleFoundationModelProvider.swift" \
    "$ROOT_DIR/Tastko/Services/SentenceCompletionPrompt.swift" \
    "$ROOT_DIR/Tastko/Services/SentenceCompletionService.swift" \
    "$BENCHMARK_DIR/FocusTypes.swift" \
    "$ROOT_DIR/script/SentenceBenchmarkSupport.swift" \
    "$ROOT_DIR/script/benchmark_sentence_typing.swift" \
    -o "$BENCHMARK_DIR/sentence-typing-benchmark"
if [[ "${1:-}" != --build-only ]]; then
    "$BENCHMARK_DIR/sentence-typing-benchmark" "$@"
fi
