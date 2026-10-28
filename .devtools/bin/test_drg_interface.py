import struct
import unittest

from drg_interface import Names, Usage, declared, read_gma


def gma(files: dict[str, str]) -> bytes:
    out = bytearray(b"GMAD" + bytes([3]) + bytes(8) + bytes(8) + b"\0")
    out += b"name\0desc\0author\0" + struct.pack("<i", 1)
    for number, (path, text) in enumerate(files.items(), start=1):
        out += struct.pack("<I", number) + path.encode() + b"\0"
        out += struct.pack("<q", len(text.encode())) + struct.pack("<I", 0)
    out += struct.pack("<I", 0)
    for text in files.values():
        out += text.encode()
    return bytes(out + struct.pack("<I", 0))


class ReadGma(unittest.TestCase):
    def test_each_file_and_its_text(self):
        files = {"lua/a.lua": "x = 1", "lua/b/c.lua": "y = 2"}
        self.assertEqual(read_gma(gma(files)), files)

    def test_not_an_addon_is_refused(self):
        with self.assertRaises(ValueError):
            read_gma(b"NOPE")


class DrgNames(unittest.TestCase):
    TEXT = """
function ENT:GetEnemy() return self._enemy end
function ENT:OnNewEnemy() end
ENT.RunSpeed = 200
ENT.ClimbLedges = false
local function helper() end
function DrGBase.GetNextbots() end
-- function ENT:Commented() end
"""

    def test_methods_and_fields_of_the_nextbot(self):
        names = Names.of_drgbase(self.TEXT)
        self.assertEqual(names.methods, {"GetEnemy", "OnNewEnemy"})
        self.assertEqual(names.fields, {"RunSpeed", "ClimbLedges"})

    def test_what_it_adds_to_gmods_metatables_but_not_its_own_classes(self):
        text = """
function entMETA:DrG_TraceHull(data) end
function plyMETA:DrG_JoinFaction(f) end
function vecMETA:DrG_Away(v) end
function Node:GetPos() end
"""
        self.assertEqual(Names.of_drgbase(text).methods, {"DrG_TraceHull", "DrG_JoinFaction", "DrG_Away"})


class OurUsage(unittest.TestCase):
    TEXT = """
function ENT:OnNewEnemy(enemy) self:FollowPath(enemy:GetPos()) end
ENT.RunSpeed = 250
local e = soldier:GetEnemy()
if bot.ClimbLedges then end
-- soldier:Commented()
"""

    def test_what_we_call_define_and_set(self):
        usage = Usage.of(self.TEXT)
        self.assertEqual(usage.defined, {"OnNewEnemy"})
        self.assertEqual(usage.set, {"RunSpeed"})
        self.assertTrue({"FollowPath", "GetEnemy", "GetPos"} <= usage.called)
        self.assertIn("ClimbLedges", usage.read)
        self.assertNotIn("Commented", usage.called)


class Declared(unittest.TestCase):
    def test_quoted_names_and_replaced_keys(self):
        text = 'METHODS = { "GetEnemy", "FollowPath" }\nREPLACED = {\n\t_Handle = "the base\'s own",\n}\n-- "Commented"'
        self.assertEqual(declared(text), {"GetEnemy", "FollowPath", "_Handle"})


if __name__ == "__main__":
    unittest.main()
