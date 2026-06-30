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

Local STT and TTS providers must not be marked release-ready just because a model is present. Provider-specific runtime smoke checks remain part of #13 and #14.

## Accessibility Boundary

Product TTS is not VoiceOver. Local TTS can read short SoloPM prompts such as overdue counts or task creation summaries, but it does not replace manual VoiceOver evidence. Screen-reader accessibility remains a separate release gate under `docs/release/checklist.md`.
