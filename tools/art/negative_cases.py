"""Write broken copies of the source tree for Phase 05 negative-case evidence.

    docker compose --profile tools run --rm art python3 tools/art/negative_cases.py
    docker compose run --rm site-build stack exec -- site check --root .local/negative/CASE

Each case under .local/negative/ (git-ignored) is a copy of content/ and
assets/ with exactly one deliberate problem; `site check` must reject it
with a clear message. The repository's content/ is never touched.
"""

import json
import os
import shutil
import sys

from common import chown_like_work

ROOT = ".local/negative"


def edit_project(case, slug, change):
    path = f"{ROOT}/{case}/content/projects/{slug}/project.json"
    with open(path) as f:
        meta = json.load(f)
    change(meta)
    with open(path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")


def write(case, rel, data):
    path = f"{ROOT}/{case}/{rel}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


CASES = {
    "legacy-category": lambda c: edit_project(c, "brigid", lambda m: m.update(category="Haskell library")),
    "unknown-topic": lambda c: edit_project(c, "black", lambda m: m.update(topics=["type-systems", "type-sytems"])),
    "duplicate-topic": lambda c: edit_project(c, "paranoia-engine", lambda m: m.update(topics=["game-engines", "game-engines"])),
    "misfiled-technology": lambda c: edit_project(c, "black", lambda m: m.update(technologies=["Haskell", "Type systems"])),
    "duplicate-technology": lambda c: edit_project(c, "brigid", lambda m: m.update(technologies=["Haskell", "haskell"])),
    "resume-not-pdf": lambda c: write(c, "content/resume.pdf", b"<html>this is not a PDF</html>\n"),
    "missing-script": lambda c: os.remove(f"{ROOT}/{c}/assets/scripts/work-filter.js"),
    # post-Phase 05 remediation
    "impossible-date": lambda c: write(c, "content/writing/fixture/article.json", json.dumps({
        "slug": "fixture", "title": "Fixture", "summary": "A fixture.", "publication_status": "published",
        "date": "2026-02-31", "body": "body.md"}).encode()) or write(c, "content/writing/fixture/body.md", b"Text.\n"),
    "handler-like-summary": lambda c: edit_project(c, "brigid", lambda m: m.update(summary='description" onerror="alert(1)')),
}

# Cases that must pass `site check` (positive controls for the remediation).
ACCEPTED = {
    "quoted-summary": lambda c: edit_project(c, "brigid", lambda m: m.update(summary='A "correctness-first" programming language.')),
}


def main() -> int:
    shutil.rmtree(ROOT, ignore_errors=True)
    for case, breakit in {**CASES, **ACCEPTED}.items():
        for name in ("content", "assets"):
            shutil.copytree(name, f"{ROOT}/{case}/{name}", symlinks=False)
        breakit(case)
        print(f"{ROOT}/{case}")
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        chown_like_work(dirpath, *(os.path.join(dirpath, n) for n in filenames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
