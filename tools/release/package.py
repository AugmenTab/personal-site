"""Release packaging: exact-allowlist staging, inventory checks and hashes.

Run by scripts/release.sh inside the tools container (stdlib only):

  package.py check-dist --manifest M
      dist/ must hold exactly the manifest's files plus the generator's
      ownership marker, and every manifest path must be publishable.

  package.py stage --manifest M --meta KEY=VALUE ...
      Rebuilds .release/public from scratch: copies exactly the manifest's
      files from dist/ plus release/_headers, verifies the result, and
      writes .release/evidence/SHA256SUMS and release.json.

  package.py verify
      Re-hashes .release/public against .release/evidence/SHA256SUMS and
      checks the inventory is unchanged (used immediately before a deploy).

Nothing is inferred to be safe because it happens to be in a directory: the
allowlist is the generator's manifest (`site manifest`), and anything else
fails the run.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys

DIST = "dist"
PUBLIC = os.path.join(".release", "public")
EVIDENCE = os.path.join(".release", "evidence")
SUMS = os.path.join(EVIDENCE, "SHA256SUMS")
METADATA = os.path.join(EVIDENCE, "release.json")
OWNERSHIP_MARKER = ".personal-site-output"

# Provider-consumed files added by packaging (never produced by the
# generator, never served as ordinary assets). Source -> published name.
PROVIDER_FILES = {os.path.join("release", "_headers"): "_headers"}

# File types the site may publish. Anything else in the manifest is a
# packaging error, even if the generator produced it.
ALLOWED_EXTENSIONS = {
    ".html", ".css", ".js", ".svg", ".webp", ".png", ".jpg", ".jpeg", ".avif",
    ".woff2", ".txt", ".xml", ".pdf", ".ico",
}
# Source formats and local material that must never be uploaded, even if a
# future generator change listed them.
FORBIDDEN_EXTENSIONS = {
    ".md", ".markdown", ".json", ".yaml", ".yml", ".toml", ".hs", ".cabal",
    ".lock", ".env", ".sh", ".py", ".log", ".map", ".orig", ".bak", ".key", ".pem",
}
FORBIDDEN_SEGMENTS = {"content", ".git", ".stack-work", ".stack-root", ".local", ".release",
                      "node_modules", "design", "docker", "tools", "test", "src", "app"}
# Text that would reveal a build machine or a secret if it leaked into a
# published text file.
LEAK_MARKERS = ["/Users/", "/home/", "/stack-root", ".stack-work", "CLOUDFLARE_API_TOKEN",
                "BEGIN PRIVATE KEY", "BEGIN RSA PRIVATE KEY"]
TEXT_EXTENSIONS = {".html", ".css", ".js", ".svg", ".txt", ".xml"}


class PackageError(Exception):
    pass


def fail(problems):
    raise PackageError("\n".join(f"  - {p}" for p in problems))


def read_manifest(path):
    with open(path, encoding="utf-8") as fh:
        entries = [line.rstrip("\n") for line in fh if line.strip()]
    if not entries:
        fail([f"{path}: the manifest is empty"])
    if len(entries) != len(set(entries)):
        fail([f"{path}: duplicate entries"])
    return sorted(entries)


def path_problems(rel):
    """Reasons a manifest path may not be published (empty if fine)."""
    problems = []
    parts = rel.split("/")
    if rel.startswith("/") or "\\" in rel or any(p in ("", ".", "..") for p in parts):
        problems.append(f"{rel}: not a plain relative path")
    if any(p.startswith(".") for p in parts):
        problems.append(f"{rel}: hidden path component")
    if parts[0] in ("_headers", "_redirects", "_routes.json", "_worker.js"):
        problems.append(f"{rel}: provider-reserved name (only packaging adds provider files)")
    if any(p in FORBIDDEN_SEGMENTS for p in parts[:-1]):
        problems.append(f"{rel}: source or local directory")
    ext = os.path.splitext(rel)[1].lower()
    if ext in FORBIDDEN_EXTENSIONS:
        problems.append(f"{rel}: forbidden file type {ext}")
    elif ext not in ALLOWED_EXTENSIONS:
        problems.append(f"{rel}: file type {ext or '(none)'} is not on the publishable list")
    return problems


def inventory(root):
    """Every file and symlink under root, as sorted relative POSIX paths."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
            full = os.path.join(dirpath, name)
            found.append(os.path.relpath(full, root).replace(os.sep, "/"))
    return sorted(found)


def compare(label, actual, expected):
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    problems = [f"{label}: missing {m}" for m in missing] + [f"{label}: unexpected {e}" for e in extra]
    return problems


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def leak_problems(root, rel):
    if os.path.splitext(rel)[1].lower() not in TEXT_EXTENSIONS:
        return []
    with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    return [f"{rel}: contains {m!r}" for m in LEAK_MARKERS if m in text]


def check_dist(manifest):
    problems = [p for rel in manifest for p in path_problems(rel)]
    if not os.path.isfile(os.path.join(DIST, OWNERSHIP_MARKER)):
        problems.append(f"{DIST}/ has no ownership marker: it was not written by the generator")
    actual = inventory(DIST)
    problems += compare(f"{DIST}/", actual, manifest + [OWNERSHIP_MARKER])
    for rel in actual:
        if os.path.islink(os.path.join(DIST, rel)):
            problems.append(f"{DIST}/{rel}: symbolic link")
    if not problems:
        problems += [p for rel in manifest for p in leak_problems(DIST, rel)]
    if problems:
        fail(problems)
    print(f"dist/ matches the manifest: {len(manifest)} files plus the ownership marker (not published).")


def reset_public():
    # Only ever remove the staging directory itself, and only inside .release/.
    real = os.path.realpath(PUBLIC)
    if os.path.basename(real) != "public" or os.path.basename(os.path.dirname(real)) != ".release":
        fail([f"refusing to clear unexpected staging path {real}"])
    if os.path.islink(PUBLIC) or os.path.islink(".release"):
        fail(["refusing to stage through a symbolic link"])
    if os.path.exists(PUBLIC):
        shutil.rmtree(PUBLIC)
    os.makedirs(PUBLIC)
    os.makedirs(EVIDENCE, exist_ok=True)


def expected_public(manifest):
    return sorted(manifest + list(PROVIDER_FILES.values()))


def write_sums(entries):
    lines = [f"{sha256(os.path.join(PUBLIC, rel))}  {rel}\n" for rel in entries]
    with open(SUMS, "w", encoding="utf-8") as fh:
        fh.writelines(lines)
    return "".join(lines)


def stage(manifest, meta):
    check_dist(manifest)
    for src in PROVIDER_FILES:
        if not os.path.isfile(src):
            fail([f"{src} is missing"])
    reset_public()
    for rel in manifest:
        dest = os.path.join(PUBLIC, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(os.path.join(DIST, rel), dest)
    for src, name in PROVIDER_FILES.items():
        shutil.copyfile(src, os.path.join(PUBLIC, name))

    entries = expected_public(manifest)
    problems = compare(f"{PUBLIC}/", inventory(PUBLIC), entries)
    problems += [f"{rel}: copy differs from dist/" for rel in manifest
                 if sha256(os.path.join(PUBLIC, rel)) != sha256(os.path.join(DIST, rel))]
    if os.path.exists(os.path.join(PUBLIC, OWNERSHIP_MARKER)):
        problems.append("the ownership marker reached the public package")
    if problems:
        fail(problems)

    sums = write_sums(entries)
    sizes = {rel: os.path.getsize(os.path.join(PUBLIC, rel)) for rel in entries}
    metadata = {
        "package": {
            "directory": ".release/public",
            "fileCount": len(entries),
            "totalBytes": sum(sizes.values()),
            "digest": hashlib.sha256(sums.encode("utf-8")).hexdigest(),
            "providerFiles": sorted(PROVIDER_FILES.values()),
            "excluded": [OWNERSHIP_MARKER],
        },
        "files": [{"path": rel, "bytes": sizes[rel], "sha256": line.split("  ")[0]}
                  for rel, line in zip(entries, sums.splitlines())],
        "validation": [
            "haskell tests passed",
            "site check passed",
            "site built from a fresh generator run",
            "dist/ inventory equals the generator manifest plus the ownership marker",
            "every manifest path passed the publishable-path rules",
            "no build-machine paths or secret markers in text files",
            "public package equals the manifest plus provider files, byte for byte",
        ],
    }
    metadata.update(meta)
    with open(METADATA, "w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"Staged {len(entries)} files ({metadata['package']['totalBytes']} bytes) in {PUBLIC}/.")
    print(f"Package digest (SHA-256 of SHA256SUMS): {metadata['package']['digest']}")


def verify():
    if not os.path.isfile(SUMS) or not os.path.isfile(METADATA):
        fail(["no packaged release: run scripts/release.sh package first"])
    with open(SUMS, encoding="utf-8") as fh:
        sums = fh.read()
    expected = {}
    for line in sums.splitlines():
        digest, rel = line.split("  ", 1)
        expected[rel] = digest
    problems = compare(f"{PUBLIC}/", inventory(PUBLIC), sorted(expected))
    problems += [f"{rel}: content changed since packaging" for rel, digest in expected.items()
                 if os.path.isfile(os.path.join(PUBLIC, rel)) and sha256(os.path.join(PUBLIC, rel)) != digest]
    with open(METADATA, encoding="utf-8") as fh:
        metadata = json.load(fh)
    if metadata["package"]["digest"] != hashlib.sha256(sums.encode("utf-8")).hexdigest():
        problems.append("SHA256SUMS does not match the digest recorded in release.json")
    if problems:
        fail(problems)
    print(f"Package verified: {len(expected)} files, digest {metadata['package']['digest']}, "
          f"commit {metadata.get('commit', '?')}.")


def parse_meta(pairs):
    meta = {}
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep or not key:
            fail([f"bad --meta {pair!r} (expected KEY=VALUE)"])
        meta[key] = value
    return meta


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_check = sub.add_parser("check-dist")
    p_check.add_argument("--manifest", required=True)
    p_stage = sub.add_parser("stage")
    p_stage.add_argument("--manifest", required=True)
    p_stage.add_argument("--meta", action="append", default=[])
    sub.add_parser("verify")
    args = parser.parse_args(argv)
    try:
        if args.command == "check-dist":
            check_dist(read_manifest(args.manifest))
        elif args.command == "stage":
            stage(read_manifest(args.manifest), parse_meta(args.meta))
        else:
            verify()
    except PackageError as err:
        print(f"package: FAILED\n{err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
