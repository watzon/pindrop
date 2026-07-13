#!/usr/bin/env python3
"""Fetch checksum-pinned AMI diarization fixtures declared in manifest.json.

The committed manifest is the reviewable source of truth. The script never chooses
an alternate URL or silently changes a checksum. Audio conversion uses ffmpeg to
produce 16 kHz mono float PCM WAV files, while reference intervals are copied from
the manifest's deterministic AMI-window selection output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "PindropTests/Fixtures/Diarization/manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Pindrop diarization fixture fetcher"})
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def convert_to_16k_mono(
    source: Path,
    destination: Path,
    *,
    start_seconds: float | None = None,
    end_seconds: float | None = None,
) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("ffmpeg is required to generate diarization fixtures")
    command = [ffmpeg, "-y", "-v", "error"]
    if start_seconds is not None:
        command.extend(["-ss", str(start_seconds)])
    command.extend(["-i", str(source)])
    if end_seconds is not None:
        if start_seconds is None:
            command.extend(["-to", str(end_seconds)])
        else:
            command.extend(["-t", str(max(0.0, end_seconds - start_seconds))])
    command.extend(["-ar", "16000", "-ac", "1", "-c:a", "pcm_f32le", str(destination)])
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output-root", type=Path, default=ROOT / "PindropTests/Fixtures/Diarization/Generated")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    fixtures = manifest.get("fixtures", [])
    if not fixtures:
        raise SystemExit("manifest contains no checksum-pinned fixtures; populate it from official AMI windows first")

    args.output_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pindrop-diarization-") as temporary:
        temporary_root = Path(temporary)
        generated_fixtures = []
        for fixture in fixtures:
            fixture_id = fixture["id"]
            source_url = fixture["source_url"]
            expected_sha = fixture["sha256"]
            source = temporary_root / f"{fixture_id}.source"
            download(source_url, source)
            actual_sha = sha256(source)
            if actual_sha != expected_sha:
                raise SystemExit(f"checksum mismatch for {fixture_id}: expected {expected_sha}, got {actual_sha}")
            audio_path = args.output_root / fixture["audio"]
            audio_path.parent.mkdir(parents=True, exist_ok=True)
            convert_to_16k_mono(
                source,
                audio_path,
                start_seconds=fixture.get("start_seconds"),
                end_seconds=fixture.get("end_seconds"),
            )
            reference_path = args.output_root / fixture["reference"]
            reference_path.parent.mkdir(parents=True, exist_ok=True)
            reference_path.write_text(json.dumps(fixture["reference_intervals"], indent=2) + "\n", encoding="utf-8")
            generated_fixtures.append(
                {
                    "id": fixture_id,
                    "audio": fixture["audio"],
                    "expectedSpeakerCount": fixture["expected_speaker_count"],
                }
            )
            print(f"generated {fixture_id}: {audio_path}")
        (args.output_root / "manifest.json").write_text(
            json.dumps({"fixtures": generated_fixtures}, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
