import shutil
import socket
import tempfile
import threading
import unittest
from pathlib import Path

from srcds import (
    AUTH,
    AUTH_RESPONSE,
    EXECCOMMAND,
    RESPONSE_VALUE,
    AuthFailed,
    Install,
    Packet,
    RconClient,
    ServerConfig,
    command_line,
    decode_packets,
    link_maps,
    encode_packet,
    map_from_status,
    server_pids,
    unlink_maps,
)

INSTALL = Install(
    wine=Path("/Apps/wine"),
    bottle="Team Fortress 2",
    gmod_windows=r"C:\Steam\steamapps\common\GarrysMod",
    gmod_dir=Path("/bottle/GarrysMod/garrysmod"),
)


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.config = ServerConfig(map="koth_viaduct", port=27025, rcon_password="pw", maxplayers=24)
        self.argv = command_line(INSTALL, self.config)

    def test_runs_the_dedicated_server_through_the_bottles_wine(self):
        self.assertEqual(self.argv[:3], ["/Apps/wine", "--bottle", "Team Fortress 2"])
        exe = self.argv[self.argv.index("--cx-app") + 1]
        self.assertEqual(exe, r"C:\Steam\steamapps\common\GarrysMod\srcds_win64.exe")
        self.assertEqual(self.argv[self.argv.index("--workdir") + 1], INSTALL.gmod_windows)

    def test_wine_options_come_before_the_program(self):
        self.assertLess(self.argv.index("--workdir"), self.argv.index("--cx-app"))
        self.assertLess(self.argv.index("--no-gui"), self.argv.index("--cx-app"))

    def test_avoids_the_steam_workshop_crash(self):
        # srcds_win64 under CrossOver dies in steamclient64 while it mounts the
        # Workshop unless the server is insecure and skips the Workshop.
        for flag in ("-insecure", "-noworkshop", "-nosteam"):
            self.assertIn(flag, self.argv)

    def test_logs_the_console_and_keeps_thinking_while_empty(self):
        self.assertIn("-condebug", self.argv)
        self.assertEqual(self._convar("sv_hibernate_think"), "1")

    def test_sets_the_server_up_as_configured(self):
        self.assertEqual(self.argv[self.argv.index("-port") + 1], "27025")
        self.assertEqual(self._convar("maxplayers"), "24")
        self.assertEqual(self._convar("gamemode"), "sandcastle")
        self.assertEqual(self._convar("rcon_password"), "pw")
        self.assertEqual(self._convar("sv_lan"), "1")

    def test_listens_only_on_this_machine(self):
        # Without +ip the RCON socket binds the first interface's address
        # (a VPN's, here), not 127.0.0.1.
        self.assertEqual(self._convar("ip"), "127.0.0.1")

    def test_the_map_comes_last_so_every_setting_is_in_place_when_it_loads(self):
        self.assertEqual(self.argv[-2:], ["+map", "koth_viaduct"])

    def test_extra_convars_are_set_before_the_map(self):
        config = ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=24,
                              convars=(("sv_gameplay_enabled", "0"),))
        argv = command_line(INSTALL, config)
        self.assertLess(argv.index("+sv_gameplay_enabled"), argv.index("+map"))
        self.assertEqual(argv[argv.index("+sv_gameplay_enabled") + 1], "0")

    def _convar(self, name):
        return self.argv[self.argv.index("+" + name) + 1]


class ServerConfigRefuses(unittest.TestCase):
    def test_a_password_with_a_space(self):
        with self.assertRaises(ValueError):
            ServerConfig(map="gm_construct", port=27025, rcon_password="a b", maxplayers=24)

    def test_an_empty_password(self):
        with self.assertRaises(ValueError):
            ServerConfig(map="gm_construct", port=27025, rcon_password="", maxplayers=24)

    def test_a_map_name_with_a_path(self):
        with self.assertRaises(ValueError):
            ServerConfig(map="../maps/x", port=27025, rcon_password="pw", maxplayers=24)

    def test_too_few_slots_for_bots(self):
        with self.assertRaises(ValueError):
            ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=1)


class Packets(unittest.TestCase):
    def test_encodes_size_id_type_body_and_two_nulls(self):
        data = encode_packet(Packet(7, AUTH, "pw"))
        self.assertEqual(data, (12).to_bytes(4, "little") + (7).to_bytes(4, "little")
                         + (3).to_bytes(4, "little") + b"pw\x00\x00")

    def test_round_trips(self):
        packets = [Packet(1, EXECCOMMAND, "status"), Packet(2, RESPONSE_VALUE, "")]
        decoded, rest = decode_packets(b"".join(encode_packet(p) for p in packets))
        self.assertEqual(decoded, packets)
        self.assertEqual(rest, b"")

    def test_keeps_a_partial_packet_for_later(self):
        data = encode_packet(Packet(1, RESPONSE_VALUE, "hello"))
        decoded, rest = decode_packets(data[:-3])
        self.assertEqual(decoded, [])
        self.assertEqual(rest, data[:-3])

    def test_a_negative_id_decodes_as_signed(self):
        decoded, _ = decode_packets(encode_packet(Packet(-1, AUTH_RESPONSE, "")))
        self.assertEqual(decoded[0].id, -1)

    def test_bodies_that_are_not_utf8_still_decode(self):
        raw = bytearray(encode_packet(Packet(1, RESPONSE_VALUE, "ab")))
        raw[12] = 0xFF
        decoded, _ = decode_packets(bytes(raw))
        self.assertEqual(len(decoded), 1)


class Status(unittest.TestCase):
    def test_reads_the_map(self):
        text = "hostname: My Garry's Mod Server\nversion : 2024.10.29/24 9536 secure\nmap     : koth_viaduct at: 0 x, 0 y, 0 z\n"
        self.assertEqual(map_from_status(text), "koth_viaduct")

    def test_no_map_line(self):
        self.assertIsNone(map_from_status("Unknown command"))


class ServerPids(unittest.TestCase):
    PS = "\n".join([
        " 100 /Apps/winewrapper.exe --workdir C:\\GarrysMod --run -- C:\\GarrysMod\\srcds_win64.exe -console -port 27025 -insecure",
        " 101 C:\\GarrysMod\\srcds_win64.exe -console -game garrysmod -port 27025 -insecure",
        " 102 C:\\GarrysMod\\srcds_win64.exe -console -game garrysmod -port 27015 -insecure",
        " 103 C:\\GarrysMod\\gmod_win64.exe -port 27025",
        " 104 C:\\GarrysMod\\srcds_win64.exe -console -port 270250",
    ])

    def test_only_the_servers_on_our_port(self):
        self.assertEqual(server_pids(27025, self.PS), [100, 101])

    def test_a_port_at_the_end_of_the_line(self):
        self.assertEqual(server_pids(270250, self.PS), [104])


class MapLinks(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.tf_maps = self.tmp / "tf" / "maps"
        self.tf_maps.mkdir(parents=True)
        for name in ("pl_badwater.bsp", "pl_badwater.nav", "koth_viaduct.bsp"):
            (self.tf_maps / name).write_text("x")
        self.addon = self.tmp / "garrysmod" / "addons" / "wetsand_test_maps"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_links_every_tf2_map_but_never_its_nav(self):
        # A TF2 .nav in an addon would shadow the converted one in garrysmod/maps.
        link_maps(self.tf_maps, self.addon)
        names = sorted(p.name for p in (self.addon / "maps").iterdir())
        self.assertEqual(names, ["koth_viaduct.bsp", "pl_badwater.bsp"])
        self.assertEqual((self.addon / "maps" / "pl_badwater.bsp").resolve(), (self.tf_maps / "pl_badwater.bsp").resolve())

    def test_linking_twice_is_harmless(self):
        link_maps(self.tf_maps, self.addon)
        link_maps(self.tf_maps, self.addon)
        self.assertEqual(len(list((self.addon / "maps").iterdir())), 2)

    def test_unlinking_removes_the_addon_and_leaves_tf2_alone(self):
        link_maps(self.tf_maps, self.addon)
        unlink_maps(self.addon)
        self.assertFalse(self.addon.exists())
        self.assertTrue((self.tf_maps / "pl_badwater.bsp").exists())

    def test_unlinking_refuses_a_folder_holding_real_files(self):
        (self.addon / "maps").mkdir(parents=True)
        (self.addon / "maps" / "mine.bsp").write_text("x")
        with self.assertRaises(ValueError):
            unlink_maps(self.addon)
        self.assertTrue((self.addon / "maps" / "mine.bsp").exists())


class FakeRconServer:
    """A Source RCON server on a local socket: it checks the password and
    answers each command with its text split over two packets, as srcds does
    for long output, then mirrors the empty terminator."""

    def __init__(self, password):
        self.password = password
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(1)
        self.port = self.sock.getsockname()[1]
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        conn, _ = self.sock.accept()
        self.sock.close()
        buf = b""
        with conn:
            while True:
                data = conn.recv(4096)
                if not data:
                    return
                packets, buf = decode_packets(buf + data)
                for p in packets:
                    conn.sendall(b"".join(encode_packet(r) for r in self.answer(p)))

    def answer(self, p):
        if p.type == AUTH:
            ok = p.body == self.password
            return [Packet(p.id, RESPONSE_VALUE, ""), Packet(p.id if ok else -1, AUTH_RESPONSE, "")]
        if p.type == EXECCOMMAND:
            return [Packet(p.id, RESPONSE_VALUE, "echo:"), Packet(p.id, RESPONSE_VALUE, p.body)]
        return [Packet(p.id, RESPONSE_VALUE, "")]


class Client(unittest.TestCase):
    def test_runs_a_command_and_joins_its_split_answer(self):
        server = FakeRconServer("pw")
        with RconClient.connect("127.0.0.1", server.port, "pw", timeout=2) as rcon:
            self.assertEqual(rcon.command("status"), "echo:status")

    def test_a_wrong_password_is_refused(self):
        server = FakeRconServer("pw")
        with self.assertRaises(AuthFailed):
            RconClient.connect("127.0.0.1", server.port, "nope", timeout=2)


if __name__ == "__main__":
    unittest.main()
