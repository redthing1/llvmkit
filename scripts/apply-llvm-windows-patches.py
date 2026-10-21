#!/usr/bin/env python3
"""Apply checked, idempotent text hunks without requiring Git or patch on Windows."""
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).resolve()
patches = pathlib.Path(sys.argv[2])
for patch in sorted(patches.glob("*.patch")):
    lines = patch.read_text(encoding="utf-8").splitlines(keepends=True)
    path = None
    hunks = []
    old, new = [], []
    in_hunk = False
    for line in lines:
        if line.startswith("--- a/"):
            if path is not None:
                raise RuntimeError("Use one source file per patch: " + str(patch))
            path = source / line[6:].strip()
            path.resolve().relative_to(source)
        elif line.startswith("+++ b/"):
            if path != source / line[6:].strip():
                raise RuntimeError("Renames are unsupported: " + str(patch))
        elif line.startswith("@@ "):
            if in_hunk:
                hunks.append(("".join(old), "".join(new)))
            old, new, in_hunk = [], [], True
        elif in_hunk and line[:1] in (" ", "-", "+"):
            if line[0] in " -":
                old.append(line[1:])
            if line[0] in " +":
                new.append(line[1:])
        else:
            raise RuntimeError("Unsupported patch syntax: " + str(patch))
    if in_hunk:
        hunks.append(("".join(old), "".join(new)))
    if path is None or not hunks:
        raise RuntimeError("Empty patch: " + str(patch))
    text = path.read_text(encoding="utf-8")
    original = text
    for before, after in hunks:
        if not before or not after:
            raise RuntimeError("Whole-file changes are unsupported: " + str(patch))
        if text.count(before) == 1:
            text = text.replace(before, after, 1)
        elif text.count(after) != 1:
            raise RuntimeError("Patch context differs from pinned LLVM source: " + str(patch))
    if text != original:
        with path.open("w", encoding="utf-8", newline="\n") as output:
            output.write(text)
    print(patch.name + (": applied" if text != original else ": already applied"))
