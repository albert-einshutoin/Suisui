#!/usr/bin/env python3
"""Local Kokoro TTS runtime adapter for SoloPM smoke tests.

This wrapper intentionally exposes the small executable contract expected by
SoloPM instead of asking the app to know Kokoro's Python package internals.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys
from pathlib import Path


SAMPLE_RATE = 24_000
SAFE_VOICE_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a local WAV with a cached Kokoro model and voice pack."
    )
    parser.add_argument("--model", required=True, help="Absolute path to kokoro-v1_0.pth")
    parser.add_argument("--text-file", required=True, help="UTF-8 prompt text file")
    parser.add_argument("--language", required=True, choices=["ja", "en"], help="Prompt language")
    parser.add_argument("--voice", required=True, help="Kokoro voice id, for example jf_alpha or af_heart")
    parser.add_argument("--output", required=True, help="WAV output path")
    parser.add_argument("--config", help="Optional path to Kokoro config.json; defaults next to --model")
    parser.add_argument("--voice-dir", help="Optional path to Kokoro voices directory; defaults next to --model")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed multiplier")
    parser.add_argument("--device", default="cpu", help="Torch device; defaults to cpu for release-smoke repeatability")
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"BLOCKER: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_file(label: str, path: Path) -> Path:
    if not path.is_absolute():
        fail(f"{label} path must be absolute")
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"{label} is missing or empty")
    return path


def resolve_voice_file(voice_dir: Path, voice_id: str) -> Path:
    # Voice ids are user-configured runtime input, so keep them to simple ids
    # and resolve inside the local cache instead of accepting arbitrary paths.
    if not SAFE_VOICE_ID.fullmatch(voice_id):
        fail("Kokoro voice id must contain only letters, numbers, underscore, or hyphen")
    return require_file("Kokoro voice pack", voice_dir / f"{voice_id}.pt")


def kokoro_language_code(language: str, voice_id: str) -> str:
    if language == "ja":
        if not voice_id.startswith("j"):
            fail("Japanese Kokoro voice id must start with j")
        return "j"
    if not voice_id.startswith(("a", "b")):
        fail("English Kokoro voice id must start with a or b")
    return "b" if voice_id.startswith("b") else "a"


def check_offline_language_assets(language: str) -> None:
    if language == "en" and importlib.util.find_spec("en_core_web_sm") is None:
        fail("English Kokoro G2P model en_core_web_sm is not installed in this Python environment")


def prefer_unidic_lite_for_japanese() -> None:
    if importlib.util.find_spec("unidic_lite") is None:
        return
    try:
        import unidic
        import unidic_lite
    except Exception:
        return
    # misaki's Japanese cutlet path constructs fugashi.Tagger() without
    # arguments. If the full unidic package is present but its dictionary was
    # not downloaded, point it at unidic-lite so local smoke stays small.
    if not Path(unidic.DICDIR, "mecabrc").is_file():
        unidic.DICDIR = unidic_lite.DICDIR


def main() -> int:
    args = parse_args()

    model_path = require_file("Kokoro model", Path(args.model).expanduser())
    text_path = require_file("Kokoro prompt", Path(args.text_file).expanduser())
    config_path = require_file(
        "Kokoro config",
        Path(args.config).expanduser() if args.config else model_path.parent / "config.json",
    )
    voice_dir = Path(args.voice_dir).expanduser() if args.voice_dir else model_path.parent / "voices"
    if not voice_dir.is_absolute():
        fail("Kokoro voice directory path must be absolute")
    if not voice_dir.is_dir():
        fail("Kokoro voice directory is missing")
    voice_path = resolve_voice_file(voice_dir, args.voice)
    output_path = Path(args.output).expanduser()
    if not output_path.is_absolute():
        fail("Kokoro output path must be absolute")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    prompt = text_path.read_text(encoding="utf-8").strip()
    if not prompt:
        fail("Kokoro prompt is empty")

    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    check_offline_language_assets(args.language)
    if args.language == "ja":
        prefer_unidic_lite_for_japanese()

    try:
        import numpy as np
        import soundfile as sf
        from kokoro import KModel, KPipeline
    except Exception as error:  # pragma: no cover - exercised by local runtime setup
        fail(f"Kokoro Python runtime dependency is unavailable: {error}")

    try:
        model = KModel(
            repo_id="hexgrad/Kokoro-82M",
            config=str(config_path),
            model=str(model_path),
        ).to(args.device).eval()
        pipeline = KPipeline(
            lang_code=kokoro_language_code(args.language, args.voice),
            repo_id="hexgrad/Kokoro-82M",
            model=model,
            device=args.device,
        )
        chunks = []
        for result in pipeline(
            prompt,
            voice=str(voice_path),
            speed=args.speed,
            split_pattern=r"\n+",
        ):
            if result.audio is not None:
                chunks.append(result.audio.detach().cpu().numpy())
        if not chunks:
            fail("Kokoro synthesis produced no audio")
        audio = chunks[0] if len(chunks) == 1 else np.concatenate(chunks)
        sf.write(str(output_path), audio, SAMPLE_RATE)
    except SystemExit:
        raise
    except Exception as error:
        fail(f"Kokoro synthesis failed: {error}")

    if output_path.stat().st_size == 0:
        fail("Kokoro output WAV is empty")
    print(f"OK: wrote Kokoro WAV to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
