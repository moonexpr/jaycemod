"""vpk.py reads a Valve pak's directory and its files: in the directory file
itself (archive 0x7fff), in a numbered archive beside it, and with preload
bytes kept in the tree. The paks are built here, byte by byte."""
import struct
from pathlib import Path

import pytest

from vpk import DIR_ARCHIVE, Vpk, VpkError

SIGNATURE = 0x55AA1234


def entry(crc: int, preload: bytes, archive: int, offset: int, length: int) -> bytes:
    return struct.pack("<IHHIIH", crc, len(preload), archive, offset, length, 0xFFFF) + preload


def tree(files) -> bytes:
    """files: (ext, path, name, entry bytes), grouped by ext then path."""
    out = b""
    by_ext = {}
    for ext, path, name, data in files:
        by_ext.setdefault(ext, {}).setdefault(path, []).append((name, data))
    for ext, paths in by_ext.items():
        out += ext.encode() + b"\0"
        for path, names in paths.items():
            out += path.encode() + b"\0"
            for name, data in names:
                out += name.encode() + b"\0" + data
            out += b"\0"
        out += b"\0"
    return out + b"\0"


def write_pak(directory: Path, base: str, files, inline_data: bytes = b"", archives=None) -> Path:
    t = tree(files)
    header = struct.pack("<IIIIIII", SIGNATURE, 2, len(t), len(inline_data), 0, 0, 0)
    dir_path = directory / f"{base}_dir.vpk"
    dir_path.write_bytes(header + t + inline_data)
    for index, data in (archives or {}).items():
        (directory / f"{base}_{index:03d}.vpk").write_bytes(data)
    return dir_path


@pytest.fixture
def pak(tmp_path: Path) -> Path:
    archive0 = b"xxxx" + b'"Cart.Roll" { "wave" "cart.wav" }'
    inline = b"manifest-body"
    files = [
        ("txt", "scripts", "game_sounds", entry(0, b"", 0, 4, len(archive0) - 4)),
        ("txt", "scripts", "game_sounds_manifest", entry(0, b"", DIR_ARCHIVE, 0, len(inline))),
        ("txt", "scripts", "preloaded", entry(0, b"head-", DIR_ARCHIVE, len(inline), 0)),
        ("res", " ", "rootfile", entry(0, b"at-root", DIR_ARCHIVE, len(inline), 0)),
    ]
    return write_pak(tmp_path, "tf2_misc", files, inline_data=inline, archives={0: archive0})


def test_lists_every_file_by_its_path(pak):
    assert sorted(Vpk.open(pak).names()) == [
        "rootfile.res", "scripts/game_sounds.txt", "scripts/game_sounds_manifest.txt", "scripts/preloaded.txt"]


def test_reads_a_file_from_its_numbered_archive(pak):
    assert Vpk.open(pak).read("scripts/game_sounds.txt") == b'"Cart.Roll" { "wave" "cart.wav" }'


def test_reads_a_file_kept_in_the_directory_file_itself(pak):
    assert Vpk.open(pak).read("scripts/game_sounds_manifest.txt") == b"manifest-body"


def test_preload_bytes_lead_the_file(pak):
    assert Vpk.open(pak).read("scripts/preloaded.txt") == b"head-"


def test_a_root_file_has_no_folder(pak):
    assert Vpk.open(pak).read("rootfile.res") == b"at-root"


def test_paths_are_matched_without_regard_to_case(pak):
    assert Vpk.open(pak).read("Scripts/Game_Sounds.TXT") == b'"Cart.Roll" { "wave" "cart.wav" }'


def test_a_file_not_in_the_pak_is_refused_by_name(pak):
    with pytest.raises(KeyError, match="scripts/nope.txt"):
        Vpk.open(pak).read("scripts/nope.txt")


def test_a_file_that_is_not_a_pak_is_refused(tmp_path):
    bad = tmp_path / "bad_dir.vpk"
    bad.write_bytes(b"\0" * 32)
    with pytest.raises(VpkError):
        Vpk.open(bad)
