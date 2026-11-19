"""holylib.py: HolyLib's pinned release fetched for the Linux server, each file held to its hash.
Nothing here reaches the network: downloads are a fake."""
import hashlib

import pytest

import holylib
from holylib import FILES, RELEASE, Mismatch, fetch, status


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Release:
    """A fake of the release's downloads: the pinned files' bytes, by URL, each asked counted."""

    def __init__(self, files):
        self.files, self.asked = files, []

    def get(self, url):
        self.asked.append(url)
        return self.files[url.rsplit("/", 1)[1]]


@pytest.fixture
def pinned(monkeypatch):
    data = {name: f"{name} bytes".encode() for name in FILES}
    monkeypatch.setattr(holylib, "FILES", {name: digest(body) for name, body in data.items()})
    return Release(data)


def test_fetch_downloads_each_file_of_the_pinned_release_into_the_folder(tmp_path, pinned):
    placed = fetch(tmp_path, pinned.get)
    for name, path in placed.items():
        assert path == tmp_path / name
        assert path.read_bytes() == pinned.files[name]
    assert all(f"/download/{RELEASE}/" in url for url in pinned.asked)


def test_a_file_already_fetched_is_not_downloaded_again(tmp_path, pinned):
    fetch(tmp_path, pinned.get)
    pinned.asked.clear()
    fetch(tmp_path, pinned.get)
    assert pinned.asked == []


def test_a_file_changed_on_disk_is_downloaded_again(tmp_path, pinned):
    placed = fetch(tmp_path, pinned.get)
    name = next(iter(placed))
    placed[name].write_bytes(b"tampered")
    assert status(tmp_path)[name] == "mismatch"
    pinned.asked.clear()
    fetch(tmp_path, pinned.get)
    assert len(pinned.asked) == 1 and placed[name].read_bytes() == pinned.files[name]


def test_a_download_that_is_not_the_pinned_file_is_refused_and_never_written(tmp_path, pinned):
    name = next(iter(pinned.files))
    pinned.files[name] = b"another build"
    with pytest.raises(Mismatch, match=name):
        fetch(tmp_path, pinned.get)
    assert not (tmp_path / name).exists()
    assert not list(tmp_path.glob("*.partial"))


def test_status_says_what_is_missing_until_fetched(tmp_path, pinned):
    assert set(status(tmp_path).values()) == {"missing"}
    fetch(tmp_path, pinned.get)
    assert set(status(tmp_path).values()) == {"ok"}


def test_the_release_is_the_64_bit_plugin_and_the_vdf_that_loads_it():
    assert set(FILES) == {"holylib_linux_64.vdf", "gmsv_holylib_linux64.so"}
    assert all(len(pin) == 64 for pin in FILES.values())


def test_the_server_starts_with_every_module_off_but_vprof():
    args = holylib.SERVER_ARGS
    assert "-holylib_startdisabled" in args
    assert args[args.index("-holylib_enable_vprof") + 1] == "1"
