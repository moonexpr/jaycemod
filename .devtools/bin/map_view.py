#!/usr/bin/env python3
"""Render a view of a .vmf to a PNG, through hammer-mcp's render_vmf_view.

Flat colour per material, one light, no textures and no props: the shape of
a place (what stands where, what hides what), from a camera given as Source
does (x forward, y left, z up). The picture goes to
.devtools/artifacts/views/<name>.png, and the tool's JSON (what was drawn,
how much sky or void the camera sees) is printed.

    python3 .devtools/bin/map_view.py MAP.vmf --origin X Y Z --look-at X Y Z [--name NAME]
        [--fov 90] [--size 800 560] [--stand]
"""
import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HAMMER = Path.home() / "Repositories" / "hammer-mcp"
VIEWS = REPO / ".devtools" / "artifacts" / "views"


def render(args: dict) -> tuple:
    """The tool's JSON and the picture's bytes."""
    done = subprocess.run(["node", str(HAMMER / ".devtools/bin/mcp-call.mjs"), "render_vmf_view", json.dumps(args)],
                          cwd=HAMMER, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"render_vmf_view failed:\n{done.stdout[-2000:]}{done.stderr[-2000:]}")
    report, png = None, None
    for line in done.stdout.splitlines():
        if line.startswith('{"type":"image"'):
            png = base64.b64decode(json.loads(line)["data"])
    body = done.stdout.split("=== render_vmf_view", 1)[1]
    report = json.loads(body[body.index("{"):body.index("\n}") + 2])
    if png is None:
        sys.exit("render_vmf_view returned no picture:\n" + json.dumps(report, indent=1))
    return report, png


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("vmf", type=Path)
    parser.add_argument("--origin", type=float, nargs=3, required=True)
    parser.add_argument("--look-at", type=float, nargs=3, required=True)
    parser.add_argument("--name", help="the picture's name (default: the map's and the origin's)")
    parser.add_argument("--fov", type=float, default=90)
    parser.add_argument("--size", type=int, nargs=2, default=(800, 560))
    parser.add_argument("--stand", action="store_true", help="the eye where a player standing under origin has it")
    args = parser.parse_args()
    report, png = render({"path": str(args.vmf.resolve()), "origin": args.origin, "lookAt": args.look_at,
                          "fov": args.fov, "width": args.size[0], "height": args.size[1], "stand": args.stand})
    VIEWS.mkdir(parents=True, exist_ok=True)
    name = args.name or f"{args.vmf.stem}_{'_'.join(str(round(v)) for v in args.origin)}"
    path = VIEWS / f"{name}.png"
    path.write_bytes(png)
    print(json.dumps({k: report[k] for k in ("origin", "angles", "facesDrawn", "skyFraction", "voidFraction", "insideSolid")}))
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
