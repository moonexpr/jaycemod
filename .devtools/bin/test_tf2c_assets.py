"""tf2c_assets.py copies the few files Sandcastle takes from TF2 Classified
(its VIP HUD's materials, for the hostage HUD) out of its paks into the
addon, each at its own path; a file the paks lack is refused, naming it."""
from pathlib import Path

import pytest

import tf2c_assets


class FakePak:
    def __init__(self, files):
        self.files = files

    def names(self):
        return list(self.files)

    def read(self, path):
        return self.files[path]


def test_each_file_is_copied_to_its_own_path_from_whichever_pak_has_it(tmp_path: Path):
    paks = [FakePak({"materials/hud/a.vmt": b"A"}), FakePak({"materials/hud/b.vtf": b"B"})]
    written = tf2c_assets.extract(paks, ["materials/hud/a.vmt", "materials/hud/b.vtf"], tmp_path)
    assert (tmp_path / "materials/hud/a.vmt").read_bytes() == b"A"
    assert (tmp_path / "materials/hud/b.vtf").read_bytes() == b"B"
    assert written == [tmp_path / "materials/hud/a.vmt", tmp_path / "materials/hud/b.vtf"]


def test_a_file_no_pak_has_is_refused(tmp_path: Path):
    with pytest.raises(tf2c_assets.MissingAsset, match="materials/hud/none.vmt"):
        tf2c_assets.extract([FakePak({})], ["materials/hud/none.vmt"], tmp_path)


def test_the_assets_are_the_vip_huds_materials_each_with_its_texture():
    stems = {Path(p).stem for p in tf2c_assets.ASSETS}
    assert {"vip_track", "vip_home", "vip_car", "vip_civ", "vip_civ_bottom"} <= stems
    for stem in stems:
        assert f"materials/hud/{stem}.vmt" in tf2c_assets.ASSETS
        assert f"materials/hud/{stem}.vtf" in tf2c_assets.ASSETS
