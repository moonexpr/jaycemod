#!/usr/bin/env python3
"""Format Lua (GLua) the way notcake formats gcompute and glib.

    lua_format.py PATH...            rewrite each file (a folder: every .lua under it)
    lua_format.py --check PATH...    list the files it would change; exit 1 if any
    lua_format.py --diff PATH...     print what it would change
    lua_format.py -                  stdin to stdout

The rules, measured on gcompute's and glib's 670 files:

- Tabs indent, one per open block or bracket; a line's indent is set by the
  line that opened its block, so `foo (function ()` indents its body once.
- One space between a callee and its parentheses, and before an index:
  `self:Foo (x)`, `function self:ctor ()`, `self.Map [key]`. None inside
  `()` or `[]`; `{ a, b }` padded, `{}` empty.
- Binary operators, `=` and `..` spaced; `-`, `#` unary tight; `.` `:` tight.
- A multiline table opens on its own line and its last element has no comma:
      GLib.Enum (
          {
              Local  = 1,
              Remote = 2
          }
      )
- A run of assignments (or table fields) written with `=` aligned is kept
  aligned; trailing comments written aligned are kept aligned.
- Double quotes; `--` comments with a space; at most one blank line.
- No GMod syntax: `!=` `&&` `||` `!` `//` `/* */` become `~=` `and` `or`
  `not` `--` `--[[ ]]`. No `;` ending a line, no parentheses around a whole
  `if`/`while` condition.

Line breaks are the author's: it never joins or wraps lines.
"""
import argparse
import difflib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

KEYWORDS = frozenset(
    "and break do else elseif end false for function goto if in local nil not or repeat return then true until while"
    .split())
VALUE_KEYWORDS = frozenset({"true", "false", "nil", "end"})
BLOCK_OPENERS = frozenset({"function", "then", "do", "repeat"})
BRACKETS = {"(": ")", "[": "]", "{": "}"}
CLOSING_BRACKETS = {close: open for open, close in BRACKETS.items()}
BINARY = frozenset({"+", "-", "*", "/", "%", "^", "..", "==", "~=", "<", ">", "<=", ">=", "and", "or"})
GMOD_OPERATORS = {"!=": ("op", "~="), "&&": ("kw", "and"), "||": ("kw", "or"), "!": ("kw", "not")}
OPERATORS = ["...", "..", "==", "~=", "<=", ">=", "::", "!=", "&&", "||"] + list("+-*/%^#&~|<>=(){}[];:,.!")

NUMBER = re.compile(
    r"(?:0[xX][0-9a-fA-F]*(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)"
    r"(?:[uU]?[lL][lL]|[iI])?")
NAME = re.compile(r"[^\W\d]\w*")
LONG_OPEN = re.compile(r"\[(=*)\[")
INDENT = "\t"


class FormatError(Exception):
    """The source is not Lua this formatter can read; nothing is written."""


@dataclass
class Token:
    kind: str  # name kw num str long comment longcomment op nl
    text: str
    ws: str  # whitespace written before it on its line
    line: int | None
    unary: bool = False

    def is_op(self, *texts):
        return self.kind == "op" and self.text in texts

    def is_kw(self, *texts):
        return self.kind == "kw" and self.text in texts

    @property
    def is_code(self):
        return self.kind not in ("nl", "comment", "longcomment")

    @property
    def opens(self):
        return self.is_op(*BRACKETS) or self.is_kw(*BLOCK_OPENERS)

    @property
    def closes(self):
        return self.is_op(*CLOSING_BRACKETS) or self.is_kw("end", "until")


def long_level(body):
    """The `=` run that lets `body` sit between long brackets."""
    level = ""
    while f"]{level}]" in body:
        level += "="
    return level


def double_quoted(text):
    """A single-quoted string as a double-quoted one, or itself when it holds a double quote."""
    body, out, i = text[1:-1], [], 0
    while i < len(body):
        if body[i] == "\\":
            pair = body[i:i + 2]
            out.append("'" if pair == "\\'" else pair)
            i += 2
        elif body[i] == '"':
            return text
        else:
            out.append(body[i])
            i += 1
    return '"' + "".join(out) + '"'


def line_comment(text):
    text = text.rstrip()
    if len(text) > 2 and text[2] not in " \t-[":
        return "-- " + text[2:]
    return text


def tokenize(src):
    toks, i, n, ws, line = [], 0, len(src), "", 1

    def push(kind, text):
        nonlocal ws, line
        toks.append(Token(kind, text, ws, line))
        line += text.count("\n")
        ws = ""

    while i < n:
        c = src[i]
        if c in " \t\f\v":
            j = i
            while j < n and src[j] in " \t\f\v":
                j += 1
            ws, i = src[i:j], j
        elif c == "\r":
            i += 1
        elif c == "\n":
            push("nl", "\n")
            i += 1
        elif src.startswith("--", i):
            m = LONG_OPEN.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                end = src.find(close, m.end())
                if end < 0:
                    raise FormatError(f"{line}: unfinished long comment")
                push("longcomment", src[i:end + len(close)])
                i = end + len(close)
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
                push("comment", line_comment(src[i:end]))
                i = end
        elif src.startswith("//", i):
            end = src.find("\n", i)
            end = n if end < 0 else end
            push("comment", line_comment("--" + src[i + 2:end]))
            i = end
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            if end < 0:
                raise FormatError(f"{line}: unfinished /* comment")
            body = src[i + 2:end]
            level = long_level(body)
            push("longcomment", f"--[{level}[{body}]{level}]")
            i = end + 2
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\n":
                    raise FormatError(f"{line}: unfinished string")
                j += 2 if src[j] == "\\" else 1
            if j >= n:
                raise FormatError(f"{line}: unfinished string")
            text = src[i:j + 1]
            push("str", double_quoted(text) if c == "'" else text)
            i = j + 1
        elif c == "[" and LONG_OPEN.match(src, i):
            m = LONG_OPEN.match(src, i)
            close = "]" + m.group(1) + "]"
            end = src.find(close, m.end())
            if end < 0:
                raise FormatError(f"{line}: unfinished long string")
            push("long", src[i:end + len(close)])
            i = end + len(close)
        elif c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = NUMBER.match(src, i)
            push("num", m.group())
            i = m.end()
        elif m := NAME.match(src, i):
            word = m.group()
            push("kw" if word in KEYWORDS else "name", word)
            i = m.end()
        else:
            op = next((o for o in OPERATORS if src.startswith(o, i)), None)
            if op is None:
                raise FormatError(f"{line}: unexpected {c!r}")
            kind, text = GMOD_OPERATORS.get(op, ("op", op))
            push(kind, text)
            i += len(op)
    return toks


def pair_blocks(toks):
    """Each opener's index to its closer's and back; mismatched blocks are refused."""
    stack, pairs = [], {}
    for i, t in enumerate(toks):
        if t.is_op(*BRACKETS) or t.is_kw(*BLOCK_OPENERS):
            stack.append(i)
        elif t.is_op(*CLOSING_BRACKETS) or t.is_kw("end", "until", "else", "elseif"):
            if not stack:
                raise FormatError(f"{t.line}: {t.text} closes nothing")
            opener = toks[stack[-1]].text
            fits = {
                "end": opener in ("function", "then", "do", "else"),
                "until": opener == "repeat",
                "else": opener == "then",
                "elseif": opener == "then",
            }.get(t.text, CLOSING_BRACKETS.get(t.text) == opener)
            if not fits:
                raise FormatError(f"{t.line}: {t.text} closes {opener} from line {toks[stack[-1]].line}")
            j = stack.pop()
            pairs[i], pairs[j] = j, i
            if t.text == "else":
                stack.append(i)
    if stack:
        t = toks[stack[-1]]
        raise FormatError(f"{t.line}: {t.text} is never closed")
    return pairs


def next_code(toks, i, step=1):
    i += step
    while 0 <= i < len(toks) and not toks[i].is_code:
        i += step
    return i if 0 <= i < len(toks) else None


def line_numbers(toks):
    numbers, line = [], 0
    for t in toks:
        numbers.append(line)
        if t.kind == "nl":
            line += 1
    return numbers


def newline():
    return Token("nl", "\n", "", None)


def drop_semicolons(toks):
    """`;` between table fields becomes `,`; one ending a statement's line goes."""
    out, blocks = [], []
    for i, t in enumerate(toks):
        if t.opens:
            blocks.append(t.text)
        elif t.closes or t.is_kw("elseif"):
            blocks.pop()
        elif t.is_op(";"):
            if blocks and blocks[-1] == "{":
                t.text = ","
            else:
                after = i + 1
                while after < len(toks) and toks[after].kind in ("comment", "longcomment"):
                    after += 1
                ends_line = after == len(toks) or toks[after].kind == "nl"
                follower = next_code(toks, i)
                if follower is None or toks[follower].is_kw("end", "else", "elseif", "until"):
                    continue
                if ends_line and not toks[follower].is_op("("):
                    continue
        out.append(t)
    return out


def drop_condition_parens(toks):
    pairs, gone = pair_blocks(toks), set()
    for i, t in enumerate(toks):
        if not t.is_kw("if", "elseif", "while"):
            continue
        open_ = next_code(toks, i)
        if open_ is None or not toks[open_].is_op("("):
            continue
        close = pairs[open_]
        after = next_code(toks, close)
        if after is not None and toks[after].is_kw("then", "do"):
            gone.update((open_, close))
    return [t for i, t in enumerate(toks) if i not in gone]


def tables_on_own_lines(toks):
    """A `{` ending a line whose table closes on a later one moves to a line of its own."""
    pairs, lines, out = pair_blocks(toks), line_numbers(toks), []
    for i, t in enumerate(toks):
        moves = (t.is_op("{") and i > 0 and toks[i - 1].kind != "nl"
                 and i + 1 < len(toks) and toks[i + 1].kind == "nl" and lines[pairs[i]] != lines[i])
        if moves:
            out.append(newline())
        out.append(t)
    return out


def drop_trailing_separators(toks):
    gone = set()
    for i, t in enumerate(toks):
        if t.is_op("}"):
            before = next_code(toks, i, -1)
            if before is not None and toks[before].is_op(",", ";"):
                gone.add(before)
    return [t for i, t in enumerate(toks) if i not in gone]


def split_closers(toks):
    """Closers leading a line share it only when their openers shared one: `end)` stays, `})` splits."""
    pairs, lines, out = pair_blocks(toks), line_numbers(toks), []
    for i, t in enumerate(toks):
        start = line_start(toks, i)
        leading = start < i and all(toks[k].closes for k in range(start, i + 1))
        if leading and t.text != "until" and lines[pairs[i]] != lines[pairs[i - 1]]:
            out.append(newline())
        out.append(t)
    return out


def line_start(toks, i):
    while i > 0 and toks[i - 1].kind != "nl":
        i -= 1
    return i


def mark_unary(toks):
    prev = None
    for t in toks:
        if not t.is_code:
            continue
        if t.is_op("-", "#"):
            t.unary = t.text == "#" or prev is None or (
                prev.kind == "kw" and prev.text not in VALUE_KEYWORDS) or (
                prev.kind == "op" and prev.text not in (")", "]", "}", "..."))
        prev = t


def is_binary(t):
    return t is not None and not t.unary and (t.is_op(*BINARY) or t.is_kw("and", "or"))


def separator(before2, a, b):
    """The whitespace between tokens a and b on one line."""
    if b.kind in ("comment", "longcomment"):
        return b.ws or " "
    if a.is_op("(", "[") and b.kind == "long":
        return " "
    if a.unary:
        return " " if b.text.startswith("-") else ""
    if a.is_op("(", "[") or b.is_op(")", "]", ",", ";", ".", ":") or a.is_op(".", ":"):
        return ""
    if a.is_op("{"):
        return "" if b.is_op("}") else " "
    if a.is_op("::") and b.kind == "name":
        return ""
    if b.is_op("::") and a.kind == "name" and before2 is not None and before2.is_op("::"):
        return ""
    return " "


@dataclass
class Line:
    indent: int
    toks: list
    seps: list

    def text(self):
        if not self.toks:
            return ""
        body = "".join(sep + t.text for sep, t in zip(self.seps, self.toks))
        return INDENT * self.indent + body.rstrip(" \t")

    def width_to(self, index):
        return len("".join(sep + t.text for sep, t in zip(self.seps[:index], self.toks[:index])))

    def assignment(self):
        """The index of the `=` this line assigns with, if it is an assignment or table field."""
        first = self.toks[0]
        if first.kind == "kw" and first.text != "local" or first.closes or first.kind not in ("name", "kw", "op"):
            return None
        depth = 0
        for i, t in enumerate(self.toks):
            if t.is_op(*BRACKETS):
                depth += 1
            elif t.is_op(*CLOSING_BRACKETS):
                depth -= 1
            elif t.is_op("=") and depth == 0:
                return i if i > 0 else None
            elif t.kind == "kw" and t.text != "local" or t.opens:
                return None
        return None

    def trailing_comment(self):
        last = len(self.toks) - 1
        return last if last > 0 and self.toks[last].kind == "comment" else None


def indent_lines(toks):
    rows, row = [], []
    for t in toks:
        if t.kind == "nl":
            rows.append(row)
            row = []
        else:
            row.append(t)
    rows.append(row)

    lines, stack, prev_last, prev_depth = [], [], None, 0
    for row in rows:
        if not row:
            lines.append(Line(0, [], []))
            continue
        first = row[0]
        continued = 0
        if first.closes or first.is_kw("else", "elseif"):
            indent = stack[-1]
        else:
            indent = stack[-1] + 1 if stack else 0
            same_context = len(stack) == prev_depth
            if first.is_op(":", ".") or same_context and (
                    is_binary(first) or (is_binary(prev_last) and first.is_code)):
                continued = 1
        indent += continued
        depth_before = len(stack)
        for t in row:
            if t.is_op(*CLOSING_BRACKETS) or t.is_kw("end", "until", "elseif"):
                stack.pop()
            elif t.is_kw("else"):
                stack.append(stack.pop())
            if t.opens:
                stack.append(indent - continued if t.is_kw("then", "do") else indent)
        seps = [""] + [separator(row[k - 2] if k > 1 else None, row[k - 1], row[k]) for k in range(1, len(row))]
        lines.append(Line(indent, row, seps))
        code = [t for t in row if t.is_code]
        if code:
            prev_last, prev_depth = code[-1], depth_before
    return lines


def runs(lines, member):
    """Runs of consecutive lines at one indent that `member` admits."""
    run = []
    for line in lines:
        if line.toks and member(line) is not None and (not run or run[0].indent == line.indent):
            run.append(line)
            continue
        if len(run) > 1:
            yield run
        run = [line] if line.toks and member(line) is not None else []
    if len(run) > 1:
        yield run


def authored_aligned(ws):
    return "\t" in ws or len(ws) >= 2


def align(lines):
    for run in runs(lines, Line.assignment):
        if not any(authored_aligned(line.toks[line.assignment()].ws) for line in run):
            continue
        column = max(line.width_to(line.assignment()) for line in run)
        for line in run:
            i = line.assignment()
            line.seps[i] = " " * (column - line.width_to(i) + 1)
    for run in runs(lines, Line.trailing_comment):
        if not any(authored_aligned(line.toks[line.trailing_comment()].ws) for line in run):
            for line in run:
                line.seps[line.trailing_comment()] = " "
            continue
        column = max(line.width_to(line.trailing_comment()) for line in run)
        for line in run:
            i = line.trailing_comment()
            line.seps[i] = " " * (column - line.width_to(i) + 1)


def format_lua(src):
    toks = tokenize(src)
    pair_blocks(toks)
    shape = None
    while shape != [(t.kind, t.text) for t in toks]:
        shape = [(t.kind, t.text) for t in toks]
        for transform in (drop_semicolons, drop_condition_parens, tables_on_own_lines, drop_trailing_separators,
                          split_closers):
            toks = transform(toks)
    pair_blocks(toks)
    mark_unary(toks)
    lines = indent_lines(toks)
    align(lines)

    out, blank = [], False
    for line in lines:
        text = line.text()
        if not text:
            blank = bool(out)
            continue
        if blank:
            out.append("")
        out.append(text)
        blank = False
    return "\n".join(out) + "\n" if out else ""


def lua_files(paths):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.lua"))
        else:
            yield path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("paths", nargs="+", help="files or folders, or - for stdin")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="list files that would change; exit 1 if any")
    mode.add_argument("--diff", action="store_true", help="print the changes instead of writing them")
    args = parser.parse_args(argv)

    if args.paths == ["-"]:
        try:
            sys.stdout.write(format_lua(sys.stdin.read()))
        except FormatError as e:
            print(f"<stdin>:{e}", file=sys.stderr)
            return 2
        return 0

    changed, failed = 0, 0
    for path in lua_files(Path(p) for p in args.paths):
        src = path.read_text(encoding="utf-8", errors="surrogateescape")
        try:
            formatted = format_lua(src)
        except FormatError as e:
            print(f"{path}:{e}", file=sys.stderr)
            failed += 1
            continue
        if formatted == src:
            continue
        changed += 1
        if args.check:
            print(path)
        elif args.diff:
            sys.stdout.writelines(difflib.unified_diff(
                src.splitlines(keepends=True), formatted.splitlines(keepends=True), str(path), str(path)))
        else:
            path.write_text(formatted, encoding="utf-8", errors="surrogateescape")
    if failed:
        return 2
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    sys.exit(main())
