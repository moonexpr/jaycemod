#!/usr/bin/env python3
"""Summarise a TF2 HUD .res layout: one line per control with its layout keys.

    hud_res.py FILE.res [CONTROL ...]

Keys with _minmode, _lodef or _hidef suffixes and [$X360] lines are left out;
nested conditional blocks (if_match, if_mvm, ...) are printed under their control
as "  if_x: key=value ...". Naming controls keeps only those (and their children).
"""
import re
import sys
from dataclasses import dataclass, field

KEYS = (
    "controlname", "xpos", "ypos", "zpos", "wide", "tall", "visible", "font", "image",
    "border", "fgcolor", "bgcolor", "fgcolor_override", "bgcolor_override", "labeltext",
    "textalignment", "scaleimage", "drawcolor", "alpha", "textinsetx", "paintbackground",
    "proportionaltoparent", "src_corner_width", "draw_corner_width", "image_name",
)
SKIP = re.compile(r"_(minmode|lodef|hidef)$")
TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|(\{)|(\})|(\[[^\]]*\])|([^\s"{}\[\]]+)')


@dataclass
class Node:
    name: str
    pairs: list = field(default_factory=list)
    children: list = field(default_factory=list)


def tokens(text):
    text = re.sub(r"//[^\n]*", "", text)
    for m in TOKEN.finditer(text):
        quoted, opening, closing, condition, bare = m.groups()
        if opening:
            yield "{", None
        elif closing:
            yield "}", None
        elif condition:
            yield "cond", condition
        else:
            yield "word", quoted if quoted is not None else bare


def parse(text):
    root = Node("<root>")
    stack, pending = [root], None
    stream = list(tokens(text))
    i = 0
    while i < len(stream):
        kind, value = stream[i]
        if kind == "word":
            nxt = stream[i + 1] if i + 1 < len(stream) else ("}", None)
            if nxt[0] == "cond" and i + 2 < len(stream) and stream[i + 2][0] == "{":
                node = Node(value)
                stack[-1].children.append(node)
                stack.append(node)
                i += 3
                continue
            if nxt[0] == "{":
                node = Node(value)
                stack[-1].children.append(node)
                stack.append(node)
                i += 2
                continue
            if nxt[0] == "word":
                cond = stream[i + 2][1] if i + 2 < len(stream) and stream[i + 2][0] == "cond" else ""
                if "X360" not in cond or "WIN32" in cond:
                    stack[-1].pairs.append((value, nxt[1]))
                i += 3 if cond else 2
                continue
        elif kind == "}":
            if len(stack) > 1:
                stack.pop()
        i += 1
    return root


def describe(node):
    seen = {}
    for key, value in node.pairs:
        low = key.lower()
        if SKIP.search(low) or low not in KEYS and low != "fieldname":
            continue
        if low == "fieldname":
            continue
        seen[low] = value
    return " ".join(f"{k}={v}" for k, v in seen.items())


def show(node, depth, wanted, out):
    for child in node.children:
        conditional = child.name.lower().startswith("if_")
        if wanted and depth == 0 and child.name not in wanted and not child.children:
            continue
        line = describe(child)
        if conditional:
            if line:
                out.append("  " * depth + f"{child.name}: {line}")
            continue
        out.append("  " * depth + f"{child.name}: {line}")
        show(child, depth + 1, None, out)


def main(argv):
    path, wanted = argv[1], set(argv[2:])
    root = parse(open(path, encoding="utf-8", errors="replace").read())
    top = root.children[0] if len(root.children) == 1 else root
    out = []
    for child in top.children:
        if wanted and child.name not in wanted:
            continue
        holder = Node("<one>", children=[child])
        show(holder, 0, None, out)
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv)
