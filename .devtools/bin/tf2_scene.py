#!/usr/bin/env python3
"""Print the events TF2's scenes/scenes.image holds for a scene: speak, gesture and sequence.

  tf2_scene.py scenes/bot/merasmus/low/bomb_attack_001.vcd ...

TF2 ships its scenes only inside scenes.image (in tf2_misc_dir.vpk), so a scene's
sounds and gestures cannot be read from a loose .vcd. Prints each scene's events
(the sound a speak plays, the activity a gesture plays), or MISSING. Exit 1 if any
is missing.
"""
import lzma
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tf2_content  # noqa: E402

IMAGE = "scenes/scenes.image"
HEADER = struct.Struct("<4siiii")  # id, version, scenes, strings, entry offset
LZMA_ID = b"LZMA"
LZMA_HEADER = struct.Struct("<4sII5s")  # id, actual size, compressed size, properties
EVENT_HEAD = struct.Struct("<BHffH")  # type, name, start, end, parameters
# CChoreoEvent::EVENTTYPE, the kinds a bot's scene uses
EVENT_TYPES = {
    5: "speak",
    6: "gesture",
    7: "sequence",
}
MAX_SCENE_SECONDS = 120


def scene_crc(name: str) -> int:
    return zlib.crc32(name.lower().replace("/", "\\").encode()) & 0xFFFFFFFF


def decompress(blob: bytes) -> bytes:
    if blob[:4] != LZMA_ID:
        return blob
    _, size, packed, props = LZMA_HEADER.unpack_from(blob)
    lc, rest = props[0] % 9, props[0] // 9
    filters = [{"id": lzma.FILTER_LZMA1, "dict_size": struct.unpack("<I", props[1:5])[0], "lc": lc, "lp": rest % 5, "pb": rest // 5}]
    start = LZMA_HEADER.size
    return lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=filters).decompress(blob[start : start + packed])[:size]


class SceneImage:
    def __init__(self, data: bytes):
        self.data = data
        _, version, scenes, strings, entries = HEADER.unpack_from(data)
        self.strings = struct.unpack_from(f"<{strings}i", data, HEADER.size)
        entry = struct.Struct("<IiiI")  # crc, offset, length, summary offset
        self.entries = {}
        for k in range(scenes):
            crc, offset, length = entry.unpack_from(data, entries + k * entry.size)[:3]
            self.entries[crc] = (offset, length)

    def string(self, index: int) -> str:
        start = self.strings[index]
        return self.data[start : self.data.index(b"\0", start)].decode("latin1")

    def scene_events(self, name: str):
        """The scene's events as (type name, event name, start, end, parameters), or None.

        A binary VCD event begins: type (byte), name (pool index), start and end
        (floats), parameters (pool index) (CChoreoEvent::RestoreFromBuffer). The
        records are found by that shape rather than by walking the whole format.
        """
        found = self.entries.get(scene_crc(name))
        if found is None:
            return None
        offset, length = found
        vcd = decompress(self.data[offset : offset + length])
        events = []
        for pos in range(len(vcd) - EVENT_HEAD.size):
            kind, name_index, start, end, params = EVENT_HEAD.unpack_from(vcd, pos)
            if kind not in EVENT_TYPES or name_index >= len(self.strings) or params >= len(self.strings):
                continue
            if not (0 <= start <= end <= MAX_SCENE_SECONDS):
                continue
            events.append((EVENT_TYPES[kind], self.string(name_index), round(start, 3), round(end, 3), self.string(params)))
        return events


def main(argv) -> int:
    image = SceneImage(tf2_content.Tf2Install(tf2_content.TF_DIR).read(IMAGE))
    status = 0
    for name in argv:
        events = image.scene_events(name)
        if events is None:
            print(f"{name}: MISSING")
            status = 1
            continue
        print(name)
        for kind, event, start, end, params in events:
            print(f"  {kind} {event!r} {start}-{end} s: {params}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
