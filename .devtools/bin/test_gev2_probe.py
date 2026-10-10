"""gev2_probe.py's client mode, against a fake server whose fake client
answers the loader by writing its result into the shared data folder."""
import re
from dataclasses import dataclass
from pathlib import Path

import pytest

from gev2_probe import ProbeFailed, client_loader, run_on_clients

JOINED = """map     : koth_viaduct at: 0 x, 0 y, 0 z
# userid name                uniqueid            connected ping loss state  adr
#      2 "moon"              STEAM_0:1:1234      00:12       50    0 active loopback
"""
EMPTY = """map     : koth_viaduct at: 0 x, 0 y, 0 z
# userid name                uniqueid            connected ping loss state  adr
#      3 "Bot01"             BOT                                     active
"""


@dataclass(frozen=True)
class FakeInstall:
    data_dir: Path


class FakeServer:
    def __init__(self, data_dir, status=JOINED, answers=True):
        self.install = FakeInstall(data_dir)
        self.status = status
        self.answers = answers
        self.commands = []

    def rcon(self, text, timeout=10):
        self.commands.append(text)
        if text == "status":
            return self.status
        m = re.search(r'RunString\(file\.Read\("ws_tests/gev2/(\w+)\.txt", "DATA"\)', text)
        if m and self.answers:
            out = self.install.data_dir / "ws_tests" / "gev2" / "client_out" / f"{m.group(1)}.txt"
            out.write_text(f"realm | client\nran {m.group(1)}\n")
        return ""


@pytest.fixture
def probes(tmp_path):
    folder = tmp_path / "probes"
    folder.mkdir()
    (folder / "client_t4.lua").write_text("-- a probe\n")
    return folder


def run(server, tmp_path, probes, **kw):
    return run_on_clients(server, "client_t4", probes=probes, dest=tmp_path / "client", **kw)


def test_client_mode_sends_the_loader_to_every_human_player(tmp_path, probes):
    server = FakeServer(tmp_path / "data")
    run(server, tmp_path, probes)
    loaders = [c for c in server.commands if c.startswith("lua_run")]
    assert loaders == [client_loader("client_t4")]
    assert "player.GetHumans()" in loaders[0] and ":SendLua(" in loaders[0]
    assert ";" not in loaders[0]  # the console would split the line there
    sent = re.search(r"SendLua\(\[\[(.*)\]\]\)", loaders[0]).group(1)
    assert len(sent.encode()) < 255  # SendLua's limit
    assert (tmp_path / "data" / "ws_tests" / "gev2" / "client_t4.txt").read_text() == "-- a probe\n"


def test_client_mode_copies_the_clients_result_to_the_client_artifacts(tmp_path, probes):
    text = run(FakeServer(tmp_path / "data"), tmp_path, probes)
    assert text == "realm | client\nran client_t4\n"
    assert (tmp_path / "client" / "client_t4.txt").read_text() == text


def test_client_mode_refuses_without_a_joined_client(tmp_path, probes):
    server = FakeServer(tmp_path / "data", status=EMPTY)
    with pytest.raises(ProbeFailed, match="no client"):
        run(server, tmp_path, probes)
    assert not [c for c in server.commands if c.startswith("lua_run")]


def test_client_mode_never_returns_an_old_result(tmp_path, probes):
    old = tmp_path / "data" / "ws_tests" / "gev2" / "client_out" / "client_t4.txt"
    old.parent.mkdir(parents=True)
    old.write_text("an earlier run\n")
    with pytest.raises(ProbeFailed):
        run(FakeServer(tmp_path / "data", answers=False), tmp_path, probes, timeout=1)


def test_a_label_keeps_each_steps_result_apart(tmp_path, probes):
    run(FakeServer(tmp_path / "data"), tmp_path, probes, label="after-refresh")
    assert (tmp_path / "client" / "client_t4-after-refresh.txt").exists()
