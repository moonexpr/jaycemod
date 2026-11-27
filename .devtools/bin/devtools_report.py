#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["reportlab>=4", "matplotlib>=3.8"]
# ///
# dt-brief: The .devtools audit as a PDF: what lives in bin, how it grew, devrag's use, and the discussion
"""The .devtools audit report (2026-11-13) as a PDF with charts.

  devtools_report.py                      write .devtools/artifacts/devtools-report-<date>.pdf
  devtools_report.py --out PATH           write it there

The folder's numbers are read live (the files, their imports, git's dates,
devrag's questions.jsonl); the weekly history, the harness's milestones and
the eval scores are the figures taken on 2026-11-13, held as constants so the
report stands as a record of that day.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from reportlab.lib import colors  # noqa: E402
from reportlab.lib.enums import TA_LEFT  # noqa: E402
from reportlab.lib.pagesizes import letter  # noqa: E402
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet  # noqa: E402
from reportlab.lib.units import inch  # noqa: E402
from reportlab.platypus import (  # noqa: E402
    Image,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / ".devtools" / "bin"
TODAY = "2026-11-13"

# The dataviz reference palette (light surface).
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
MAGENTA, GREEN, VIOLET, RED = "#e87ba4", "#008300", "#6250d6", "#e34948"
BLUE_300 = "#6da7ec"
NEUTRAL_FILL = "#d9d8d2"

# ---------------------------------------------------------------- the folder

CATEGORIES = {
    "Server plumbing": [
        "srcds.py", "server_root.py", "server_lua.py", "server_watch.py", "instances.py",
        "gmod_mcp.py", "gmod_client.py", "lua_watch.py", "add_map.py", "gmod_lua.py",
    ],
    "Live-server probes": [
        "bot_probe.lua", "bot_status.lua", "ctfbot_check.lua", "ctfbot_demo.lua", "hostage_status.lua",
        "hotswap_listing.lua", "lane_audit.lua", "nav_reach.lua", "navsearch_live_check.lua",
        "next_soldier_head_check.lua", "next_soldier_round_check.lua", "nextsoldier_engine_check.lua",
        "rooms_dump.lua", "squad_member_check.lua", "stuck_census.lua", "stuck_report.lua",
        "tactical_behavior_check.lua", "war_round_check.lua", "route_told_check.lua",
        "aiwar_fight_watch.py", "hostage_watch.py",
    ],
    "Benches and fixtures": [
        "aiwar_bench.py", "aiwar_ab_bench.py", "stranding_ab.py", "dustbowl_stage2_bench.py",
        "hostage_survey.py", "ns_bench_map.py", "ns_bench_run.py", "ns_fixture_map.py",
        "bench_foundation.lua", "native_bench.lua", "dev_3house_bench.lua", "dev_3house_trial.lua",
        "dev_3house_nav.lua", "dev_3house_map.py", "engineer_defense.lua", "aiwar_tick_probe.lua",
        "profile_server.lua", "record_routes.lua", "route_replay.lua", "capture_routes.lua",
        "capture_nav_section.lua",
    ],
    "Rooms and places": [
        "incursion.py", "places.py", "classes.py", "ambush.py", "rooms_view.py", "incursion_view.py",
        "classes_view.py", "assault_view.py", "places_diff.py", "map_view.py",
    ],
    "Source/TF2 content readers": [
        "vpk.py", "gma.py", "bsp_entities.py", "ice.py", "pe_rtti.py", "lua_glue.py", "tf2_content.py",
        "tf2_server_content.py", "tf2c_assets.py", "tf2_scene.py", "hud_res.py", "nav_convert.py",
        "gmod_lua_cache.py", "map_census.py",
    ],
    "Repo checks and hooks": [
        "check_lua.sh", "check_lua_gate.py", "check_names.py", "check_engine_names.sh",
        "check_no_markers.py", "check_totals.sh", "run_lua_tests.sh", "suites.lua", "lua_format.py",
        "drg_interface.py",
    ],
    "Refactor and history": [
        "foundation_rename.py", "foundation_globals.py", "retwin_comment.py", "strip_attribution.py",
        "publish_public.sh", "vendor_source_sdk.sh", "gev2_marker.py",
    ],
    "Art and assets": ["kill_icons_art.py", "gamemode_art.py", "teamtint_bake.py", "sound_pack.py"],
    "Game events v2 research": ["gev2_probe.py", "gev2_client_session.sh"],
    "In-game harness (2026-09)": ["ingame_tests.py", "ingame_one.py"],
}

FINISHED = [
    "foundation_rename.py", "foundation_globals.py", "retwin_comment.py", "gev2_marker.py",
    "check_no_markers.py", "gev2_probe.py", "gev2_client_session.sh", "tf2c_assets.py", "hud_res.py", "ice.py",
]

# Taken 2026-11-13 from git (the main branch at each Sunday's end).
GROWTH = [
    ("2026-09-28", 10, 4, 0, 4),
    ("2026-10-05", 17, 7, 0, 10),
    ("2026-10-12", 53, 24, 0, 17),
    ("2026-10-19", 62, 26, 4, 20),
    ("2026-10-26", 79, 27, 13, 26),
    ("2026-11-02", 120, 42, 18, 40),
    ("2026-11-09", 142, 45, 30, 41),
    ("2026-11-13", 147, 46, 32, 43),
]

MILESTONES = [
    ("2026-09-24", "layout rule: one place for everything (claude-config2)"),
    ("2026-09-27", "bin begins: bsp_entities, gmod_lua, a test each"),
    ("2026-09-30", "in-game harness: srcds.py + ingame_tests.py"),
    ("2026-10-09", "server_lua, Watch; server-lua and dedicated-server skills"),
    ("2026-10-10", "gmod MCP; the dt drawer"),
    ("2026-10-21", "devrag: rag-history searches the history"),
    ("2026-10-22", "dev workbench addon, scenarios; foundation_rename"),
    ("2026-10-27", "live-server rule"),
    ("2026-10-28", "instances.py: benches lease servers; rag eval cases"),
    ("2026-10-30", "suites.lua groups; check_lua_gate hook"),
    ("2026-11-10", "lua_format.py"),
    ("2026-11-12", "repo moves to jaycemod; foundation its own addon"),
]

# dt rag/history eval, run 2026-11-13 over .devtools/rag/eval.jsonl (54 cases; top5: an expected
# source among the five read per question).
EVAL: dict | None = {
    "rows": [
        ("keyword (BM25)", "top5 3 of 54", "exact 0/8, paraphrase 1/25, implicit 1/16, user 1/3"),
        ("meaning (embeddings)", "top5 4 of 54", "exact 0/8, paraphrase 2/25, implicit 1/16, user 1/3"),
        ("fused (what search runs)", "top5 4 of 54", "exact 0/8, paraphrase 2/25, implicit 1/16, user 1/3"),
        ("the same tool, Oct 20", "top5 23 of 25 paraphrases", "the figure recorded in the tool's own header"),
    ],
    "note": "The scores are not a measure of the search. The eval matches an expected commit to a hit by its "
            "abbreviated hash as a string; the cases hold seven-character hashes from October, and the index "
            "now keys every commit by eight characters (git lengthens its abbreviations as the repository "
            "grows; 1,363 of 1,366 keys are eight long). Seventy-five of the 79 expected commits are still in "
            "history, so almost every case is a false miss. The finding is about the harness, not the search: "
            "an eval nobody ran for sixteen days broke silently, and nothing noticed until this report ran "
            "it. Fix the comparison (resolve both sides to full hashes), then rerun to get a real number.",
}


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True).stdout


def survey() -> dict:
    own = (".DS_Store", Path(__file__).name, "transcript_toolkit.py")  # this audit's own scripts
    files = sorted(f.name for f in BIN.iterdir() if f.is_file() and f.name not in own)
    tests = [f for f in files if f.startswith("test_")]
    tools = [f for f in files if not f.startswith("test_")]
    assigned = {f for group in CATEGORIES.values() for f in group}
    missing = [f for f in tools if f not in assigned]
    extra = sorted(assigned - set(tools))
    if missing or extra:
        raise SystemExit(f"category map out of date: unassigned {missing}, gone {extra}")
    texts = {f: (BIN / f).read_text(errors="ignore") for f in files}
    stems = {Path(f).stem for f in files if f.endswith(".py")}
    importers: dict[str, set[str]] = collections.defaultdict(set)
    for f in files:
        if not f.endswith(".py"):
            continue
        for m in re.finditer(r"^\s*(?:from|import)\s+([\w.]+)", texts[f], re.M):
            name = m.group(1).split(".")[0]
            if name in stems and name != Path(f).stem and not f.startswith("test_"):
                importers[name].add(f)
    tested = {Path(t.removeprefix("test_")).stem for t in tests}
    py_tools = [f for f in tools if f.endswith(".py")]
    py_untested = [f for f in py_tools if Path(f).stem not in tested]
    outside = git("grep", "-l", "-E", "|".join(re.escape(f) for f in tools), "--", ":!.devtools/bin").split()
    referenced = set()
    for path in outside:
        text = (REPO / path).read_text(errors="ignore")
        referenced.update(f for f in tools if f in text)
    unreferenced = [f for f in tools if f not in referenced]
    lines = sum(len(texts[f].splitlines()) for f in files)
    return {
        "files": files, "tests": tests, "tools": tools, "lines": lines,
        "by_ext": collections.Counter(Path(f).suffix for f in files),
        "importers": {k: sorted(v) for k, v in importers.items()},
        "py_tools": py_tools, "py_untested": py_untested,
        "unreferenced": unreferenced,
        "subdirs": sorted(d.name for d in BIN.iterdir() if d.is_dir() and not d.name.startswith((".", "__"))),
    }


def rag_log() -> dict:
    path = REPO / ".devtools" / "artifacts" / "rag" / "questions.jsonl"
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    times = sorted(dt.datetime.fromisoformat(r["t"]) for r in rows)
    by_day = collections.Counter(t.date() for t in times)
    first, last = times[0].date(), times[-1].date()
    days = [first + dt.timedelta(days=i) for i in range((last - first).days + 1)]
    sessions = 1 + sum(1 for a, b in zip(times, times[1:]) if (b - a).total_seconds() > 1800)
    paired = sum(1 for a, b in zip(times, times[1:]) if (b - a).total_seconds() <= 15)
    found_docs = sum(1 for r in rows for f in r["found"] if f.startswith("docs/"))
    found_all = sum(len(r["found"]) for r in rows)
    weeks = collections.Counter()
    for t in times:
        monday = t.date() - dt.timedelta(days=t.weekday())
        weeks[monday] += 1
    eval_path = REPO / ".devtools" / "rag" / "eval.jsonl"
    cases = [json.loads(line) for line in eval_path.read_text().splitlines() if line.strip()]
    return {
        "count": len(rows), "days": days, "by_day": by_day, "sessions": sessions, "paired": paired,
        "found_docs": found_docs, "found_all": found_all, "weak": sum(1 for r in rows if r.get("weak")),
        "active_days": len(by_day), "weeks": dict(sorted(weeks.items())),
        "cases": len(cases), "case_kinds": collections.Counter(c.get("kind") for c in cases),
        "distinct": len({r["q"] for r in rows}),
    }


# ---------------------------------------------------------------- charts

def style_axes(ax):
    ax.set_facecolor(SURFACE)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(AXIS)
        ax.spines[side].set_linewidth(0.8)
    ax.tick_params(colors=MUTED, labelsize=8, length=0)
    ax.yaxis.grid(True, color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)


def figure(width=6.6, height=3.0):
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
        "text.color": INK2, "axes.labelcolor": INK2,
    })
    fig, ax = plt.subplots(figsize=(width, height), dpi=200)
    fig.patch.set_facecolor(SURFACE)
    style_axes(ax)
    return fig, ax


def save(fig, out: Path):
    fig.tight_layout()
    fig.savefig(out, facecolor=SURFACE)
    plt.close(fig)
    return out


def chart_growth(out: Path):
    fig, ax = figure(height=3.1)
    dates = [dt.date.fromisoformat(d) for d, *_ in GROWTH]
    series = [
        ("files at bin's root", [r[1] for r in GROWTH], BLUE),
        ("of which test_*.py", [r[2] for r in GROWTH], ORANGE),
        ("Lua probes in bin", [r[3] for r in GROWTH], AQUA),
        ("files in docs/", [r[4] for r in GROWTH], YELLOW),
    ]
    # End labels, nudged apart where two series finish close together.
    ends = sorted(((ys[-1], i) for i, (_, ys, _) in enumerate(series)), reverse=True)
    label_y = {}
    last = None
    for value, i in ends:
        y = value if last is None else min(value, last - 9)
        label_y[i] = y
        last = y
    for i, (name, ys, color) in enumerate(series):
        ax.plot(dates, ys, color=color, linewidth=2, marker="o", markersize=4, label=name)
        ax.annotate(f"{name}  {ys[-1]}", (dates[-1], ys[-1]), xytext=(8, (label_y[i] - ys[-1]) * 1.1),
                    textcoords="offset points", fontsize=7.5, color=INK2, va="center")
    ax.set_xlim(dates[0] - dt.timedelta(days=2), dates[-1] + dt.timedelta(days=26))
    ax.set_ylim(0, 165)
    ax.set_xticks(dates)
    ax.set_xticklabels([d.strftime("%b %d") for d in dates], fontsize=7.5)
    ax.set_ylabel("files", fontsize=8)
    ax.legend(frameon=False, fontsize=7.5, loc="upper left", labelcolor=INK2)
    return save(fig, out)


def chart_categories(out: Path):
    counts = sorted(((k, len(v)) for k, v in CATEGORIES.items()), key=lambda kv: kv[1])
    fig, ax = figure(height=3.2)
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, color=GRID, linewidth=0.6)
    names = [k for k, _ in counts]
    values = [v for _, v in counts]
    ax.barh(names, values, color=BLUE, height=0.55)
    for i, v in enumerate(values):
        ax.text(v + 0.4, i, str(v), va="center", fontsize=8, color=INK2)
    ax.set_xlim(0, max(values) + 4)
    ax.tick_params(axis="y", labelsize=8, colors=INK2)
    ax.set_xlabel("tools (tests not counted)", fontsize=8)
    return save(fig, out)


def chart_hubs(out: Path, importers: dict[str, list[str]]):
    top = sorted(importers.items(), key=lambda kv: len(kv[1]))[-10:]
    fig, ax = figure(height=2.9)
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, color=GRID, linewidth=0.6)
    names = [k + ".py" for k, _ in top]
    values = [len(v) for _, v in top]
    ax.barh(names, values, color=BLUE, height=0.55)
    for i, v in enumerate(values):
        ax.text(v + 0.1, i, str(v), va="center", fontsize=8, color=INK2)
    ax.set_xlim(0, max(values) + 1.5)
    ax.tick_params(axis="y", labelsize=8, colors=INK2)
    ax.set_xlabel("other tools importing it", fontsize=8)
    return save(fig, out)


def chart_status(out: Path, s: dict):
    rows = [
        ("Python tools with a test_*.py", len(s["py_tools"]) - len(s["py_untested"]), len(s["py_untested"]),
         "tested", "untested"),
        ("Tools named outside bin", len(s["tools"]) - len(s["unreferenced"]), len(s["unreferenced"]),
         "named in a doc, skill or CLAUDE.md", "named nowhere"),
        ("Lua tools with any test", 0, s["by_ext"][".lua"] - 1, "tested", "untested"),
    ]
    fig, ax = figure(height=2.1)
    ax.yaxis.grid(False)
    ax.xaxis.grid(False)
    ax.spines["left"].set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.set_xticks([])
    for i, (label, a, b, la, lb) in enumerate(rows):
        total = a + b
        y = len(rows) - 1 - i
        ax.barh(y, a / total * 100, color=BLUE, height=0.5)
        ax.barh(y, b / total * 100, left=a / total * 100 + 0.4, color=NEUTRAL_FILL, height=0.5)
        if a:
            ax.text(1, y, f"{a} {la}", va="center", fontsize=7.5, color="#ffffff")
        ax.text(a / total * 100 + 1.4, y, f"{b} {lb}", va="center", fontsize=7.5, color=INK)
    ax.set_yticks(range(len(rows)))
    ax.set_yticklabels([r[0] for r in reversed(rows)], fontsize=8, color=INK2)
    ax.set_xlim(0, 101)
    return save(fig, out)


def chart_rag(out: Path, r: dict):
    fig, ax = figure(height=2.9)
    days = r["days"]
    values = [r["by_day"].get(d, 0) for d in days]
    ax.bar(days, values, color=BLUE, width=0.72)
    peak = max(values)
    peak_day = days[values.index(peak)]
    ax.annotate(f"{peak} searches on {peak_day.strftime('%b %d')}", (peak_day, peak), xytext=(10, -6),
                textcoords="offset points", fontsize=7.5, color=INK2)
    for d, v in zip(days, values):
        if 0 < v < peak and v >= 24:
            ax.text(d, v + 2, str(v), ha="center", fontsize=7, color=INK2)
    ticks = [d for d in days if d.weekday() == 0]
    ax.set_xticks(ticks)
    ax.set_xticklabels([d.strftime("Mon %b %d") for d in ticks], fontsize=7.5)
    ax.set_ylabel("searches a day", fontsize=8)
    ax.set_xlim(days[0] - dt.timedelta(days=1), days[-1] + dt.timedelta(days=1))
    return save(fig, out)


LUA_DOORS = [
    ("gmod MCP lua_run", "gmod MCP lua_run", BLUE),
    ("dt gmod lua_run (the MCP from a shell)", "dt gmod lua_run", ORANGE),
    ("dt lua / server_lua.py (luadev socket)", None, AQUA),
    ("gmod_lua.py (the first socket tool)", "gmod_lua.py", YELLOW),
]


def chart_doors(out: Path, weekly: dict):
    weeks = sorted(weekly)
    fig, ax = figure(height=2.9)
    dates = [dt.date.fromisoformat(w) for w in weeks]
    bottom = [0] * len(weeks)
    for label, key, color in LUA_DOORS:
        if key is None:
            values = [weekly[w].get("dt lua", 0) + weekly[w].get("server_lua.py", 0) for w in weeks]
        else:
            values = [weekly[w].get(key, 0) for w in weeks]
        ax.bar(dates, values, bottom=bottom, width=5.2, color=color, label=label, edgecolor=SURFACE, linewidth=1)
        bottom = [b + v for b, v in zip(bottom, values)]
    for d, total in zip(dates, bottom):
        ax.text(d, total + 15, str(total), ha="center", fontsize=7.5, color=INK2)
    ax.set_xticks(dates)
    ax.set_xticklabels([d.strftime("Mon %b %d") for d in dates], fontsize=7.5)
    ax.set_ylabel("Lua chunks sent to the server", fontsize=8)
    ax.set_ylim(0, max(bottom) * 1.15)
    ax.legend(frameon=False, fontsize=7.2, loc="upper left", labelcolor=INK2)
    return save(fig, out)


def chart_intents(out: Path, intents: list):
    rows = [(i, n) for i, n in intents if i != "other"][:12]
    rows.sort(key=lambda kv: kv[1])
    fig, ax = figure(height=3.0)
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, color=GRID, linewidth=0.6)
    names = [i for i, _ in rows]
    values = [n for _, n in rows]
    colors_ = [ORANGE if i in ("map change", "which map", "limits off (mp_timelimit 0 ...)") else BLUE for i in names]
    ax.barh(names, values, color=colors_, height=0.55)
    for y, v in enumerate(values):
        ax.text(v + 8, y, str(v), va="center", fontsize=8, color=INK2)
    ax.set_xlim(0, max(values) * 1.12)
    ax.tick_params(axis="y", labelsize=8, colors=INK2)
    ax.set_xlabel("Lua chunks and console commands, Oct 5 to Nov 13 (orange: the rituals around map changes)",
                  fontsize=7.5)
    return save(fig, out)


def chart_timeline(out: Path):
    """A vertical timeline: one evenly spaced row a milestone, the files at bin's root that week as a bar."""
    rows = len(MILESTONES)
    fig, ax = figure(height=0.27 * rows + 0.5)
    ax.yaxis.grid(False)
    ax.xaxis.grid(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_visible(False)
    ax.set_xticks([])
    ax.set_yticks([])
    growth = [(dt.date.fromisoformat(d), root) for d, root, *_ in GROWTH]
    ax.vlines(0, -0.5, rows - 0.5, color=AXIS, linewidth=1.2)
    for i, (d, label) in enumerate(MILESTONES):
        y = rows - 1 - i
        date = dt.date.fromisoformat(d)
        root = next((r for g, r in growth if g >= date), growth[-1][1])
        ax.scatter([0], [y], s=22, color=BLUE, zorder=3)
        ax.text(-0.04, y, date.strftime("%b %d"), ha="right", va="center", fontsize=7.5, color=INK2)
        ax.text(0.05, y, label, ha="left", va="center", fontsize=7.5, color=INK)
        ax.barh(y, root / 160 * 0.9, left=2.05, height=0.5, color=BLUE_300)
        ax.text(2.05 + root / 160 * 0.9 + 0.02, y, str(root), va="center", fontsize=7, color=INK2)
    ax.text(2.05, rows - 0.35, "files at bin's root by that week's end", fontsize=7, color=MUTED, va="bottom")
    ax.set_xlim(-0.4, 3.1)
    ax.set_ylim(-0.6, rows)
    return save(fig, out)


# ---------------------------------------------------------------- the document

def styles():
    base = getSampleStyleSheet()
    body = ParagraphStyle("body", parent=base["Normal"], fontName="Helvetica", fontSize=9.6, leading=13.4,
                          textColor=INK, spaceAfter=6, alignment=TA_LEFT)
    return {
        "title": ParagraphStyle("title", parent=body, fontName="Helvetica-Bold", fontSize=22, leading=27,
                                spaceAfter=4),
        "subtitle": ParagraphStyle("subtitle", parent=body, fontSize=10.5, textColor=INK2, spaceAfter=16),
        "h1": ParagraphStyle("h1", parent=body, fontName="Helvetica-Bold", fontSize=14.5, leading=18,
                             spaceBefore=12, spaceAfter=6, textColor=INK, keepWithNext=1),
        "h2": ParagraphStyle("h2", parent=body, fontName="Helvetica-Bold", fontSize=11, leading=14,
                             spaceBefore=8, spaceAfter=3, textColor=INK, keepWithNext=1),
        "body": body,
        "bullet": ParagraphStyle("bullet", parent=body, leftIndent=12, bulletIndent=2, spaceAfter=3),
        "caption": ParagraphStyle("caption", parent=body, fontSize=8, leading=10.5, textColor=MUTED,
                                  spaceAfter=10),
        "cell": ParagraphStyle("cell", parent=body, fontSize=8.4, leading=10.8, spaceAfter=0),
        "cellhead": ParagraphStyle("cellhead", parent=body, fontName="Helvetica-Bold", fontSize=8.4,
                                   leading=10.8, spaceAfter=0, textColor=INK2),
        "question": ParagraphStyle("question", parent=body, leftIndent=12, bulletIndent=2, spaceAfter=4,
                                   textColor=INK),
    }


def table(rows: list[list[str]], widths: list[float], st: dict, head=True) -> Table:
    data = []
    for i, row in enumerate(rows):
        style = st["cellhead"] if head and i == 0 else st["cell"]
        data.append([Paragraph(c, style) for c in row])
    t = Table(data, colWidths=widths, hAlign="LEFT")
    cmds = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, colors.HexColor(AXIS)),
        ("LINEBELOW", (0, 1), (-1, -1), 0.3, colors.HexColor(GRID)),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 2),
    ]
    t.setStyle(TableStyle(cmds))
    return t


def bullets(items: list[str], st: dict, style="bullet"):
    return [Paragraph(item, st[style], bulletText="•") for item in items]


def numbered(items: list[str], st: dict):
    return [Paragraph(item, st["question"], bulletText=f"{i}.") for i, item in enumerate(items, 1)]


def image(path: Path, width=6.6 * inch):
    from PIL import Image as PILImage  # matplotlib brings Pillow

    w, h = PILImage.open(path).size
    return Image(str(path), width=width, height=width * h / w)


def toolkit_log() -> dict:
    path = REPO / ".devtools" / "artifacts" / "transcript-toolkit.json"
    if not path.exists():
        raise SystemExit(f"{path} missing: run .devtools/bin/transcript_toolkit.py first")
    return json.loads(path.read_text())


def build(out: Path, s: dict, r: dict, k: dict, charts: dict[str, Path]):
    st = styles()
    doc = SimpleDocTemplate(str(out), pagesize=letter, leftMargin=0.95 * inch, rightMargin=0.95 * inch,
                            topMargin=0.85 * inch, bottomMargin=0.85 * inch,
                            title="The .devtools audit", author="jaycemod")
    W = 6.6 * inch
    story = []
    P = lambda text, style="body": story.append(Paragraph(text, st[style]))  # noqa: E731
    H1 = lambda text: story.append(Paragraph(text, st["h1"]))  # noqa: E731
    H2 = lambda text: story.append(Paragraph(text, st["h2"]))  # noqa: E731

    tools, tests = len(s["tools"]), len(s["tests"])
    lua = s["by_ext"][".lua"]
    rag_weeks = list(r["weeks"].values())

    # ---- title and summary
    P("The .devtools audit", "title")
    P(f"What lives in <font face='Courier'>.devtools/bin</font> and <font face='Courier'>.claude</font>, how the "
      f"folder came to be this way, how devrag has been used, and whether the harness around them is earning "
      f"its keep. jaycemod, {TODAY}.", "subtitle")

    H1("1. Summary")
    story.append(table([
        ["Measure", "Value"],
        ["Files at bin's root", f"{len(s['files'])} ({s['by_ext']['.py']} Python, {lua} Lua, {s['by_ext']['.sh']} shell)"],
        ["Of which tests (test_*.py)", f"{tests}, so {tools} tools"],
        ["Lines of code", f"about {s['lines']:,}"],
        ["Subfolders", ", ".join(s["subdirs"])],
        ["Growth", "10 files on Sep 28, 53 on Oct 12, 147 today"],
        ["Tools no doc, skill or CLAUDE.md names", f"{len(s['unreferenced'])}"],
        ["Python tools without a test", f"{len(s['py_untested'])} of {len(s['py_tools'])}; no Lua tool has one"],
        ["Generated artifacts", "236 MB in .devtools/artifacts, ignored by git"],
        ["devrag searches logged", f"{r['count']} over {r['active_days']} days and {r['sessions']} sessions"],
    ], [2.4 * inch, 4.2 * inch], st))
    story.append(Spacer(1, 8))
    P("Five findings carry the rest of the report:")
    story.extend(bullets([
        "<b>The folder is nine jobs in one drawer.</b> Server plumbing, live probes, benches, the rooms "
        "library, Source content readers, repo checks, refactor tools, art baking and two research efforts "
        "share one flat namespace. Only two of them have a subfolder.",
        "<b>It grew by accretion and never by retirement.</b> Three generations of \"run Lua on the server\" "
        "coexist, the September in-game harness still sits beside the workbench that replaced it, and at "
        "least eight tools finished their job weeks ago.",
        "<b>The layout rule made the drawer.</b> \"A script is anything you might run twice\" plus a hook that "
        "denies scripts anywhere else sends every probe into bin. The rule has one home for scripts and none "
        "for experiments, so experiments become permanent.",
        "<b>devrag is used in bursts and its use is falling.</b> Weekly searches went "
        f"{', '.join(str(v) for v in rag_weeks)}. A third of searches come within fifteen seconds of the "
        "previous one, the two-questions ritual the rule asks for, and the log cannot tell a hit from a miss.",
        "<b>The harness answers \"what does the game do\" well and \"why is it this way\" unevenly.</b> The "
        "gmod MCP and the workbench return data; devrag returns eight candidates every time with no "
        "abstention and no feedback loop; the skills describe the same loop three times.",
    ], st))

    # ---- section 2: what lives here
    story.append(PageBreak())
    H1("2. What lives in .devtools/bin")
    P(f"The folder holds about 28,000 lines across {len(s['files'])} files, plus five subfolders of tools. The "
      f"tests double the file count: {tests} of the {len(s['files'])} are pytest files sitting beside the tool "
      "they test.")
    story.append(image(charts["growth"], W))
    P("Figure 1. Files at bin's root by week, with the tests and Lua probes among them, and docs/ for scale. "
      "The jump from 17 to 53 files in the week of Oct 5 to 12 is the game events v2 research and the "
      "foundation split; the Lua probes begin in late October and double in November.", "caption")

    H2("The nine jobs")
    P("Grouping the 101 tools by what they are for gives nine categories. The names already imply them: "
      "<font face='Courier'>*_check.lua</font>, <font face='Courier'>*_bench</font>, "
      "<font face='Courier'>*_view.py</font>, <font face='Courier'>check_*</font>.")
    story.append(image(charts["categories"], W))
    P("Figure 2. Tools by job. Tests are left out; a test belongs to its tool's category.", "caption")
    cat_rows = [["Job", "Tools", "Examples", "Has a folder"]]
    examples = {
        "Server plumbing": "srcds, server_root, server_lua, gmod_mcp, instances",
        "Live-server probes": "bot_status, lane_audit, stuck_census, *_check.lua",
        "Benches and fixtures": "aiwar_bench, ns_bench_run, dev_3house_*, record_routes",
        "Rooms and places": "incursion, places, classes, rooms_view, assault_view",
        "Source/TF2 content readers": "vpk, gma, bsp_entities, nav_convert, tf2_content",
        "Repo checks and hooks": "check_lua.sh, suites.lua, lua_format, check_names",
        "Refactor and history": "foundation_rename, retwin_comment, strip_attribution",
        "Art and assets": "kill_icons_art, teamtint_bake, gamemode_art",
        "Game events v2 research": "gev2_probe, gev2_client_session (+ gev2/)",
        "In-game harness (2026-09)": "ingame_tests, ingame_one (+ ingame/checks)",
    }
    folders = {"Server plumbing": "dt/, server_root/", "Game events v2 research": "gev2/",
               "In-game harness (2026-09)": "ingame/", "Live-server probes": "listeners/ (one file)"}
    for name, group in sorted(CATEGORIES.items(), key=lambda kv: -len(kv[1])):
        cat_rows.append([name, str(len(group)), examples[name], folders.get(name, "no")])
    story.append(KeepTogether(table(cat_rows, [1.75 * inch, 0.5 * inch, 3.1 * inch, 1.25 * inch], st)))
    story.append(Spacer(1, 6))

    H2("What depends on what")
    P("Only the server plumbing is depended on. Nine tools import <font face='Courier'>server_root</font> and "
      "nine import <font face='Courier'>srcds</font>; the rooms library is the one other cluster. Everything "
      "else is a leaf: a probe, a bench, a one-off.")
    story.append(image(charts["hubs"], W))
    P("Figure 3. The modules other tools import, counting non-test importers. The plumbing and the rooms "
      "library are the only shared code; the other 80 tools import nothing of each other.", "caption")

    H2("Repetitions")
    story.extend(bullets([
        "<b>Three doors to one room.</b> <font face='Courier'>gmod_lua.py</font> (Sep 27) and "
        "<font face='Courier'>server_lua.py</font> (Oct 9) both run Lua through luadev's socket; the gmod "
        "MCP's <font face='Courier'>lua_run</font> (Oct 10) is the third. <font face='Courier'>lua_watch.py"
        "</font> still uses the first, everything else the second, the skills recommend the third.",
        "<b>The dt drawer is four symlinks and two wrappers.</b> <font face='Courier'>dt/lua.py</font>, "
        "<font face='Courier'>srcds.py</font>, <font face='Courier'>watch.py</font> and <font face='Courier'>"
        "add_map.py</font> are the root files under second names. The name also collides with the "
        "cross-project <font face='Courier'>dt</font> dispatcher in claude-config2.",
        "<b>Projects held together by prefix only.</b> <font face='Courier'>dev_3house_*</font> (four files: a "
        "map builder, a nav builder, a bench, a trial), <font face='Courier'>gev2_*</font> (three plus a "
        "folder), <font face='Courier'>hostage_*</font> (three), <font face='Courier'>stuck_*</font>, "
        "<font face='Courier'>ctfbot_*</font>, and the route pipeline (record, replay, capture, told_check).",
        "<b>One subject, three spellings.</b> <font face='Courier'>next_soldier_*</font>, "
        "<font face='Courier'>nextsoldier_*</font> and <font face='Courier'>ns_*</font>; "
        "<font face='Courier'>aiwar_*</font> and <font face='Courier'>war_round_check</font>.",
        "<b>Four renderers, four Draw functions.</b> rooms_view, incursion_view, classes_view and "
        "assault_view each define their own Draw and Summary over the same dumped room graph.",
    ], st))

    H2("Coverage")
    story.append(image(charts["status"], W))
    P("Figure 4. Which tools have a test and which are named anywhere outside the folder. The Lua probes "
      "have neither.", "caption")
    P(f"The {len(s['unreferenced'])} tools nothing names: " + ", ".join(
        f"<font face='Courier'>{f}</font>" for f in s["unreferenced"]) + ". Some are live and undocumented; "
      "some are dead. The folder cannot say which.")
    P("Finished, their job done and merged: " + ", ".join(
        f"<font face='Courier'>{f}</font>" for f in FINISHED) + ", and the <font face='Courier'>gev2/</font> "
      "folder. Game events v2 was superseded by net2 on Nov 10 (docs/net2.md says so), which closes the whole "
      "gev2 family; <font face='Courier'>gmod_client.py</font>, the largest file in bin, was built for its "
      "client tests and survives only because the dedicated-server skill still names it.")

    # ---- section 3: .claude
    H1("3. What lives in .claude")
    P("Ten tracked files: two rules, four skills, a settings file with one hook (the Lua check gate). "
      "<font face='Courier'>settings.local.json</font>, <font face='Courier'>worktrees/</font> and "
      "<font face='Courier'>.DS_Store</font> are ignored as they should be. It is small and mostly healthy; "
      "what it shows is overlap and weight.")
    story.append(table([
        ["File", "Lines", "Loaded", "Covers"],
        ["rules/live-server.md", "160", "every session", "the MCP, the workbench loop, the whole dev library index"],
        ["rules/lua-metamethods.md", "154", "every session", "Lua's metamethods, a language reference"],
        ["skills/dedicated-server", "217", "on demand", "srcds, RCON, luadev, lua_watch, in-game checks, a client"],
        ["skills/server-lua", "144", "on demand", "server_lua, Watch, dt lua / rcon / gmod"],
        ["skills/dev-workbench", "96", "on demand", "dev_reload, scenarios, the gamerules harness"],
        ["skills/glua-style", "149 + 451", "on demand", "the style guide and its reference Lua"],
        ["settings.json", "15", "always", "the check_lua_gate hook"],
    ], [1.7 * inch, 0.7 * inch, 0.9 * inch, 3.3 * inch], st))
    story.append(Spacer(1, 6))
    story.extend(bullets([
        "<b>Three documents describe the same loop.</b> live-server.md, server-lua and dedicated-server all "
        "cover dt lua, dt rcon, dt gmod and luadev; live-server.md and dev-workbench both cover dev_reload and "
        "scenarios. With the MCP as the primary door, server-lua is largely a subset of dedicated-server.",
        "<b>314 lines load into every session</b> before any work starts: the dev library index (which the "
        "dev-workbench skill could own, on demand) and a Lua language reference that is not a project rule.",
        "<b>The skills know only the plumbing.</b> Nothing in .claude points at the probes, benches, rooms "
        "library or content readers, so 60-odd tools are discoverable only by listing the folder.",
    ], st))

    # ---- section 4: origin and evolution
    story.append(PageBreak())
    H1("4. The original design, and what it became")
    story.append(image(charts["timeline"], W))
    P("Figure 5. The harness's milestones, with the number of files at bin's root by the end of each "
      "milestone's week.", "caption")
    H2("The design")
    P("The folder came with a rule, three days before its first file: <i>one place for everything</i> "
      "(claude-config2's layout rule, Sep 24). A reusable script lives in the project's "
      "<font face='Courier'>.devtools/bin/</font>, a cross-project one in the claude-config2 drawer run as "
      "<font face='Courier'>dt category/name</font>, generated output in <font face='Courier'>"
      ".devtools/artifacts/</font>, documentation in docs/. A hook enforces it on every write. The first "
      "commit (Sep 27) set the pattern the folder kept: two small command-line tools, each with a docstring "
      "that is its manual and a pytest file beside it.")
    P("That design is a <i>drawer</i>: flat, named by hand, every item self-describing. It assumes a modest "
      "count and a reader who can scan it. It held through Oct 5, at 17 files.")
    H2("Three turns")
    story.extend(bullets([
        "<b>Sep 30: the in-game harness.</b> srcds.py runs the dedicated server under CrossOver and "
        "ingame_tests.py drives checks per map and writes a report. It ran twice (Oct 7, Oct 14) and its "
        "reports are the only ones in artifacts. It was the first attempt at \"test on the live server\".",
        "<b>Oct 9 to 22: the live loop.</b> server_lua and Watch (a reply channel and events pushed back), "
        "the gmod MCP, the dt short names, two skills, then the dev workbench addon with reload, capture and "
        "scenarios. This is the harness that stuck; the live-server rule (Oct 27) codified it. The in-game "
        "harness was not retired when it was superseded.",
        "<b>Oct 22 onward: the folder as a workbench for the AI war.</b> foundation_rename and the split "
        "tools, instances.py so benches lease servers, suites.lua and the gate so agents check only the "
        "groups they touched, then 32 Lua probes in six weeks as the soldiers, squads and rooms were "
        "prototyped. From Oct 12 the folder roughly doubled every three weeks.",
    ], st))
    H2("How the rule shaped the outcome")
    P("The layout rule has a home for scripts and for artifacts, and none for <i>experiments</i>: a probe "
      "written to answer one question during one prototyping session. Since \"a script is anything you might "
      "run twice\" and the hook denies the scratchpad, every probe is written into bin with the same standing "
      "as srcds.py. Nothing in the rule says when a tool leaves. The folder is therefore a faithful log of "
      "every question the project asked of the live game, which is a useful record and a poor toolbox.")
    P("The second shaping force is that the agents, not the operator, wrote almost all of it. An agent "
      "reaches for a new file more readily than for an existing one it would have to read first, and it "
      "names by the task in front of it (<font face='Courier'>next_soldier_head_check</font>) rather than by "
      "a scheme. The spelling drift and the prefix-only projects are that habit, made visible.")

    # ---- section 5: where should these live
    H1("5. Where a more appropriate home might be")
    P("The question is less \"what folder\" than \"what kind of thing is each tool, and who is its reader\". "
      "Sorting by that, five homes appear, and only the first is the folder we have.")
    story.append(table([
        ["Kind", "Which", "Home", "Why"],
        ["The project's build and test system",
         "srcds, server_root, instances, gmod_mcp, server_lua, server_watch, add_map, lua_watch; check_lua, "
         "suites, the gate, lua_format, check_names, drg_interface",
         ".devtools/bin as two packages: server/ and check/, with the tests in .devtools/tests/",
         "Bound to this repo, depended on by everything, documented by the skills. This is what bin was for."],
        ["Probes of the live game",
         "the 21 *_check, *_status, *_census, *_audit, *_watch scripts",
         "the dev workbench (addons/sandcastle_dev) as dev.* functions and console commands, held by its "
         "index test",
         "They are server Lua already run through dt lua. The workbench has the index, the test that keeps "
         "it honest, and the reload. A probe there is discoverable from inside the game; in bin it is not."],
        ["Knowledge of Source and GMod formats",
         "vpk, gma, bsp_entities, nav_convert, ice, pe_rtti, lua_glue, tf2_content, tf2_scene, hud_res",
         "a package of its own (sourcetools), in the claude-config2 drawer as dt source/vpk or its own repo",
         "Nothing in them is Sandcastle's. hammer-mcp and any later GMod work want the same readers."],
        ["Experiments and benches",
         "aiwar_bench, aiwar_ab_bench, stranding_ab, hostage_survey, dustbowl_stage2_bench, dev_3house_*, "
         "gev2_*, ns_bench_*, the route pipeline, the in-game harness",
         ".devtools/experiments/<name>/ with its scripts, fixtures and artifacts together, or beside the plan "
         "it serves in docs/research/",
         "Each has a question, a span and an end. Keeping the script with its results and its plan makes the "
         "end visible, and makes deletion a folder, not a hunt."],
        ["The rooms library",
         "incursion, places, classes, ambush and the four views",
         "one package, tools/rooms/, with one renderer and the views as its modes",
         "It is a library split into nine root files, the only one in bin besides the plumbing."],
        ["Finished work",
         "foundation_rename, foundation_globals, retwin_comment, gev2_marker, check_no_markers, tf2c_assets, "
         "hud_res, ice",
         "git",
         "Their job is merged. The commit that added each is its record."],
    ], [1.15 * inch, 1.85 * inch, 1.7 * inch, 1.9 * inch], st))
    story.append(Spacer(1, 6))
    H2("Artifacts, scenarios and secrets")
    P("artifacts/ holds 236 MB in 75 entries: timestamped bench results at its root beside folders, "
      "add_map's lock and log files, and two secrets (<font face='Courier'>rcon_password</font>, "
      "<font face='Courier'>steam_account_token</font>) as plain files. The same sorting applies: a bench's "
      "results belong with the bench; logs and locks belong in a run/ folder the tools own; secrets belong "
      "in <font face='Courier'>.devtools/secrets/</font> or the keychain, never beside data an agent may list "
      "and read into a report.")
    H2("A note on the name")
    P("\"devtools\" now names three different things: this folder, the cross-project drawer in claude-config2 "
      "that <font face='Courier'>dt</font> dispatches, and the <font face='Courier'>bin/dt/</font> drawer "
      "inside this folder. One word for the project's harness (<i>harness</i>, <i>workbench</i>) and another "
      "for personal cross-project tools would end the collision and make the rule easier to state.")

    # ---- section 6: devrag
    story.append(PageBreak())
    H1("6. devrag: what it is and how often it has been used")
    P("devrag is <font face='Courier'>dt rag/history</font>, a 599-line tool in the claude-config2 drawer "
      "(created Oct 21, and still uncommitted there). It indexes every commit message on every branch and the "
      "markdown under docs/, fuses a keyword ranking (SQLite FTS5) with a meaning ranking (local embeddings, "
      "mxbai-embed-large), and returns its best eight. By the tool's own finding on Oct 20, no score "
      "separates an answered question from an unanswered one, so it never abstains. CLAUDE.md asks every "
      "agent to write one or two questions before changing existing behaviour, search each, and show what "
      "came up. Each search is appended to <font face='Courier'>artifacts/rag/questions.jsonl</font>; "
      "corrected questions are meant to become eval cases in <font face='Courier'>.devtools/rag/eval.jsonl"
      "</font>.")
    story.append(image(charts["rag"], W))
    P("Figure 6. devrag searches a day, Oct 21 to Nov 12, from questions.jsonl. Nov 1 alone is 151 searches, "
      "a third of all of them.", "caption")
    story.append(table([
        ["Measure", "Value", "Reading"],
        ["Searches logged", f"{r['count']} ({r['distinct']} distinct)", "over 23 days; 19 had at least one"],
        ["Sessions (gaps over 30 min)", str(r["sessions"]), "about 7 searches a session"],
        ["By week (Mon Oct 19, 26, Nov 2, 9)", ", ".join(str(v) for v in rag_weeks),
         "a burst, then a fall to a tenth"],
        ["Asked within 15 s of the previous", f"{r['paired']} ({r['paired'] * 100 // r['count']}%)",
         "the two-questions ritual, fired back to back"],
        ["Results that are docs vs commits", f"{r['found_docs']} vs {r['found_all'] - r['found_docs']}",
         "three quarters of hits are commit messages"],
        ["Searches marked weak", str(r["weak"]), "the one feedback field, never set"],
        ["Eval cases", f"{r['cases']} ({', '.join(f'{k} {v}' for k, v in r['case_kinds'].items())})",
         "last added Oct 28; 3 are operator corrections"],
    ], [2.2 * inch, 1.7 * inch, 2.7 * inch], st))
    story.append(Spacer(1, 6))
    if EVAL:
        H2("What the eval says today")
        story.append(table([["Ranking", "Score", "Note"]] + [[k, str(v), n] for k, v, n in EVAL["rows"]],
                           [1.6 * inch, 1.2 * inch, 3.8 * inch], st))
        P(EVAL["note"])
    else:
        P("<i>The eval over the 54 cases was still running when this report was written; its scores are not "
          "in it.</i>")
    H2("Reading the pattern")
    story.extend(bullets([
        "<b>Use follows orchestration, not need.</b> The 151-search day and the 40-search days after it match "
        "the multi-agent runs of early November, where each agent obeyed the rule at the start of each task. "
        "The quiet days are the operator's own attended sessions. The tool is used when a rule fires, not "
        "when someone is puzzled.",
        "<b>The paired questions are the rule, not curiosity.</b> 140 searches came within fifteen seconds of "
        "the previous one: the agent wrote its two questions and ran both. That is compliance; whether the "
        "second question added anything the log cannot say.",
        "<b>The log has no outcome.</b> It records the question and the eight hits, never which one the agent "
        "then read, whether the operator corrected the question, or whether the search changed the change. "
        "The weak flag exists and has never been set. 440 searches have produced no signal about their "
        "worth, which is the thing the log was meant to produce.",
        "<b>The eval froze while the corpus moved.</b> Cases stopped on Oct 28. Since then the gamemode split "
        "into addons, NextSoldier and wartactics were carved out, and the repo moved. The eval still measures "
        "the search against late-October questions.",
        "<b>The fall in November is ambiguous.</b> It may mean the agents absorbed the history into CLAUDE.md "
        "and docs and need the search less, or that the rule is being skipped. Either reading matters and "
        "the data cannot pick one.",
    ], st))

    # ---- section 7: is the metaharness effective
    story.append(PageBreak())
    H1("7. Is the harness effective?")
    P("Three questions, each answered from what the folder, the logs and the history show, with the limits "
      "of that evidence stated.")
    H2("Does it answer questions?")
    P("<b>\"What does the game do?\"</b> Yes, and this is the harness's clear success. The gmod MCP returns "
      "Lua values as data, breakpoints capture who reaches a line, the workbench reloads a change in place and "
      "restores a saved scenario, and the live-server rule turns all that into a procedure. A question about "
      "behaviour is answered in a minute on the running server where a month ago it was answered by a map "
      "change and a guess from source.")
    P("<b>\"Why is it this way?\"</b> Partly. devrag reaches commit messages and plans, which this project "
      "writes carefully, so when the answer is in history the search likely finds it among eight. But it "
      "cannot say when the answer is not there, the log cannot say how often the agent found it, and the "
      "eval has not kept pace. The honest statement is that devrag's value is plausible and unmeasured, and "
      "the mechanism to measure it was designed and then not used.")
    P("<b>\"What tools do we have?\"</b> Poorly. 24 tools are named nowhere, the skills know only the "
      "plumbing, and the one index that exists (the dev library in live-server.md) covers the workbench, not "
      "bin. A newcomer, agent or human, learns the folder by listing it.")
    H2("Does it raise productivity?")
    P("Where it does: check_lua.sh's groups and the gate keep 397 tests from being run whole on every change; "
      "dt short names save keystrokes and quoting; dev.reload removes the map change; instances.py lets a "
      "bench run unattended on a leased server; lua_format.py removes a class of review comments. Those are "
      "real and recent, and each arrived as a response to a felt cost.")
    P("Where it costs: every session loads 314 lines of rules before work, three documents describe one loop, "
      "three doors open onto one room and the agent must pick one, and the flat drawer makes \"is there "
      "already a tool for this?\" a question that takes longer to answer than writing the tool. The "
      "two-questions rule costs a search pair at the start of every behaviour change and returns a record "
      "no one reads back. Productivity tooling that is itself undiscoverable is paid for twice.")
    H2("Does it adapt as prototyping reveals better directions?")
    P("It adapts by <b>addition</b> well and by <b>subtraction</b> not at all. Every turn in Section 4 was a "
      "good response to a real problem: the reply channel when RCON could not answer, the MCP when the "
      "socket was clumsy from an agent, the workbench when map changes cost too much, the gate when agents "
      "ran the whole suite, server leasing when benches collided. In each case the new thing was built and "
      "the old thing stayed. The harness has no step for retiring a tool, a rule, or a skill: no owner, no "
      "last-used date, no sunset, no review. The result is a folder that remembers every direction the "
      "prototype took, including the ones it left.")
    P("The rules show the same shape. The layout rule has not changed since Sep 24 though the folder it "
      "governs grew fifteen-fold; the two-questions rule has not been revisited since devrag's use "
      "collapsed; live-server.md grew to carry an index because there was nowhere else indexed. A harness "
      "that adapts would have its rules revisited at the same cadence as its code.")
    H2("A correction that did not take")
    P("The memory directory holds a feedback entry from Oct 10, repeated Oct 17: edit files with the Edit "
      "tool, never with Python heredocs or sed through Bash. The transcripts show what happened next.")
    story.append(KeepTogether(table([
        ["Week of", "Edit and Write tool calls", "Bash heredoc edits", "sed -i"],
        ["Oct 5", "96", "31", "11"],
        ["Oct 12 (correction Oct 10 and 17)", "765", "149", "78"],
        ["Oct 19", "1,024", "412", "113"],
        ["Oct 26", "1,226", "439", "36"],
        ["Nov 2", "1,666", "680", "117"],
        ["Nov 9", "800", "183", "44"],
    ], [2.2 * inch, 1.6 * inch, 1.5 * inch, 1.3 * inch], st)))
    story.append(Spacer(1, 4))
    P("Heredoc edits ran at about a third of the tool edits every week and peaked three weeks after the "
      "second correction. Part of the cause is in the harness itself: when a session runs with permissions "
      "bypassed, Claude Code's own instructions tell the agent to prefer Bash, sed and heredocs over the Edit "
      "tool, which is the opposite of the stored feedback. A memory cannot win against a system instruction, "
      "so the correction keeps being given. The fix is a hook that denies heredoc edits, as the think-in-code "
      "hook already denies recursive grep, or a permissions mode that does not carry that instruction.")

    # ---- section 8: the live-server toolkit in the transcripts
    story.append(PageBreak())
    H1("8. The live-server toolkit in practice")
    doors = dict(k["doors"])
    lua_calls = sum(doors.get(d, 0) for d in ("gmod MCP lua_run", "dt lua", "dt gmod lua_run", "server_lua.py", "gmod_lua.py"))
    rcon_calls = sum(doors.get(d, 0) for d in ("dt rcon", "gmod MCP rcon", "srcds.py rcon"))
    starts = sum(doors.get(d, 0) for d in ("srcds.py start", "srcds.py stop", "dt srcds"))
    intents = dict(k["intents"])
    errors = dict(k["errors"])
    retries = dict(k["retries"])
    P(f"This section reads Claude Code's own transcripts for the project under both names, "
      f"{k['files']} sessions from Oct 5 to Nov 13, and classifies every tool call that touched the server "
      f"or the checks. Only aggregates were read; no transcript text beyond short command templates. "
      f"{k['toolkit_calls']:,} of {k['total_tool_calls']:,} tool calls went through the toolkit, in "
      f"{k['sessions_using']} sessions, a median of {k['calls_per_session_median']:.0f} a session and "
      f"{k['calls_per_session_max']:,} at most.")
    story.append(table([
        ["Door", "Calls", "Note"],
        ["Lua sent to the server, all doors", f"{lua_calls:,}",
         f"MCP lua_run {doors.get('gmod MCP lua_run', 0):,}; the MCP from a shell {doors.get('dt gmod lua_run', 0)}; "
         f"dt lua {doors.get('dt lua', 0)}; server_lua.py {doors.get('server_lua.py', 0)}; gmod_lua.py {doors.get('gmod_lua.py', 0)}"],
        ["Console commands over RCON", f"{rcon_calls}",
         f"dt rcon {doors.get('dt rcon', 0)}, MCP rcon {doors.get('gmod MCP rcon', 0)}, srcds.py rcon {doors.get('srcds.py rcon', 0)}"],
        ["Reads of Lua errors", f"{doors.get('gmod MCP lua_errors', 0) + doors.get('dt gmod lua_errors', 0)}",
         "all but a handful with no since argument, so each read returns the whole list again"],
        ["Server started or stopped", f"{starts}", "despite the rule never to restart; the server was found down 61 times"],
        ["Benches leasing servers (instances.py)", f"{doors.get('instances.py', 0)}", "a third of them polling in sleep loops"],
        ["Test runs (luajit, check_lua.sh, run_lua_tests.sh)",
         f"{doors.get('luajit a test', 0) + doors.get('run_lua_tests.sh', 0) + sum(n for d, n in doors.items() if d.startswith('check_lua.sh')):,}",
         f"check_lua.sh --changed {doors.get('check_lua.sh --changed', 0)}, a named group {sum(n for d, n in doors.items() if d.startswith('check_lua.sh ') and d not in ('check_lua.sh --changed', 'check_lua.sh 2', 'check_lua.sh all'))}, all {doors.get('check_lua.sh all', 0)}"],
        ["The debugger (breakpoints), game events, watch", f"{sum(n for d, n in doors.items() if 'breakpoint' in d or 'game_events' in d or d == 'dt watch')}",
         "the MCP's distinguishing features, almost untouched"],
        ["devrag from a shell", f"{doors.get('dt rag/history search', 0) + doors.get('dt rag/history files', 0)}",
         "search and files; the log in Section 6 holds the rest"],
    ], [2.3 * inch, 0.6 * inch, 3.7 * inch], st))
    story.append(Spacer(1, 6))
    story.append(image(charts["doors"], W))
    P("Figure 7. Lua chunks sent to the server each week, by door. The socket tools led in October, the MCP "
      "took over in the week of Oct 26, and the shell wrapper around the MCP appeared when context-mode "
      "batching made it attractive. In the latest week the socket tool is back level with the MCP. Five doors, "
      "never settled.", "caption")
    story.append(image(charts["intents"], W))
    P("Figure 8. What the Lua and console commands were for, by the first thing each chunk does. Reads of "
      "soldiers and the war dominate, as they should on an AI project; the orange bars are the rituals around "
      "a map change.", "caption")
    H2("What works")
    story.extend(bullets([
        f"<b>The MCP is the door agents prefer once they have it.</b> {doors.get('gmod MCP lua_run', 0):,} "
        "calls, and the busiest week sent over a thousand. Its error rate is 9%, and 51 of those 161 errors "
        "are the server being down, not the tool.",
        f"<b>The grouped checks took.</b> check_lua.sh with a group or --changed was run "
        f"{doors.get('check_lua.sh --changed', 0) + sum(n for d, n in doors.items() if d.startswith('check_lua.sh ') and d not in ('check_lua.sh --changed', 'check_lua.sh 2', 'check_lua.sh all'))} "
        f"times against {doors.get('check_lua.sh all', 0)} for the whole suite, and the gate's refusals appear in the error list.",
        "<b>The edit, test, try-it-live loop is real.</b> The commonest sequences are a test run followed by a "
        "lua_run and the reverse (186 and 144 times): agents do check a change in the game, which is what the "
        "harness was built for.",
    ], st))
    H2("The repetitive tasks")
    story.extend(bullets([
        f"<b>Asking which map is up: {intents.get('which map', 0)} times.</b> CLAUDE.md asks for it before map-dependent "
        "work, and agents obey, one call each time. The MCP could put the map, the player count and the "
        "round state in a header on every result and the question would never be asked.",
        f"<b>Changing the map: {intents.get('map change', 0)} times, against {intents.get('dev.reload', 0)} reloads.</b> The rule says "
        "change map only when reload refuses, and reload refuses cl_, sh_ and root files, which many changes "
        "touch. Each change resets the limits, so the <font face='Courier'>mp_timelimit 0; mp_winlimit 0; "
        "mp_maxrounds 0</font> line follows it (25 times by hand). A reload that handles sh_ files, and a "
        "dev-server convar that holds the map, would remove most of both.",
        f"<b>Reading errors after every run: {doors.get('gmod MCP lua_errors', 0)} lua_errors calls</b>, 165 of them "
        "directly after a lua_run and 146 followed by another. Almost none pass since, so each returns the "
        "whole list. If lua_run returned the errors raised during it, the second call would go away.",
        f"<b>Polling in shell loops: {k['bash_loops']:,} Bash calls contain a sleep, an until or a for loop</b>, most of "
        "them waiting on the server or a bench (<font face='Courier'>until dt gmod lua_run ...</font>, "
        "<font face='Courier'>sleep N; server_lua.py ...</font>, <font face='Courier'>for i in seq ...; "
        "instances.py</font>). The skills forbid exactly this. Watch and listeners exist and were used 6 times. "
        "A wait tool the agent can call once (a condition in Lua, a timeout) is the missing ergonomic piece.",
        f"<b>Retrying the same command: {sum(retries.values()):,} times within five minutes</b>, led by single test files "
        "(268), dt lua (129) and lua_run (115). Some are legitimate re-runs after an edit; the test ones follow "
        "a check_lua.sh run 215 times, which suggests the check's output does not show the failure well "
        "enough and the agent reruns one file to see it.",
        f"<b>Who is on the server: the single most repeated Lua chunk</b> (a loop over player.GetHumans, 31 times) "
        "because others share the dev server. A <font face='Courier'>dev.who()</font>, or the header above, "
        "answers it.",
        f"<b>Hooks and timers installed live: {intents.get('hooks / timers added', 0)} chunks</b> add a hook or a timer "
        "through lua_run, and nothing removes them when the task ends. The memory directory records the "
        "case (Oct 22): a wrapper the operator rejected was already live, threw every think and froze every "
        "NPC until found. A scoped form (a hook with a lifetime, cleared on the next reload) would make the "
        "habit safe.",
        f"<b>Five doors to one room</b>, used {lua_calls:,} times between them, and the newest sessions still mix "
        "them. Every door has its own quoting, its own instance flag and its own failure text, and each "
        "appears in the error list with a hook refusal or a shell quoting error.",
    ], st))
    H2("What the numbers say about the three tools")
    story.append(table([
        ["Tool", "Verdict", "Evidence"],
        ["gmod MCP", "The right door; half built out.",
         "1,787 lua_run calls and rising; breakpoints used three times, game events seven, watch never. "
         "Errors are mostly the server being down, which the MCP reports as a connection refusal rather than "
         "a state."],
        ["srcds.py", "Solid plumbing; its rule is not followed.",
         f"{starts} starts and stops, 'restart' in 59 operator prompts. The server goes down (crashes, benches, "
         "map changes) more than the rule assumes, and nothing tells the agent why or brings it back cleanly."],
        ["sandcastle_dev", "Under-used relative to its promise.",
         f"dev.reload {intents.get('dev.reload', 0)}, harness {intents.get('harness', 0)}, scenarios "
         f"{intents.get('scenario load/save', 0)}, dev.run {intents.get('dev.run', 0)} in three weeks, against "
         f"{intents.get('map change', 0)} map changes. The reload's refusals and the absence of saved scenarios "
         "for the common situations keep agents on the old path."],
    ], [1.1 * inch, 1.7 * inch, 3.8 * inch], st))
    story.append(Spacer(1, 6))
    H2("Ergonomic changes, in order of calls saved")
    story.extend(numbered([
        "<b>A status header on every MCP result</b> (map, humans, bots, round state, instance, last error count). "
        "Removes the which-map and who-is-on questions, about 500 calls.",
        "<b>lua_run returns the errors it raised</b>, and lua_errors defaults since to the caller's last read. "
        "Removes most of 279 error reads.",
        "<b>A wait tool</b>: <font face='Courier'>lua_wait(condition, timeout)</font> on the MCP, over Watch, and "
        "<font face='Courier'>instances.py --wait</font> for benches. Replaces the 2,187 shell loops.",
        "<b>Make reload cover sh_ files and hold the map on the dev server</b> (a <font face='Courier'>dev_hold_map"
        "</font> convar that sets the three limits after every load). Cuts into 415 map changes and 25 "
        "limit resets. The dev server's server.cfg is yours, not generated, and already forces gameplay and "
        "the AI war on every map; this would be one more line there, your call.",
        "<b>One door.</b> dt lua becomes a shell alias for the MCP's lua_run; server_lua.py and gmod_lua.py are "
        "retired for agents. One quoting rule, one error text, one log.",
        "<b>check_lua.sh prints each failing test's output</b>, so the rerun of a single file after a check "
        "stops being the habit.",
        "<b>A server-down state</b>: when the socket refuses, the MCP answers with when it went down and the "
        "last lines of the console log, and one <font face='Courier'>srcds_up</font> tool brings it back under "
        "the instance lock, so 'restart' stops being a prompt.",
        "<b>Scoped live hooks</b>: <font face='Courier'>dev.hook(name, fn, ttl)</font>, cleared on reload.",
    ], st))
    P("The script behind this section, transcript_toolkit.py, classifies by substring and over-counts in two "
      "places: a Bash command that edits a test with a heredoc and then runs it counts as a test run, and a "
      "command that mentions srcds.py in a sed or cat counts under srcds. The orders of magnitude hold.", "caption")

    # ---- section 9: inquiry and actions
    H1("9. Points of inquiry")
    P("Decisions that are yours, each of which changes what the cleanup does:")
    story.extend(numbered([
        "<b>Who is the folder for?</b> If it is for agents, then discoverability through an index and a "
        "skill is the first job and naming schemes matter more than depth. If it is for you, a deeper tree "
        "with READMEs serves better. The answer decides whether probes become workbench commands.",
        "<b>Should probes become workbench commands?</b> Moving 21 Lua scripts into addons/sandcastle_dev "
        "gives them an index, a test and in-game discovery, and ends their life in bin. It also makes the "
        "workbench larger and ties probes to the dev server's mount. Is that the right trade?",
        "<b>Should the Source format readers leave the repo?</b> They are the one body of code here with a "
        "second user (hammer-mcp). Leaving means a package to maintain; staying means duplicating them "
        "the next time.",
        "<b>Is the two-questions rule worth its cost?</b> Options: keep it unconditional; make it conditional "
        "(only when the change touches a file with more than N commits, or when the agent cannot find a "
        "design doc); replace it with a cheaper habit (\"dt rag/history files PATH\" before an edit, which "
        "is one call and always relevant). Which depends on whether you believe the searches have changed "
        "decisions, which the log cannot tell you.",
        "<b>Should the harness have a sunset rule?</b> For example: a tool nothing names and no commit "
        "touches for 30 days is listed for deletion in a weekly check, and the operator decides. A rule like "
        "that is the subtraction step the harness lacks.",
        "<b>How much should load every session?</b> The dev library index and the metamethods reference "
        "could move to on-demand skills, cutting 314 lines from every context. Is there a reason they need "
        "to be rules?",
    ], st))
    H2("Loose threads in the memory directory")
    P("The memory directory, 56 entries that load into every session, was read against the report. Four "
      "entries bear on it and two were stale:")
    story.extend(bullets([
        "<b>The roadmap entry still said game events v2 was next.</b> net2 shipped on Nov 10; the entry is "
        "updated now, and it is what closes the gev2 tools above.",
        "<b>The wartactics temporary-mount entry</b> asked for a link to be removed after instance 1's next "
        "restart. The link is already gone and server_root.py mounts wartactics as an addon; the entry is "
        "marked resolved. The pattern it records stands: a new addon needs a restart or a hand-made link on a "
        "running server, which is one of the reasons the no-restart rule is broken so often.",
        "<b>The Edit-tool feedback</b> (Oct 10 and 17) is the correction Section 7 shows not taking; the "
        "dev-server.cfg entry (\"ask before toggling\") is why the map-holding convar in Section 8 is your call.",
        "<b>The index itself is a second CLAUDE.md</b>: 56 one-line entries, several of them status notes "
        "(\"unchecked in game\", \"next\") that age like the folder did. It would benefit from the same sunset "
        "rule as the tools.",
    ], st))
    H1("10. Actionable steps")
    P("In an order that keeps the server and the checks working at each step:")
    story.extend(numbered([
        "<b>Commit rag-history</b> in claude-config2; it has been untracked for three weeks.",
        "<b>Delete the finished tools</b> (Section 2's list of eight) and the September in-game harness after "
        "confirming nothing in docs still prescribes it; add .pytest_cache to .gitignore.",
        "<b>Give devrag an outcome.</b> Add a <font face='Courier'>used</font> field to the log (the hit the "
        "agent then read, written by a <font face='Courier'>dt rag/history used ID</font> call the rule asks "
        "for), run the eval in a weekly check, and add cases from November's questions.",
        "<b>Sort bin into packages</b>: server/, check/, rooms/, with tests in .devtools/tests/ and a pytest "
        "configuration that finds them; the dt drawer keeps only wrappers. One Lua door: retire gmod_lua.py "
        "onto server_lua.py.",
        "<b>Move the probes into the workbench</b> as dev.* functions, one commit per probe, each with a line "
        "in the dev library index and so held by its test.",
        "<b>Create .devtools/experiments/</b> and move each bench with its artifacts and fixtures; amend the "
        "layout rule so an experiment has a home and an end. Keep results in main's tree: a worktree's "
        "artifacts die with the worktree, which is how the 15-map in-game report was lost on Oct 7.",
        "<b>Extract the Source readers</b> into a package in the claude-config2 drawer, and point nav_convert "
        "and hammer-mcp at it.",
        "<b>Merge the skills</b>: server-lua into dedicated-server; the dev library index into dev-workbench; "
        "lua-metamethods into glua-style's references. Then live-server.md is the one short rule.",
        "<b>Generate an index.</b> Every tool already carries a docstring or a dt-brief line; a check that "
        "writes .devtools/README.md from them, and fails when a tool has neither, makes the folder "
        "self-describing again, as the first commit intended.",
        "<b>Rename the collision</b>: pick one word for the project harness and one for the cross-project "
        "drawer, and update the layout rule and CLAUDE.md to match.",
        "<b>Ship the first three ergonomic changes of Section 8</b> (the status header, errors returned by "
        "lua_run, a wait tool) before the folder moves: they remove more calls than any reorganisation, and "
        "they are changes to one file, gmod_mcp.py.",
    ], st))
    # ---- section 10: the models and the codenames
    story.append(PageBreak())
    H1("11. Tengu, Fennec, Amber Flint, Mythos, Fable, Onyx Plover: using them properly")
    P("Six names, two kinds. Mythos and Fable are models Anthropic ships and documents. The other four are "
      "internal labels from Claude Code's own source, which was exposed in early 2026 and picked over by "
      "third parties; Anthropic has not confirmed what they mean, and the sources disagree on one of them. "
      "The table separates what is documented from what is inferred.")
    story.append(table([
        ["Name", "What it is", "Standing", "How it bears on this project"],
        ["Mythos (5.1, 5.2)", "The top tier of the Claude 5 family, served to verified organizations only.",
         "Documented", "Not available to this account. Fable is the same model with safeguards."],
        ["Fable (5, 5.1, 5.2)", "Mythos with Anthropic's dual-use safeguards, generally available. Fable 5.1 "
         "wrote this report; 5.2 is current and cheaper ($8/$40 per MTok).", "Documented",
         "The model for the architect role and for long autonomous runs; thinking is always on, depth is set "
         "by effort."],
        ["Tengu", "Claude Code's own codename; the prefix of its feature flags and telemetry events.",
         "Leaked, consistent across sources", "A name for the harness you are already using, not a thing to "
         "adopt."],
        ["Fennec", "An early codename for a 4.6-generation model. Sources split between Opus 4.6 and Sonnet 4.6.",
         "Leaked, disputed", "Nothing to use: the model shipped under its real name."],
        ["Amber Flint", "A Claude Code feature flag, reported as agent teams or agent swarms: several agents "
         "coordinated on one task.", "Leaked, inferred", "If it is what the sources say, it is the mechanism "
         "behind the subagents and the director already in your agent set."],
        ["Onyx Plover", "A Claude Code feature flag, reported as Auto Dream: background consolidation of memory.",
         "Leaked, inferred", "If so, it is the thing that would digest the memory directory on its own, which "
         "devrag and the memory index now do by hand."],
    ], [1.05 * inch, 2.25 * inch, 1.15 * inch, 2.15 * inch], st))
    story.append(Spacer(1, 6))
    H2("Using the models properly")
    story.extend(bullets([
        "<b>Pick the model by the role, and name it in the agent, not the prompt.</b> Your CLAUDE.md already "
        "says plans and prompts name a role, not a model. Put the model in each agent's frontmatter: Fable "
        "for architect and scholar, where judgment over a long context is the work; Opus 5.5 for programmer, "
        "the default and a fifth of Fable's price; Sonnet 5.5 or Haiku 5.5 for Explore and for subagents "
        "that read and report. A fork inherits the parent's model, so start a fork only from the model you "
        "want it on.",
        "<b>Tune effort before you reach for a bigger model.</b> On the Claude 5 models effort is the main "
        "control: start at high, step down to medium for routine work, and go to xhigh or max only where a "
        "measured gain shows. Lower effort on a newer model often beats high effort on an older one, and one "
        "model means one prompt cache.",
        "<b>Give Fable the whole task up front and let the turn run long.</b> Fable's turns are longer and it "
        "finishes what it is handed; prompts written for earlier models are usually too prescriptive and "
        "reduce its output. The rules in this repo are detailed by design; the audit in Section 7 suggests "
        "trimming what loads every session rather than adding to it.",
        "<b>Do not build on leaked flag names.</b> Tengu, Amber Flint and Onyx Plover are not stable "
        "interfaces. A flag can be renamed, removed or kept dark; nothing in your harness should depend on "
        "one. Where a leaked flag describes a feature you want (agent teams, memory consolidation), use the "
        "documented path: the Agent tool, the director agent, the memory directory and its index.",
        "<b>Expect refusals on Fable and handle them.</b> Fable's safeguards can decline a request mid-run "
        "(the <font face='Courier'>refusal</font> stop reason). In Claude Code that appears as a turn that "
        "stops; in API code include the server-side fallback. Most of this project's work (game AI, Lua, "
        "Source formats) is far from the guarded categories, but the binary-reversing tools "
        "(<font face='Courier'>pe_rtti</font>, <font face='Courier'>lua_glue</font>, "
        "<font face='Courier'>ice</font>) are the kind of thing to phrase carefully.",
    ], st))
    H2("Using them effectively, moving forward")
    P("The harness audit and the model question meet in one place: the cost of a session is the context it "
      "loads and the turns it burns, and both are set by you, not the model. Three moves pay regardless of "
      "which model runs:")
    story.extend(numbered([
        "<b>Match the agent set to the models' strengths, one priority at a time.</b> One Fable architect "
        "writing a plan with acceptance criteria, one or two Opus programmers implementing it, the architect "
        "evaluating: the shape your agents already describe, within the limit you set on Sep 30 of at most "
        "two agents on the current priority. Making the model explicit per agent, and measuring tasks "
        "completed per dollar across a week, would tell you whether the split is right.",
        "<b>Cut what every session loads, then let the model think.</b> 314 lines of rules plus the memory "
        "index plus CLAUDE.md's 400 lines arrive before the first word of the task. Fable and Opus 5.5 do "
        "better with the task stated once and the constraints discoverable on demand (skills) than with "
        "everything up front.",
        "<b>Make the harness measurable.</b> devrag's missing outcome field, the tools nothing names, the "
        "eval that stopped: each is a place where the harness could tell you whether it works and does not. "
        "Whatever the models are called next quarter, a harness that reports on itself is the one that adapts.",
    ], st))
    P("Sources for the codenames: the claude-code-secrets catalogue on GitHub (AKCodez), the "
      "claude-code-source-code analysis (sanbuphy), The Algorithmic Bridge's account of the exposure, and "
      "aivy.com.au's codename tracker. All are secondary readings of exposed source, not Anthropic "
      "statements.", "caption")
    P("The script that produced this report is itself a new file in bin, written there because the layout "
      "rule allows nowhere else. It is the first candidate for the experiments folder.", "caption")

    doc.build(story)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, default=REPO / ".devtools" / "artifacts" / f"devtools-report-{TODAY}.pdf")
    args = parser.parse_args()
    s = survey()
    r = rag_log()
    k = toolkit_log()
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        charts = {
            "growth": chart_growth(t / "growth.png"),
            "categories": chart_categories(t / "categories.png"),
            "hubs": chart_hubs(t / "hubs.png", s["importers"]),
            "status": chart_status(t / "status.png", s),
            "rag": chart_rag(t / "rag.png", r),
            "timeline": chart_timeline(t / "timeline.png"),
            "doors": chart_doors(t / "doors.png", k["weekly"]),
            "intents": chart_intents(t / "intents.png", k["intents"]),
        }
        args.out.parent.mkdir(parents=True, exist_ok=True)
        build(args.out, s, r, k, charts)
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
