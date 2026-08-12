# Inbox wide visual evidence

This evidence records the Inbox composition at the widest runtime viewport
available to the local macOS capture surface. The reference image is 1400x1024;
the local display reserves 49px for system chrome, so the truthful captured
viewport is 1400x975 rather than an artificially cropped 1400x1024 image.

The left navigation is intentionally present in these captures only because the
runtime window owns it; the Inbox fidelity scope is the main list, triage rail,
voice playback, transcript, proposed actions, and detail information.

- Light Inbox: `ui-screenshots/inbox-wide-light.png`
- Dark Inbox: `ui-screenshots/inbox-wide-dark.png`
- Light Inbox voice detail: `ui-screenshots/inbox-voice-wide-light.png`
- Dark Inbox voice detail: `ui-screenshots/inbox-voice-wide-dark.png`
- Japanese light Inbox: `ui-screenshots-ja/inbox-wide-light.png`
- Japanese dark Inbox: `ui-screenshots-ja/inbox-wide-dark.png`
- Japanese light Inbox voice detail: `ui-screenshots-ja/inbox-voice-wide-light.png`
- Japanese dark Inbox voice detail: `ui-screenshots-ja/inbox-voice-wide-dark.png`

Capture command:

```sh
SUISUI_VISUAL_BASELINE_VIEWPORT=1400x975 \
  SUISUI_UI_EVIDENCE_DIR=docs/release/evidence/ui-screenshots \
  script/capture_ui_evidence.sh --p0-workflows
```

Runtime behavior was independently verified by
`script/check_runtime_inbox_triage_smoke.sh`, including quick add, task
classification, schedule, review later, project conversion, and Undo. Voice
playback was independently verified by
`script/check_runtime_inbox_voice_playback_smoke.sh`, including restart,
play/pause, progress, seek, selection stop, and missing-audio fallback.
