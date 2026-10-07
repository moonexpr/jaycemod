import shutil
import struct
import tempfile
import unittest
from pathlib import Path

from tf2_server_content import (
    INCLUDE_COUNT_OFFSET,
    MODEL_SUFFIXES,
    include_models,
    model_names_in_entities,
    write_content,
)


def mdl_with_includes(names):
    """A studiohdr_t stub: the include count and index at their offsets,
    then mstudiomodelgroup_t {label, name} offsets, then the strings."""
    header = bytearray(INCLUDE_COUNT_OFFSET + 8)
    groups_at = len(header)
    struct.pack_into("<ii", header, INCLUDE_COUNT_OFFSET, len(names), groups_at)
    groups = bytearray(8 * len(names))
    strings = bytearray()
    strings_at = groups_at + len(groups)
    for i, name in enumerate(names):
        entry_at = groups_at + 8 * i
        struct.pack_into("<ii", groups, 8 * i, 0, strings_at + len(strings) - entry_at)
        strings += name.encode() + b"\0"
    return bytes(header + groups + strings)


class Includes(unittest.TestCase):
    def test_reads_each_included_model(self):
        mdl = mdl_with_includes(["models/player/sniper_animations.mdl", "models/bots/x.mdl"])
        self.assertEqual(include_models(mdl), ["models/player/sniper_animations.mdl", "models/bots/x.mdl"])

    def test_none(self):
        self.assertEqual(include_models(mdl_with_includes([])), [])

    def test_a_header_too_short_has_none(self):
        self.assertEqual(include_models(b"IDST"), [])


class EntityModels(unittest.TestCase):
    def test_model_keys_that_name_studio_models(self):
        entities = [
            {"classname": "prop_dynamic", "model": "models/props_trainyard/bomb_cart.mdl"},
            {"classname": "func_tracktrain", "model": "*12"},
            {"classname": "tf_zombie_spawner"},
            {"classname": "prop_physics", "model": "Models/Props_Halloween/Pumpkin_01.MDL"},
        ]
        self.assertEqual(model_names_in_entities(entities),
                         {"models/props_trainyard/bomb_cart.mdl", "models/props_halloween/pumpkin_01.mdl"})


class FakeVpk:
    def __init__(self, files):
        self.files = files

    def __contains__(self, name):
        return name in self.files

    def read(self, name):
        return self.files[name]


class Write(unittest.TestCase):
    def setUp(self):
        self.out = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.out)

    def test_writes_a_model_its_siblings_and_its_includes(self):
        vpk = FakeVpk({
            "models/bots/skel.mdl": mdl_with_includes(["models/bots/skel_anims.mdl"]),
            "models/bots/skel.phy": b"phy",
            "models/bots/skel.vvd": b"vvd",
            "models/bots/skel_anims.mdl": mdl_with_includes([]),
            "models/bots/skel_anims.ani": b"ani",
        })
        written, missing = write_content(vpk, {"models/bots/skel.mdl", "models/gone.mdl"}, self.out)
        names = sorted(str(p.relative_to(self.out)) for p in self.out.rglob("*") if p.is_file())
        self.assertEqual(names, ["models/bots/skel.mdl", "models/bots/skel.phy", "models/bots/skel.vvd",
                                 "models/bots/skel_anims.ani", "models/bots/skel_anims.mdl"])
        self.assertEqual(written, 5)
        self.assertEqual(missing, ["models/gone.mdl"])

    def test_only_server_side_files(self):
        self.assertEqual(set(MODEL_SUFFIXES), {".mdl", ".phy", ".ani", ".vvd"})


if __name__ == "__main__":
    unittest.main()
