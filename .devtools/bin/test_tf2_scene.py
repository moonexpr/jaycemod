import struct
import unittest

from tf2_scene import EVENT_HEAD, HEADER, SceneImage, scene_crc

SCENE = "scenes/bot/merasmus/low/bomb_attack_001.vcd"
SPEAK = 5


def image(scenes, strings):
    """A version 2 scenes.image: the string pool, then each scene's (uncompressed) binary VCD."""
    pool_start = HEADER.size + 4 * len(strings)
    pool, offsets = b"", []
    for text in strings:
        offsets.append(pool_start + len(pool))
        pool += text.encode() + b"\0"
    entries_at = pool_start + len(pool)
    data_at = entries_at + 16 * len(scenes)
    entries, blobs = b"", b""
    for name, vcd in scenes.items():
        entries += struct.pack("<IiiI", scene_crc(name), data_at + len(blobs), len(vcd), 0)
        blobs += vcd
    head = HEADER.pack(b"VSIF", 2, len(scenes), len(strings), entries_at)
    return head + struct.pack(f"<{len(strings)}i", *offsets) + pool + entries + blobs


class SceneImageTest(unittest.TestCase):
    def test_a_scene_crc_is_of_its_lower_case_backslashed_name(self):
        import zlib

        self.assertEqual(scene_crc("Scenes/A.vcd"), zlib.crc32(b"scenes\\a.vcd"))

    def test_finds_speak_events_by_their_shape(self):
        vcd = b"bvcd\x04\0\0\0\0\x01" + EVENT_HEAD.pack(SPEAK, 0, 0.5, 4.0, 0) + b"\xff" * 8
        found = SceneImage(image({SCENE: vcd}, ["Halloween.BombSuperMove01"])).scene_events(SCENE)
        self.assertEqual(found, [("speak", "Halloween.BombSuperMove01", 0.5, 4.0, "Halloween.BombSuperMove01")])

    def test_a_scene_not_in_the_image_is_none(self):
        self.assertIsNone(SceneImage(image({}, ["x"])).scene_events(SCENE))


if __name__ == "__main__":
    unittest.main()
