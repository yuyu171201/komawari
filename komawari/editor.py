"""timetable.yaml の例外を1行単位で追加・削除する。

YAML 全体を書き直すとコメントや並びが失われるので、`exceptions:` の中の該当行だけを
足し引きし、それ以外の行には触れない。書き込む前に全体を検証し、不正なら何も変えない。
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterable
from datetime import date
from pathlib import Path

import yaml

from .config import ConfigError, _Loader, entry_id, normalize_exception, parse_text

MARKER = "# 週ビューから登録した変更"

_BLOCK_START = re.compile(r"^exceptions:\s*(#.*)?$")
_FLOW_ENTRY = re.compile(r"^\s*-\s*\{.*\}\s*(#.*)?$")


class _Dumper(yaml.SafeDumper):
    """読み込み側と同じ規則で引用符を付ける（`off` キーを引用符なしで書くため）。"""


_Dumper.yaml_implicit_resolvers = _Loader.yaml_implicit_resolvers


def edit_exceptions(
    path: str | Path, *, add: Iterable[dict] = (), remove: Iterable[str] = ()
) -> list[dict]:
    """例外を削除（id 指定）してから追加し、追加した例外を正規化した形で返す。

    削除と追加はまとめて検証・書き込みするので、途中まで反映されることはない。
    """
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    cfg = parse_text(text)
    lines = text.splitlines()

    for target in remove:
        _remove_line(lines, target, cfg)

    added = [normalize_exception(raw, cfg.periods, "追加する変更") for raw in add]
    for entry in added:
        _insert_line(lines, entry)

    new_text = "\n".join(lines) + "\n"
    parse_text(new_text)
    _write_atomically(path, new_text)
    return added


def _block(lines: list[str]) -> tuple[int, int] | None:
    """`exceptions:` の行番号と、その中身の終わり（次の行番号）を返す。無ければ None。"""
    start = next((i for i, line in enumerate(lines) if _BLOCK_START.match(line)), None)
    if start is None:
        if any(line.startswith("exceptions:") for line in lines):
            raise ConfigError("`exceptions:` が1行で書かれているため編集できません")
        return None

    end = start + 1
    while end < len(lines) and (not lines[end].strip() or lines[end][0] in " \t#-"):
        end += 1
    # 次のキーの直前にある空行や行頭コメントは、次のキーの側のものとして残す
    followed = end < len(lines)
    while end > start + 1 and (
        not lines[end - 1].strip() or (followed and lines[end - 1].startswith("#"))
    ):
        end -= 1
    return start, end


def _remove_line(lines: list[str], target: str, cfg) -> None:
    block = _block(lines)
    start, end = block if block else (0, 0)
    for i in range(start + 1, end):
        if not _FLOW_ENTRY.match(lines[i]):
            continue
        try:
            (raw,) = yaml.load(lines[i], Loader=_Loader)
            found = entry_id(normalize_exception(raw, cfg.periods))
        except (ConfigError, yaml.YAMLError, TypeError, ValueError):
            continue
        if found == target:
            del lines[i]
            return

    known = {entry_id(e) for exc in cfg.exceptions.values() for e in exc.entries}
    if target in known:
        raise ConfigError("この変更は複数行で書かれているため、YAML を直接編集してください")
    raise LookupError(target)


def _insert_line(lines: list[str], entry: dict) -> None:
    line = "- " + _flow(entry)
    block = _block(lines)
    if block is None:
        lines += ["", "exceptions:", f"  {MARKER}", f"  {line}"]
        return

    start, end = block
    indent = next(
        (l[: len(l) - len(l.lstrip())] for l in lines[start + 1 : end] if l.lstrip().startswith("-")),
        "  ",
    )
    marker = next((i for i in range(start + 1, end) if lines[i].strip() == MARKER), None)
    if marker is None:
        lines[end:end] = ["", indent + MARKER, indent + line]
        return
    # 目印のコメントに続く行のかたまりの末尾に足す
    at = marker + 1
    while at < end and lines[at].strip():
        at += 1
    lines.insert(at, indent + line)


def _flow(entry: dict) -> str:
    """正規化した例外を、YAML の1行（フロー形式）にする。"""
    data = {**entry, "date": date.fromisoformat(entry["date"])}
    text = yaml.dump(
        data,
        Dumper=_Dumper,
        default_flow_style=True,
        allow_unicode=True,
        sort_keys=False,
        width=float("inf"),
    )
    return text.strip()


def _write_atomically(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)
