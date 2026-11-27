#!/usr/bin/env python3
"""Install a sound replacement pack's .wav files under a content sound/ folder,
at the same paths, so they shadow the game's own (a gamemode's content/ folder
wins over HL2's VPKs).

  sound_pack.py PACK_SOUND_DIR DEST_SOUND_DIR

A file Source plays as it is (RIFF PCM, mono, 11025/22050/44100 Hz) is copied
byte for byte. Anything else it would play wrong or not at all is converted
with ffmpeg to 16-bit mono PCM at its own Source rate (44100 Hz otherwise):
stereo, which Source plays without position, so a speaker would not sound
where they stand; an MP3 named .wav, which it does not play. Files other than
.wav are left out.
"""
import argparse
import shutil
import struct
import subprocess
import sys
from enum import Enum
from pathlib import Path
from typing import Callable

SOURCE_RATES = (11025, 22050, 44100)
PCM = 1


class SoundPackError(Exception):
    pass


class Action(Enum):
    COPY = "copy"
    CONVERT = "convert"


def _fmt(data: bytes) -> tuple[int, int, int] | None:
    """A RIFF WAVE's (format tag, channels, rate), or None for another file."""
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    i = 12
    while i + 8 <= len(data):
        cid, size = data[i:i + 4], struct.unpack_from("<I", data, i + 4)[0]
        if cid == b"fmt ":
            tag, channels, rate = struct.unpack_from("<HHI", data, i + 8)
            return tag, channels, rate
        i += 8 + size + (size & 1)
    raise SoundPackError("a WAVE file with no fmt chunk")


def _is_mp3(data: bytes) -> bool:
    return data[:3] == b"ID3" or (len(data) > 1 and data[0] == 0xFF and data[1] & 0xE0 == 0xE0)


def plan(data: bytes) -> Action:
    """What a pack file needs before Source plays it where its speaker is."""
    fmt = _fmt(data)
    if fmt is None:
        if _is_mp3(data):
            return Action.CONVERT
        raise SoundPackError("neither a WAVE nor an MP3 file")
    tag, channels, rate = fmt
    if tag == PCM and channels == 1 and rate in SOURCE_RATES:
        return Action.COPY
    return Action.CONVERT


def ffmpeg_convert(source: Path, target: Path) -> None:
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=sample_rate",
         "-of", "csv=p=0", str(source)], check=True, capture_output=True, text=True)
    rate = int(probe.stdout.strip())
    rate = rate if rate in SOURCE_RATES else SOURCE_RATES[-1]
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(source), "-map_metadata", "-1", "-ac", "1", "-ar", str(rate),
         "-c:a", "pcm_s16le", "-f", "wav", str(target)], check=True)


def install(pack: Path, dest: Path, convert: Callable[[Path, Path], None]) -> dict[Action, int]:
    """Every .wav under pack, at its path under dest; how many of each action."""
    report = {Action.COPY: 0, Action.CONVERT: 0}
    for source in sorted(pack.rglob("*")):
        if not source.is_file() or source.suffix.lower() != ".wav":
            continue
        target = dest / source.relative_to(pack)
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            action = plan(source.read_bytes())
        except SoundPackError as e:
            raise SoundPackError(f"{source}: {e}") from e
        if action is Action.COPY:
            shutil.copyfile(source, target)
        else:
            convert(source, target)
            if plan(target.read_bytes()) is not Action.COPY:
                raise SoundPackError(f"{target}: still not a file Source plays as it is after converting")
        report[action] += 1
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pack", type=Path, help="the pack's sound/ folder")
    parser.add_argument("dest", type=Path, help="the content sound/ folder to install into")
    args = parser.parse_args()
    report = install(args.pack, args.dest, ffmpeg_convert)
    print(f"copied {report[Action.COPY]}, converted {report[Action.CONVERT]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
