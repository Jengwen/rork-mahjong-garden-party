#!/usr/bin/env python3
"""Generate web/src/engine/cards.generated.ts from the iOS NMJL card source.

The iOS file (ios/MahjongGardenParty/Models/NMJLCard2025.swift) is the single
source of truth for hand patterns. Re-run this whenever it changes:

    python3 web/scripts/convert-card.py

Hand ORDER is preserved exactly, because HandMatcher.checkWin returns the first
matching hand and bot target selection breaks ties by first occurrence.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "ios/MahjongGardenParty/Models/NMJLCard2025.swift"
OUT = ROOT / "web/src/engine/cards.generated.ts"

SUITS = {"bamboo": "Bamboo", "character": "Character", "dot": "Dot"}


def balanced(text: str, start: int, open_ch: str, close_ch: str) -> int:
    """Return index just past the bracket matching text[start] (== open_ch)."""
    depth = 0
    i = start
    in_str = False
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError(f"unbalanced {open_ch} at {start}")


def ev(expr: str, env: dict) -> int:
    expr = expr.strip()
    if not re.fullmatch(r"[\w\s+\-*]+", expr):
        raise ValueError(f"unsupported expression: {expr}")
    return int(eval(expr, {"__builtins__": {}}, env))


def parse_tile(spec: str, env: dict) -> dict:
    m = re.fullmatch(r"\.(\w+)(?:\((.*)\))?", spec.strip(), re.S)
    if not m:
        raise ValueError(f"bad tile spec {spec}")
    kind, args = m.group(1), (m.group(2) or "")
    kv = {}
    # allowedValues: [2, 4, 6, 8]
    av = re.search(r"allowedValues:\s*\[([^\]]*)\]", args)
    ar = re.search(r"allowedValues:\s*Array\((\d+)\.\.\.(\d+)\)", args)
    if av:
        kv["allowedValues"] = [ev(x, env) for x in av.group(1).split(",") if x.strip()]
        args = args[: av.start()] + args[av.end():]
    elif ar:
        kv["allowedValues"] = list(range(int(ar.group(1)), int(ar.group(2)) + 1))
        args = args[: ar.start()] + args[ar.end():]
    for part in args.split(","):
        if ":" not in part:
            continue
        k, v = part.split(":", 1)
        k, v = k.strip(), v.strip()
        if k == "suit":
            kv["suit"] = SUITS[v.lstrip(".")]
        else:
            kv[k] = ev(v, env)
    out = {"k": kind}
    out.update(kv)
    return out


def parse_hand(body: str, env: dict) -> dict:
    def interp(s: str) -> str:
        return re.sub(r"\\\((\w+)\)", lambda m: str(env[m.group(1)]), s)

    def field(name: str):
        m = re.search(rf"\b{name}:\s*\"((?:[^\"\\]|\\.)*)\"", body)
        return interp(m.group(1)) if m else None

    groups = []
    for gm in re.finditer(r"HandGroup\(count:\s*([^,]+),\s*tile:\s*", body):
        tstart = gm.end()
        # tile spec runs to the matching close of HandGroup(
        hg_open = body.rfind("(", 0, gm.start() + len("HandGroup("))
        hg_end = balanced(body, hg_open, "(", ")")
        spec = body[tstart: hg_end - 1]
        groups.append({"count": ev(gm.group(1), env), "tile": parse_tile(spec, env)})

    pts = re.search(r"\bpoints:\s*([^,\n]+)", body)
    conc = re.search(r"\bconcealed:\s*(true|false)", body)
    uniq = re.search(r"\brequireUniqueSuits:\s*(true|false)", body)
    hand = {
        "id": field("id"),
        "category": field("category"),
        "name": field("name"),
        "groups": groups,
        "points": ev(pts.group(1), env),
        "concealed": conc.group(1) == "true",
    }
    if uniq and uniq.group(1) == "true":
        hand["requireUniqueSuits"] = True
    return hand


def hands_in(text: str, env: dict) -> list:
    out = []
    for m in re.finditer(r"NMJLHand\(", text):
        start = m.end() - 1
        end = balanced(text, start, "(", ")")
        out.append(parse_hand(text[start + 1: end - 1], env))
    return out


def parse_expr(expr: str, arrays: dict) -> list:
    result = []
    i = 0
    expr = expr.strip()
    while i < len(expr):
        c = expr[i]
        if c.isspace() or c == "+":
            i += 1
            continue
        if c == "[":
            end = balanced(expr, i, "[", "]")
            result += hands_in(expr[i:end], {})
            i = end
            continue
        m = re.match(r"\((\d+)\.\.\.(\d+)\)\.map\s*\{\s*(\w+)\s+in", expr[i:])
        if m:
            brace = expr.index("{", i)
            end = balanced(expr, brace, "{", "}")
            inner = expr[brace:end]
            lo, hi, var = int(m.group(1)), int(m.group(2)), m.group(3)
            for v in range(lo, hi + 1):
                result += hands_in(inner, {var: v})
            i = end
            continue
        m = re.match(r"\w+", expr[i:])
        if m:
            name = m.group(0)
            if name not in arrays:
                raise KeyError(f"unknown array {name}")
            result += arrays[name]
            i += len(name)
            continue
        raise ValueError(f"cannot parse near: {expr[i:i+40]!r}")
    return result


def main() -> None:
    src = SRC.read_text()
    arrays: dict = {}
    decl = re.compile(r"(?:private\s+)?static let (\w+):\s*\[NMJLHand\]\s*=\s*")
    for m in decl.finditer(src):
        start = m.end()
        nxt = re.compile(r"\n\s*(?:private\s+)?static (?:let|func)|\n\s*// MARK").search(src, start)
        expr = src[start: nxt.start() if nxt else len(src)]
        arrays[m.group(1)] = parse_expr(expr, arrays)

    cards = {}
    for m in re.finditer(r"static let (card\d+) = NMJLCard\(", src):
        end = balanced(src, m.end() - 1, "(", ")")
        block = src[m.end() - 1: end]
        year = re.search(r"year:\s*\.year(\d+)", block).group(1)
        hm = re.search(r"hands:\s*([^\n]+)", block).group(1)
        hands = parse_expr(hm, arrays)
        ids = [h["id"] for h in hands]
        if len(ids) != len(set(ids)):
            dupes = sorted({x for x in ids if ids.count(x) > 1})
            print(f"warning: duplicate hand ids in {year}: {dupes}", file=sys.stderr)
        cards[year] = hands

    lines = [
        "// AUTO-GENERATED by web/scripts/convert-card.py from",
        "// ios/MahjongGardenParty/Models/NMJLCard2025.swift — do not edit by hand.",
        "import type { NMJLHand } from './types';",
        "",
    ]
    for year, hands in cards.items():
        lines.append(f"export const HANDS_{year}: NMJLHand[] = {json.dumps(hands, separators=(',', ':'))} as NMJLHand[];")
        lines.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines))
    for year, hands in cards.items():
        print(f"{year}: {len(hands)} hands, {sum(len(h['groups']) for h in hands)} groups")


if __name__ == "__main__":
    main()
