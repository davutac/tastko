# Text prediction performance

Run the optimized provider benchmark with fixed English and German examples:

```sh
bash script/benchmark_predictions.sh
```

Use `bash script/benchmark_predictions.sh --native-only` to measure the native service without invoking Foundation Models.

It reports native partial-word and next-word, first valid AI suggestion, and full model response median/p95 latency separately, prints the fixed sample outputs for quality inspection, and reports model unavailability instead of fabricating timings. Model measurements exclude the 150 ms debounce and the one-second prewarming allowance. They do not measure Accessibility capture or guarantee production end-to-end latency.

For actual field-capture timings, launch a Release build and inspect the `PredictionTiming` log category while typing in a disposable document:

```sh
TASTKO_BUILD_CONFIGURATION=Release ./script/build_and_run.sh --verify
log stream --level debug --style compact --predicate 'subsystem == "com.davutcaliskan.Tastko" AND category == "PredictionTiming"'
```

These timing records contain only stage names and elapsed milliseconds. Targets are native suggestions within 100 ms of detecting an edit and warm AI suggestions within 700 ms of the last edit. Measure on the target Mac; Foundation Models latency depends on model readiness and system load. To run unit tests optimized, add `-configuration Release ENABLE_TESTABILITY=YES` to the test command above.

Measured locally on September 5, 2026 with Xcode 27 beta 6 and optimized builds:

| Stage | Samples | Median | p95 |
| --- | ---: | ---: | ---: |
| Accessibility context capture, running Release app | 241 | 5.75 ms | 13.82 ms |
| Native candidates, fixed English/German partial words | 20 | 3.1 ms | 13.0 ms |
| Native candidates, fixed English/German next words | 20 | 1.6 ms | 2.0 ms |
| First valid prewarmed AI suggestion | 7 | 481.8 ms | 932.7 ms |
| Full prewarmed model response | 8 | 633.4 ms | 1160.4 ms |

Native timings were remeasured after adopting the candidate API; context and AI measurements are from the earlier provider benchmark with unchanged context capture and model generation. AI timings exclude the 150 ms debounce. One of eight model samples returned no valid prefix completion and is excluded from the first-valid timing. These small samples show fast native completion, but the 700 ms AI target is not consistently met; first-valid p95 plus debounce is approximately 1083 ms. Context capture and provider benchmarks were measured separately, not as end-to-end edit-to-display timings. Completion insertion and retained external-app focus were checked in TextEdit, Chrome, and a VS Code Insiders scratch editor.

### Capture cost per keystroke

Every key Tastko posts used to wait for a full context capture first, and fields without readable text took a second capture after posting. Now, when the last capture could read the field, the key waits only for a two-request focus check; the full capture runs only for fields without readable text. After posting, a focus check replaces the second capture. The table above puts a full capture at about 6–14 ms in a responsive app, so this removes that wait from before each key in readable fields. The saving is larger in slow apps. This is derived from the capture timing above, not a new end-to-end measurement.

The fallback poll captures the whole field each time. It runs every 250 ms for fields that send no change notifications, and every second for fields that do, since key presses, clicks, and focus changes already trigger their own refresh.

## Sentence suggestions

Run `bash script/benchmark_sentences.sh` to measure the actual sentence provider
with ten fixed English/German prompts. It prints timings, generated text, and the
number of completions passing prefix and suffix format checks; this is not a grammar or semantic quality score.

Measured locally on September 9, 2026 with Xcode 27 beta 6 and optimized binaries,
using three rounds of the same six prompts per implementation:

| Implementation | Requests | Median | Maximum |
| --- | ---: | ---: | ---: |
| Original two-completion array | 18 | 1106.6 ms | 1309.3 ms |
| One `completedText` field | 18 | 918.6 ms | 1202.8 ms |

The single-suggestion version reduced median provider latency by 17%; all 18
responses passed single-completion prefix/format checks. The measurement includes
token budgeting and full generation, excludes the 500 ms request throttle,
Accessibility capture, and UI presentation, and does not represent cold-start or
continuous-typing latency. Requests used fresh sessions, default instructions and
model options, and no word hints or explicit prewarming. Results vary with model
version, output length, and system load.

Apple's [performance guidance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
explains how generated tokens affect response time. Generating one field removes
the second ending and repeated input from the output.
The [guided-generation documentation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
describes schema constraints and their token cost. We retain the schema in the
prompt and the exact-prefix validation; shorter wording and a one-element array
produced suffix-only responses in local experiments that validation rejected.

Apple recommends at least a one-second lead time for
[`prewarm(promptPrefix:)`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)).
Calling it immediately before generation would not provide that window. This
single-suggestion change preserved scheduling, cancellation, and model options.

The subsequent [latency investigation](sentence-latency-experiments.md) retained
three changes for v0.1.7, measured separately:

| Change | Measurement | Before → after |
| --- | --- | --- |
| Cache instruction/schema token counts | Median provider generation, 30 requests per version | 883.3 → 832.6 ms |
| Trim the default prompt | Median provider generation, 30 requests per version | 839.7 → 804.2 ms |
| Process one sentence request at a time | Median wait after typing, 12 replays per policy | 694.9 → 285.7 ms |

These measurements cover different stages and runs; the improvements are not
additive. Shorter output formats, schema omission, and more aggressive prompt
rewrites did not preserve quality reliably.

Run `bash script/benchmark_sentence_typing.sh --rounds 1` for a typing replay
smoke test. It includes the real sentence scheduler and model, but excludes
Accessibility capture, word prediction, and UI rendering.

The current interaction allows two overlapping sentence requests with a 250 ms
start throttle, publishing newer usable results immediately. The serial timing
above describes v0.1.7 and does not measure this subsequent policy.

The subsequent text-only prompt removes keyboard-language and native-word hints.
It measures 126 instruction tokens instead of 245. Thirty provider requests per
version measured 799.0 → 750.4 ms median (6.1%); this is separate from UI latency
and the older scheduling comparison. See the experiment report for sampling limits
and remaining grammar, partial-output, and completed-sentence behavior.
