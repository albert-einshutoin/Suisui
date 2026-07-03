# ADR 0010: Local Kokoro TTS Boundary

Date: 2026-06-30
Status: Accepted

## Context

SoloPM's Personal MVP is voice-first: it should capture work by voice, clarify intent, and read back short confirmations such as overdue counts, created task summaries, and reminder results. Product TTS is separate from VoiceOver evidence; screen-reader validation remains a release gate and must not be treated as the assistant's speech runtime.

Issue #14 asks for a local OSS TTS path for Japanese and English. The first release must avoid bundling large model files in git or the app bundle, and it must not introduce a license or notarization problem while still letting users prove a ready local runtime can play a short preview.

## Decision

Use Kokoro as the first ready-gated local TTS provider surface for short Japanese and English assistant prompts.

SoloPM will:

- Keep Kokoro model files outside git and the app bundle.
- Reuse the existing `VoiceModelManager` download/cache/checksum contract.
- Expose Local Kokoro readiness in Settings even when the model or runtime is not installed.
- Require a user-configured absolute executable path before treating Kokoro as ready.
- Pass prompt text through a short-lived UTF-8 file instead of process arguments so task details are not exposed through process inspection.
- Play only fixed short Settings preview prompts through an AVAudioPlayer adapter; user task text and meeting documents are not sent through this path.
- Remove the preview-owned generated audio directory after playback.
- Limit the first slice to short prompts, no-network cached synthesis, and local preview playback.

## Options Considered

### Kokoro

- Pros: Apache-2.0 model card, small model family for TTS, Japanese and English voice metadata, already present in SoloPM's `VoiceModelCatalog`.
- Cons: The reference runtime commonly involves Python/PyTorch and phonemizer dependencies, so app-bundle integration, Swift-native playback, and notarized packaging need a later dedicated slice.

### sherpa-onnx

- Pros: Offline speech stack with Swift/iOS/macOS examples and a path toward a single local voice runtime.
- Cons: ONNX runtime packaging, model conversion, dylib signing, and notarization risk are larger than a first Personal MVP readiness slice.

### Piper

- Pros: Lightweight local TTS ecosystem with strong English voice availability.
- Cons: The current official project path is GPL-oriented and Japanese coverage was not confirmed as a safe first provider, so it is not the first SoloPM TTS provider.

## Consequences

- Positive: Personal MVP gains a real product TTS provider boundary without relying on VoiceOver or system speech.
- Positive: Settings can show what is missing before users attempt playback.
- Positive: OSS distribution stays clean because model binaries and generated audio remain out of git.
- Negative: The first slice does not ship long-form document/meeting read-aloud, streaming controls, or a bundled runtime.
- Follow-up: Decide the packaged Kokoro runtime path and add a signed/notarized smoke test before marking #14 fully complete.

## Links

- Related issue: https://github.com/albert-einshutoin/soloPM/issues/14
- Kokoro repository: https://github.com/hexgrad/kokoro
- Kokoro model card: https://huggingface.co/hexgrad/Kokoro-82M
- sherpa-onnx repository: https://github.com/k2-fsa/sherpa-onnx
- Piper repository: https://github.com/OHF-Voice/piper1-gpl
- Related implementation: Sources/SoloPMCore/Voice/TTSProviders.swift
- Related tests: Tests/SoloPMCoreTests/TTSProviderTests.swift
