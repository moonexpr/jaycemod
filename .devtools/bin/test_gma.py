import struct
import unittest

from gma import Gma, GmaError, GmaFile, read_gma, write_gma


def gma_with(files: list[tuple[str, bytes]], version: int = 3) -> bytes:
    out = bytearray(b"GMAD" + bytes([version]) + struct.pack("<QQ", 1, 2))
    if version > 1:
        out += b"\x00"  # no required content
    out += b"name\x00desc\x00author\x00" + struct.pack("<i", 1)
    for number, (path, data) in enumerate(files, start=1):
        out += struct.pack("<I", number) + path.encode() + b"\x00" + struct.pack("<qI", len(data), 0)
    out += struct.pack("<I", 0)
    for _, data in files:
        out += data
    return bytes(out + struct.pack("<I", 0))


class ReadGma(unittest.TestCase):
    def test_lists_files_with_their_contents_in_order(self):
        files = [("lua/a.lua", b"print(1)"), ("lua/entities/b/init.lua", b"")]
        gma = read_gma(gma_with(files))
        self.assertEqual([(f.path, f.data) for f in gma.files], files)
        self.assertEqual(gma.name, "name")

    def test_reads_version_one_without_required_content(self):
        gma = read_gma(gma_with([("x.lua", b"y")], version=1))
        self.assertEqual(gma.files[0].data, b"y")

    def test_rejects_other_files(self):
        with self.assertRaises(GmaError):
            read_gma(b"PK\x03\x04" + bytes(64))

    def test_rejects_a_truncated_file(self):
        with self.assertRaises(GmaError):
            read_gma(gma_with([("x.lua", b"0123456789")])[:-8])


class WriteGma(unittest.TestCase):
    def test_what_it_writes_reads_back_the_same(self):
        gma = Gma("voices", (GmaFile("sound/vo/a.wav", b"RIFF a"), GmaFile("sound/vo/b.wav", b"")))
        self.assertEqual(read_gma(write_gma(gma)), gma)

    def test_it_writes_gmad_version_three(self):
        blob = write_gma(Gma("x", ()))
        self.assertEqual(blob[:5], b"GMAD\x03")


if __name__ == "__main__":
    unittest.main()
