# SoloPM Voice Model Cache

SoloPM does not bundle local STT or TTS model binaries in the repository or app bundle. Local OSS voice models are installed only after an explicit user action in Settings, then stored in the user's application support directory.

## Cache Location

Default cache root:

```text
~/Library/Application Support/SoloPM/VoiceModels/
```

Test and development fixtures should stay under `.tmp/`, which is already ignored by git. Do not commit downloaded model binaries, `.partial` files, generated model caches, or alternate local cache roots.

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

Local TTS remains disabled in the release surface until a TTS runtime has the same model, executable, and smoke-test gates.

## Accessibility Boundary

Product TTS is not VoiceOver. Local TTS can read short SoloPM prompts such as overdue counts or task creation summaries, but it does not replace manual VoiceOver evidence. Screen-reader accessibility remains a separate release gate under `docs/release/checklist.md`.
