import dataclasses
import fcntl
import os
import struct
import tempfile
import termios
import socket
import threading
import unittest
from pathlib import Path

import srcds
from server_root import Instance
from srcds import (
    ARTIFACTS,
    DEFAULT_PORT,
    InstanceFiles,
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
    encode_packet,
    map_from_status,
    BOTTLE,
    Launched,
    WrongBottle,
    CONSOLE_COLUMNS,
    ITERM_PROFILE,
    applescript_string,
    console_pty,
    console_command,
    iterm_script,
    new_server,
    stop_targets,
)

INSTALL = Install(
    wine=Path("/Apps/wine"),
    bottle="GModServer",
    gmod_windows=r"C:\Steam\steamapps\common\GarrysMod",
    gmod_dir=Path("/bottle/GarrysMod/garrysmod"),
)


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.config = ServerConfig(map="koth_viaduct", port=27025, rcon_password="pw", maxplayers=24)
        self.argv = command_line(INSTALL, self.config)

    def test_runs_the_dedicated_server_through_the_bottles_wine(self):
        self.assertEqual(self.argv[:3], ["/Apps/wine", "--bottle", "GModServer"])
        exe = self.argv[self.argv.index("--cx-app") + 1]
        self.assertEqual(exe, r"C:\Steam\steamapps\common\GarrysMod\srcds_win64.exe")
        self.assertEqual(self.argv[self.argv.index("--workdir") + 1], INSTALL.gmod_windows)

    def test_wine_options_come_before_the_program(self):
        self.assertLess(self.argv.index("--workdir"), self.argv.index("--cx-app"))
        self.assertLess(self.argv.index("--no-gui"), self.argv.index("--cx-app"))

    def test_runs_secure_with_steam_and_the_workshop(self):
        for flag in ("-insecure", "-noworkshop", "-nosteam"):
            self.assertNotIn(flag, self.argv)

    def test_writes_no_console_log_and_runs_no_sourcetv(self):
        # the supervisor's pty log (srcds.log) is the console's record
        self.assertNotIn("-condebug", self.argv)
        self.assertIn("-nohltv", self.argv)

    def test_logs_on_with_the_game_server_token_when_it_has_one(self):
        self.assertNotIn("+sv_setsteamaccount", self.argv)
        argv = command_line(INSTALL, dataclasses.replace(self.config, steam_account="ABC123"))
        self.assertEqual(argv[argv.index("+sv_setsteamaccount") + 1], "ABC123")

    def test_only_the_main_instance_takes_the_token(self):
        # a token logs on one server at a time: a second would knock the first off Steam
        with tempfile.TemporaryDirectory() as tmp:
            token = Path(tmp) / "steam_account_token"
            self.assertEqual(srcds.steam_account(Instance(1), token), "")
            token.write_text("ABC123\n")
            self.assertEqual(srcds.steam_account(Instance(1), token), "ABC123")
            self.assertEqual(srcds.steam_account(Instance(2), token), "")

    def test_keeps_thinking_while_empty(self):
        self.assertEqual(self._convar("sv_hibernate_think"), "1")

    def test_sets_the_server_up_as_configured(self):
        self.assertEqual(self.argv[self.argv.index("-port") + 1], "27025")
        self.assertEqual(self._convar("maxplayers"), "24")
        self.assertEqual(self._convar("gamemode"), "sandcastle")
        self.assertEqual(self._convar("rcon_password"), "pw")
        # an internet server, which Steam authenticates and VAC secures; sv_lan 1 is never secure
        self.assertEqual(self._convar("sv_lan"), "0")

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

    def test_no_lua_refresh_adds_disableluarefresh(self):
        # T1 starts the server so that edits on disk after start-up never
        # reach it; by default Lua refresh stays on.
        self.assertNotIn("-disableluarefresh", self.argv)
        config = dataclasses.replace(self.config, lua_refresh=False)
        argv = command_line(INSTALL, config)
        self.assertIn("-disableluarefresh", argv[argv.index("--cx-app"):argv.index("+ip")])
        self.assertEqual(argv[:3], ["/Apps/wine", "--bottle", "GModServer"])

    # Steam friends join a -p2p server through Steam's relays.
    def test_p2p_adds_p2p(self):
        self.assertNotIn("-p2p", self.argv)
        argv = command_line(INSTALL, dataclasses.replace(self.config, p2p=True))
        self.assertIn("-p2p", argv[argv.index("--cx-app"):argv.index("+ip")])
        self.assertEqual(argv[argv.index("+sv_lan") + 1], "0")

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


PS = "\n".join([
    "    1     0 /sbin/launchd",
    "  500     1 python3 srcds.py _supervise log 27025 -- /Apps/wine --cx-app C:\\GarrysMod\\srcds_win64.exe -port 27025",
    "  501   500 /Apps/winewrapper.exe --workdir C:\\GarrysMod --run -- C:\\GarrysMod\\srcds_win64.exe -port 27025",
    "  502   501 C:\\GarrysMod\\srcds_win64.exe -console -game garrysmod -port 27025",
    "  503   501 /Apps/CrossOver/bin/wineserver",
    "  504   501 C:\\windows\\system32\\winedevice.exe",
    "  505   501 C:\\windows\\system32\\services.exe",
    "  600     1 C:\\GarrysMod\\srcds_win64.exe -console -game garrysmod -port 27025",
    "  700     1 C:\\Steam\\steamapps\\common\\Team Fortress 2\\tf_win64.exe -steam",
    "  800     1 /Apps/CrossOver/bin/wineserver",
])
LAUNCHED = Launched(supervisor=500, launcher=501, port=27025)


class StopTargets(unittest.TestCase):
    def test_only_the_processes_it_launched(self):
        self.assertEqual(stop_targets(LAUNCHED, PS), [500, 501, 502])

    def test_never_a_wineserver_or_wine_service_even_one_it_started(self):
        targets = stop_targets(LAUNCHED, PS)
        for pid in (503, 504, 505, 800):
            self.assertNotIn(pid, targets)

    def test_never_another_server_on_the_same_port_nor_the_operators_game(self):
        targets = stop_targets(LAUNCHED, PS)
        self.assertNotIn(600, targets)
        self.assertNotIn(700, targets)

    def test_nothing_once_its_processes_are_gone(self):
        self.assertEqual(stop_targets(LAUNCHED, "    1     0 /sbin/launchd"), [])

    def test_a_reused_pid_running_something_else_is_left_alone(self):
        ps = "  500     1 /usr/bin/vim\n  501   500 /bin/zsh"
        self.assertEqual(stop_targets(LAUNCHED, ps), [])


class WineReparentsTheServer(unittest.TestCase):
    # Under CrossOver the Windows process is not the launcher's child: its
    # parent is 1. It is found once, as the one server on our port that
    # was not running before the launch, and stopped by that id only.
    BEFORE = {1, 600, 700, 800}  # the launch made 500 to 505
    PS = PS + "\n  900     1 C:\\GarrysMod\\srcds_win64.exe -console -game garrysmod -port 27025"

    def test_the_new_server_on_our_port(self):
        # The supervisor, the launcher and its child name the server in
        # their command lines too; they are ours already, not the server.
        self.assertEqual(new_server(LAUNCHED, self.BEFORE | {502}, self.PS), 900)

    def test_not_one_that_ran_before_nor_one_on_another_port(self):
        self.assertIsNone(new_server(LAUNCHED, self.BEFORE | {502, 900}, self.PS))
        self.assertIsNone(new_server(dataclasses.replace(LAUNCHED, port=27015), self.BEFORE | {502}, self.PS))

    def test_stop_targets_the_adopted_server(self):
        launched = dataclasses.replace(LAUNCHED, server=900)
        self.assertEqual(stop_targets(launched, self.PS), [500, 501, 502, 900])

    def test_an_adopted_id_now_running_something_else_is_left_alone(self):
        launched = dataclasses.replace(LAUNCHED, server=700)
        self.assertNotIn(700, stop_targets(launched, PS))


class LaunchedRecord(unittest.TestCase):
    def test_round_trips_through_its_file_text(self):
        self.assertEqual(Launched.parse(LAUNCHED.text()), LAUNCHED)
        adopted = dataclasses.replace(LAUNCHED, server=900)
        self.assertEqual(Launched.parse(adopted.text()), adopted)

    def test_alive_while_any_launched_process_runs(self):
        self.assertTrue(LAUNCHED.alive(PS))
        self.assertFalse(LAUNCHED.alive("    1     0 /sbin/launchd"))


class Instances(unittest.TestCase):
    def test_the_main_instance_keeps_its_files_and_port(self):
        files = InstanceFiles.of(Instance(1))
        self.assertEqual((files.pid, files.log, files.port),
                         (ARTIFACTS / "srcds.pid", ARTIFACTS / "srcds.log", DEFAULT_PORT))

    def test_another_instance_has_its_own_files_and_port(self):
        files = InstanceFiles.of(Instance(2))
        self.assertEqual((files.pid, files.log, files.port),
                         (ARTIFACTS / "srcds-2.pid", ARTIFACTS / "srcds-2.log", DEFAULT_PORT + 10))

    def test_an_install_runs_from_its_instances_root(self):
        second = Instance(2)
        install = Install.on(Path("/Apps/wine"), second)
        self.assertEqual(install.gmod_windows, second.root_windows)
        self.assertEqual(install.gmod_dir, second.root / "garrysmod")


class Bottle(unittest.TestCase):
    def test_only_the_server_bottle(self):
        self.assertEqual(BOTTLE, "GModServer")

    def test_a_server_in_any_other_bottle_is_refused(self):
        play = Install(Path("/Apps/wine"), "Steam", INSTALL.gmod_windows, INSTALL.gmod_dir)
        with self.assertRaises(WrongBottle):
            command_line(play, ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=24))

    def test_the_launcher_does_not_update_the_bottle(self):
        argv = command_line(INSTALL, ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=24))
        self.assertIn("--no-update", argv[:argv.index("--cx-app")])


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


class BindAddress(unittest.TestCase):
    def test_binds_127_0_0_1_by_default(self):
        argv = command_line(INSTALL, ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=8))
        self.assertEqual(argv[argv.index("+ip") + 1], "127.0.0.1")

    def test_binds_the_address_given_for_a_client_in_the_other_bottle(self):
        config = ServerConfig(map="gm_construct", port=27025, rcon_password="pw", maxplayers=8, ip="100.64.0.1")
        argv = command_line(INSTALL, config)
        self.assertEqual(argv[argv.index("+ip") + 1], "100.64.0.1")

    def test_the_launch_record_keeps_the_address_for_rcon_and_stop(self):
        launched = Launched(supervisor=1, launcher=2, port=27025, host="100.64.0.1")
        self.assertEqual(Launched.parse(launched.text()).host, "100.64.0.1")

    def test_a_record_from_before_the_address_was_kept_means_127_0_0_1(self):
        self.assertEqual(Launched.parse('{"supervisor": 1, "launcher": 2, "port": 27025}').host, "127.0.0.1")

    # The operator plays from other machines on the tailnet, and the server
    # logs on to Steam: bound to the tailnet address alone, its Steam
    # sockets are too, and Steam is unreachable from there. start binds every
    # interface by default, the tailnet's among them.
    def test_start_binds_every_interface_by_default(self):
        self.assertEqual(srcds.DEFAULT_BIND_HOST, "0.0.0.0")

    def test_a_server_bound_to_every_interface_is_reached_on_this_mac(self):
        self.assertEqual(srcds.reach_address("0.0.0.0"), "127.0.0.1")

    def test_a_server_bound_to_one_address_is_reached_there(self):
        self.assertEqual(srcds.reach_address("100.64.0.1"), "100.64.0.1")

    def test_a_name_is_bound_by_its_address(self):
        self.assertEqual(srcds.bind_address("cosmicbook.tail", lambda name: "100.126.111.105"), "100.126.111.105")

    def test_an_address_is_bound_as_it_is(self):
        def never(name):
            raise AssertionError("an address needs no lookup")
        self.assertEqual(srcds.bind_address("100.64.0.1", never), "100.64.0.1")

    def test_a_name_that_does_not_resolve_is_refused_with_why(self):
        def unknown(name):
            raise socket.gaierror(8, "nodename nor servname provided")
        with self.assertRaises(srcds.BindAddressUnknown) as caught:
            srcds.bind_address("cosmicbook.tail", unknown)
        self.assertIn("cosmicbook.tail", str(caught.exception))
        self.assertIn("--ip", str(caught.exception))


class ConsoleWindow(unittest.TestCase):
    def test_the_console_follows_the_log_from_its_start_across_restarts(self):
        self.assertEqual(console_command(Path("/repo/srcds.log")), "tail -n +1 -F /repo/srcds.log")

    def test_a_log_path_with_spaces_and_quotes_is_one_shell_word(self):
        self.assertEqual(console_command(Path("/my repo/it's.log")), "tail -n +1 -F '/my repo/it'\"'\"'s.log'")

    def test_an_applescript_string_escapes_backslashes_and_quotes(self):
        self.assertEqual(applescript_string('a "b" \\ c'), '"a \\"b\\" \\\\ c"')

    def test_iterm_opens_a_window_in_the_dark_profile_running_the_command(self):
        self.assertEqual(ITERM_PROFILE, "Dark")
        script = iterm_script("tail -F '/x y'")
        self.assertIn('create window with profile "Dark" command "tail -F \'/x y\'"', script)
        self.assertIn('tell application "iTerm"', script)

    def test_the_consoles_pty_is_wide_so_wine_does_not_wrap_at_80_columns(self):
        master, slave = console_pty()
        try:
            rows, columns, _, _ = struct.unpack("HHHH", fcntl.ioctl(slave, termios.TIOCGWINSZ, bytes(8)))
            self.assertEqual(columns, CONSOLE_COLUMNS)
            self.assertGreater(columns, 80)
            self.assertGreater(rows, 0)
        finally:
            os.close(master)
            os.close(slave)

