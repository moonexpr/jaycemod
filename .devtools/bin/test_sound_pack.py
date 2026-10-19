import struct
import tempfile
import unittest
from pathlib import Path

from sound_pack import Action, SoundPackError, install, plan


def wav(channels: int = 1, rate: int = 44100, bits: int = 16, frames: int = 4, extra: bytes = b"") -> bytes:
    data = bytes(frames * channels * bits // 8)
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * channels * bits // 8, channels * bits // 8, bits)
    body = b"WAVE" + extra + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


MP3 = b"ID3\x04\x00\x00\x00\x00\x00\x00" + bytes(32)


class Plan(unittest.TestCase):
    def test_mono_pcm_at_a_source_rate_is_copied_as_it_is(self):
        self.assertEqual(plan(wav()), Action.COPY)
        self.assertEqual(plan(wav(rate=22050, bits=8)), Action.COPY)

    def test_a_chunk_before_fmt_is_skipped(self):
        self.assertEqual(plan(wav(extra=b"LIST" + struct.pack("<I", 3) + b"abc\x00")), Action.COPY)

    def test_stereo_is_made_mono_so_it_plays_where_its_speaker_is(self):
        self.assertEqual(plan(wav(channels=2)), Action.CONVERT)

    def test_a_rate_source_cannot_play_is_converted(self):
        self.assertEqual(plan(wav(rate=48000)), Action.CONVERT)

    def test_an_mp3_named_wav_is_decoded(self):
        self.assertEqual(plan(MP3), Action.CONVERT)

    def test_anything_else_is_refused(self):
        with self.assertRaises(SoundPackError):
            plan(b"PK\x03\x04" + bytes(40))
        with self.assertRaises(SoundPackError):
            plan(b"RIFF" + bytes(4) + b"WAVE")  # no fmt chunk


class Install(unittest.TestCase):
    def test_copies_and_converts_under_the_same_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack, dest = Path(tmp, "pack"), Path(tmp, "dest")
            (pack / "npc/a").mkdir(parents=True)
            (pack / "npc/a/mono.wav").write_bytes(wav())
            (pack / "npc/a/stereo.wav").write_bytes(wav(channels=2))
            (pack / "npc/a/readme.txt").write_text("not a sound")
            converted = []

            def convert(source: Path, target: Path) -> None:
                converted.append(source.name)
                target.write_bytes(wav())

            report = install(pack, dest, convert)
            self.assertEqual((dest / "npc/a/mono.wav").read_bytes(), wav())
            self.assertEqual((dest / "npc/a/stereo.wav").read_bytes(), wav())
            self.assertEqual(converted, ["stereo.wav"])
            self.assertFalse((dest / "npc/a/readme.txt").exists())
            self.assertEqual(report, {Action.COPY: 1, Action.CONVERT: 1})

    def test_a_conversion_that_is_still_not_playable_is_our_bug(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack, dest = Path(tmp, "pack"), Path(tmp, "dest")
            pack.mkdir()
            (pack / "x.wav").write_bytes(wav(channels=2))
            with self.assertRaises(SoundPackError):
                install(pack, dest, lambda source, target: target.write_bytes(wav(channels=2)))


if __name__ == "__main__":
    unittest.main()
