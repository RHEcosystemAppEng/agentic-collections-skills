#!/usr/bin/env python3
"""
Validate markdown link integrity for runtime-adjacent docs trees.

Scope:
- skills/*/docs/**/*.md
- <pack>/README.md
- <pack>/.catalog/*.md

Checks:
- local markdown link targets exist
- symlink targets resolve
- no symlink loops
- resolved targets do not escape pack root
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Iterable

DEFAULT_PACKS = [
    "rh-sre",
    "rh-developer",
    "ocp-admin",
    "rh-virt",
    "rh-ai-engineer",
    "rh-automation",
]

MD_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def is_external(target: str) -> bool:
    lower = target.lower()
    return (
        lower.startswith("http://")
        or lower.startswith("https://")
        or lower.startswith("mailto:")
        or lower.startswith("#")
    )


def resolve_packs(paths: Iterable[str]) -> set[Path]:
    packs: set[Path] = set()
    for p in paths:
        path = Path(p)
        if path.is_file():
            if path.name == "SKILL.md" and path.parent.parent.name == "skills":
                packs.add(path.parent.parent.parent.resolve())
            elif path.name.endswith(".md"):
                # If file belongs to a pack directory, infer it.
                parts = path.resolve().parts
                if "skills" in parts:
                    idx = parts.index("skills")
                    packs.add(Path(*parts[:idx]).resolve())
            continue
        if path.is_dir():
            if (path / "skills").exists():
                packs.add(path.resolve())
                continue
            # Maybe path is pack name that exists in cwd
            if (Path.cwd() / path / "skills").exists():
                packs.add((Path.cwd() / path).resolve())
    return packs


def scan_targets(pack_root: Path) -> list[Path]:
    targets: list[Path] = []
    targets.extend(sorted((pack_root / "skills").glob("*/docs/**/*.md")))
    readme = pack_root / "README.md"
    if readme.exists():
        targets.append(readme)
    catalog = pack_root / ".catalog"
    if catalog.exists():
        targets.extend(sorted(catalog.glob("*.md")))
    return targets


def validate_file(path: Path, pack_root: Path) -> list[str]:
    errs: list[str] = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    is_skill_docs = "/skills/" in path.as_posix() and "/docs/" in path.as_posix()
    is_pack_meta = (path == (pack_root / "README.md")) or (path.parent == (pack_root / ".catalog"))
    for line_no, line in enumerate(text.splitlines(), start=1):
        for m in MD_LINK_RE.finditer(line):
            raw = m.group(1).strip()
            if is_external(raw):
                continue
            base = raw.split("#", 1)[0].strip()
            if not base.endswith(".md"):
                continue

            # For pack README / catalog fragments, validate only pack-local docs references.
            if is_pack_meta:
                if not (base.startswith("docs/") or base.startswith("skills/")):
                    continue
                link_path = (pack_root / base)
            else:
                link_path = (path.parent / base)
            try:
                resolved = link_path.resolve(strict=True)
            except FileNotFoundError:
                errs.append(f"{path}:{line_no}: missing linked doc '{raw}'")
                continue
            except RuntimeError:
                errs.append(f"{path}:{line_no}: symlink loop for '{raw}'")
                continue

            if is_skill_docs:
                try:
                    resolved.relative_to(pack_root)
                except ValueError:
                    errs.append(
                        f"{path}:{line_no}: link escapes pack root '{raw}' -> '{resolved}'"
                    )

            if link_path.is_symlink():
                raw_link = os.readlink(link_path)
                immediate = (
                    link_path.parent / raw_link
                    if not os.path.isabs(raw_link)
                    else Path(raw_link)
                )
                if immediate.is_symlink():
                    errs.append(
                        f"{path}:{line_no}: symlink chain detected for '{raw}'"
                    )
    return errs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate markdown links in skills docs trees, pack README, and catalog fragments"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        default=DEFAULT_PACKS,
        help="Pack directories or SKILL.md paths",
    )
    parser.add_argument("--json-out", help="Optional JSON summary output path")
    args = parser.parse_args()

    packs = resolve_packs(args.paths)
    if not packs:
        packs = {Path(p).resolve() for p in DEFAULT_PACKS if (Path(p) / "skills").exists()}

    all_errors: list[str] = []
    scanned_files = 0
    for pack in sorted(packs):
        for f in scan_targets(pack):
            scanned_files += 1
            all_errors.extend(validate_file(f, pack))

    summary = {
        "packs_scanned": len(packs),
        "files_scanned": scanned_files,
        "error_count": len(all_errors),
    }

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps({"summary": summary, "errors": all_errors}, indent=2),
            encoding="utf-8",
        )

    if all_errors:
        print("❌ Docs tree link validation failed:")
        for err in all_errors:
            print(f"  • {err}")
        print(json.dumps(summary, indent=2))
        return 1

    print("✅ Docs tree links validated successfully")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
