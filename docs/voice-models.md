# SoloPM Voice Model Cache

SoloPM does not bundle local STT or TTS model binaries in the repository or app bundle. Local OSS voice models are installed only after an explicit user action in Settings, then stored in the user's application support directory.

## Cache Location

Default cache root:

```text
~/Library/Application Support/SoloPM/VoiceModels/
```

Test and development fixtures should stay under `.tmp/`, which is already ignored by git. Do not commit downloaded model binaries, `.partial` files, generated model caches, or alternate local cache roots.

## No-Bundle Guard

`script/check_security_regressions.sh` blocks tracked local voice model binaries by checking `git ls-files` for model file extensions such as `.gguf`, `.ggml`, `.onnx`, `.safetensors`, `.pt`, `.pth`, `.tflite`, `.mlmodel`, and `.mlpackage`, plus model-named `.bin` files such as whisper.cpp `ggml-*.bin` artifacts.

This guard intentionally checks only tracked files. Downloaded models, smoke-test artifacts, and developer fixtures can exist in `.tmp/` or the user cache without failing the release scan, but any model binary added to the repository or app bundle source tree must fail before PR merge.

## Phase 1 Catalog

| Purpose | Engine | Model | Languages | Size | License | Source |
| --- | --- | --- | --- | ---: | --- | --- |
| STT | whisper.cpp | `ggml-tiny.bin` | Japanese, English | 77,691,713 bytes | MIT | `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin` |
| TTS | Kokoro | `kokoro-v1_0.pth` | Japanese, English | 327,212,226 bytes | Apache-2.0 | `https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth` |

The catalog records HTTPS source URLs, license names, estimated sizes, cache file names, language coverage, and mandatory checksums. The first STT provider should use the multilingual whisper.cpp tiny model because it is smaller than base and covers Japanese plus English. Kokoro is tracked as the first local TTS candidate because its model card uses Apache-2.0 and its voices list includes Japanese and English voices.

## Install Contract

`VoiceModelManager` downloads through a file-based `VoiceModelDownloadClient`, stages the result as `*.partial`, verifies the configured checksum, and only then moves it into the final cache location. A failed checksum removes the partial file and returns a sanitized UI-facing error.

Settings can show:

- `Not installed`
- `Downloading`
- `Installed`
- `Failed`
- `Needs reinstall`

The whisper.cpp STT provider is selectable only when both local runtime requirements are ready:

- The `ggml-tiny.bin` model is installed and checksum-verified.
- Settings has an absolute, executable `whisper-cli` path.

Transcription re-verifies the model checksum before launching `whisper-cli`, runs the local process without a shell or PATH lookup, and never downloads a model during transcription. Non-WAV recordings are converted locally with `/usr/bin/afconvert` into a temporary 16-bit 16 kHz WAV file, then the temporary directory is removed after the attempt.

The current invocation follows the whisper.cpp CLI shape documented upstream:

```text
whisper-cli -m <model> -f <prepared-audio.wav> -l auto|ja|en -np -nt
```

References:

- whisper.cpp README: https://github.com/ggml-org/whisper.cpp
- whisper.cpp CLI README: https://github.com/ggml-org/whisper.cpp/tree/master/examples/cli
- whisper.cpp model catalog: https://github.com/ggml-org/whisper.cpp/tree/master/models

Local TTS now exposes a ready-gated Kokoro surface in Settings. The provider is visible as `Local Kokoro`, but speech synthesis and Test Play remain blocked until both local runtime requirements are ready:

- The `kokoro-v1_0.pth` model is installed and checksum-verified.
- Settings has an absolute, executable Kokoro runtime path.

The first Kokoro provider slice is intentionally short-prompt only. It re-verifies the cached model before local synthesis and passes prompt text through a short-lived UTF-8 file instead of command-line arguments so task details are not exposed through process inspection. Settings Test Play uses fixed Japanese/English sample prompts, plays the generated WAV through the app's AVFoundation audio adapter, and removes the preview-owned output directory after playback. Long-form document read-aloud, bundled runtime packaging, and signed/notarized smoke evidence remain follow-up work.

## Runtime Proof For Issue Closeout

Issue closeout for local voice work needs runtime evidence in addition to source tests:

- Model manager readiness: `script/check_security_regressions.sh` passes, no model binaries are tracked by `git ls-files`, Settings shows the model rows, and install/remove actions use the application support cache.
- STT readiness: a checksum-verified `ggml-tiny.bin` is installed, Settings points to an absolute executable `whisper-cli`, and a Japanese or English sample WAV produces a transcript from the local provider.
- TTS readiness: a checksum-verified `kokoro-v1_0.pth` is installed, Settings points to an absolute executable Kokoro runtime path, and Settings Test Play produces and plays a local WAV for Japanese and English prompts.
- Packaging readiness: the signed app keeps model binaries out of the repository and app bundle, while runtime paths continue to resolve only to user-selected executables and cache files.

Until those runtime checks are captured, source-only changes can close the no-bundled-model safety condition for the model manager, but they do not by themselves prove the whisper.cpp STT or Kokoro TTS providers are ready in a packaged app.

`script/check_local_voice_runtime_smoke.sh` is the runtime smoke entrypoint for both boundaries, but the closeout scope depends on the mode. It performs no network download and expects the model cache and executable paths to already exist.

- Issue #13 STT-only smoke: `--stt-only` verifies local whisper.cpp transcription only, does not prove Kokoro TTS, and cannot be used for #14 or full release closeout.
- Issue #14 full STT + TTS smoke: default mode verifies local whisper.cpp STT plus Kokoro Japanese/English TTS and is the path used by release readiness evidence.

Default full STT + TTS mode:

```sh
SOLOPM_WHISPER_CPP_EXECUTABLE=/absolute/path/to/whisper-cli \
SOLOPM_STT_SAMPLE_WAV=/absolute/path/to/sample-ja-or-en.wav \
SOLOPM_KOKORO_EXECUTABLE=/absolute/path/to/kokoro-runtime \
./script/check_local_voice_runtime_smoke.sh
```

Issue #13 STT-only smoke:

```sh
SOLOPM_WHISPER_CPP_EXECUTABLE=/absolute/path/to/whisper-cli \
SOLOPM_STT_SAMPLE_WAV=/absolute/path/to/sample-ja-or-en.wav \
./script/check_local_voice_runtime_smoke.sh --stt-only
```

To create tracked evidence for an STT-only pass, keep it under
`docs/release/evidence/*stt-only*.md` and make the limitation explicit:

```sh
SOLOPM_WHISPER_CPP_EXECUTABLE=/absolute/path/to/whisper-cli \
SOLOPM_STT_SAMPLE_WAV=/absolute/path/to/sample-ja-or-en.wav \
SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS="<expected words>" \
SOLOPM_LOCAL_VOICE_EVIDENCE_FILE=docs/release/evidence/local-voice-runtime-stt-only.md \
./script/check_local_voice_runtime_smoke.sh --stt-only
```

That evidence records that TTS was not verified, does not prove Kokoro TTS,
and cannot be used for #14 or full release closeout. The STT-only mode refuses
to write `docs/release/evidence/local-voice-runtime.md`; that canonical file is
reserved for the default full STT + Japanese/English TTS release evidence.

To create the tracked closeout evidence used by release readiness, the STT
sample must include a known phrase and the default smoke must cover both
Japanese and English Kokoro prompts:

```sh
SOLOPM_WHISPER_CPP_EXECUTABLE=/absolute/path/to/whisper-cli \
SOLOPM_STT_SAMPLE_WAV=/absolute/path/to/sample-ja-or-en.wav \
SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS="<expected words>" \
SOLOPM_KOKORO_EXECUTABLE=/absolute/path/to/kokoro-runtime \
SOLOPM_LOCAL_VOICE_EVIDENCE_FILE=docs/release/evidence/local-voice-runtime.md \
./script/check_local_voice_runtime_smoke.sh
```

The verifier defaults to `~/Library/Application Support/SoloPM/VoiceModels`, or `SOLOPM_LOCAL_VOICE_CACHE_ROOT` when testing an alternate cache. It checks the recorded `ggml-tiny.bin` SHA-256 before launching STT in every mode, and in default full mode it also checks `kokoro-v1_0.pth` before launching TTS. It writes smoke artifacts under `.tmp/local-voice-runtime-smoke` by default, and accepts `SOLOPM_LOCAL_VOICE_SMOKE_OUTPUT_DIR` for a separate ignored artifact directory. The full smoke requires `SOLOPM_WHISPER_CPP_EXECUTABLE`, `SOLOPM_STT_SAMPLE_WAV`, and `SOLOPM_KOKORO_EXECUTABLE` so missing local setup fails as an explicit `BLOCKER:` instead of being mistaken for release readiness. `--stt-only` intentionally skips the Kokoro executable/model/TTS language requirements so #13 can advance independently of #14. When `SOLOPM_LOCAL_VOICE_EVIDENCE_FILE` is set in full mode, `SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS` and both `ja` / `en` TTS languages are required so tracked evidence proves real transcription content plus Japanese and English WAV generation. The tracked evidence records no-network and no-bundled-model boundaries, but it does not prove Settings Test Play or VoiceOver accessibility; those remain separate closeout gates.

By default the TTS half synthesizes both Japanese and English prompts using `SOLOPM_TTS_LANGUAGES="ja en"`, `SOLOPM_TTS_JA_VOICE_ID=jf_alpha`, and `SOLOPM_TTS_EN_VOICE_ID=af_heart`. STT defaults to `SOLOPM_STT_LANGUAGE=ja`, but release reviewers can set `SOLOPM_STT_LANGUAGE=en` or `auto` when the sample WAV is English or mixed language.

## Accessibility Boundary

Product TTS is not VoiceOver. Local TTS can read short SoloPM prompts such as overdue counts or task creation summaries, but it does not replace manual VoiceOver evidence. Screen-reader accessibility remains a separate release gate under `docs/release/checklist.md`.
