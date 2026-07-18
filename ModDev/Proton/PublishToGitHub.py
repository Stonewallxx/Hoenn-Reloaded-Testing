#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

REPO_RAW = "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded-Mods/main"
BLOCKED_EXTENSIONS = {".exe", ".dll", ".bat", ".cmd", ".ps1", ".vbs", ".js", ".jar", ".msi", ".scr", ".com"}


def read_json(path):
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=True)
        handle.write("\n")


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_id(value):
    return re.sub(r"^_+|_+$", "", re.sub(r"[^a-z0-9_]+", "_", str(value).strip().lower()))


def version_ok(value):
    return bool(re.fullmatch(r"\d+\.\d+\.\d+", str(value)))


def choose(label, rows):
    print(f"\n{label}")
    for index, row in enumerate(rows, 1):
        print(f"  {index}. {row[0]}")
    print("  0. Cancel")
    try:
        selected = int(input("Choice: ").strip())
    except ValueError:
        raise RuntimeError("Invalid selection.")
    if selected == 0:
        raise KeyboardInterrupt
    if selected < 1 or selected > len(rows):
        raise RuntimeError("Invalid selection.")
    return rows[selected - 1][1]


def load_index(repo):
    path = repo / "index.json"
    data = read_json(path) if path.exists() else {"version": 1, "mods": [], "profiles": []}
    if isinstance(data, list):
        data = {"version": 1, "mods": data, "profiles": []}
    data.setdefault("mods", [])
    data.setdefault("profiles", [])
    return data


def set_sparse_path(repo, target):
    import subprocess
    subprocess.run(["git", "-C", str(repo), "sparse-checkout", "set", "--no-cone", "/index.json", target], check=True)


def publish_mod(game, repo, index):
    choices = []
    for root_name in ("Mods", "ModDev"):
        root = game / root_name
        if not root.is_dir():
            continue
        for manifest_path in sorted(root.glob("*/mod.json")):
            data = read_json(manifest_path)
            choices.append((f"{data.get('name', manifest_path.parent.name)} v{data.get('version', '?')} [{root_name}]", (manifest_path.parent, data)))
    folder, manifest = choose("Mods available to publish:", choices)
    mod_id = normalized_id(manifest.get("id", ""))
    version = str(manifest.get("version", ""))
    if not mod_id or not manifest.get("name") or not version_ok(version):
        raise RuntimeError("The selected mod has an invalid id, name, or version.")
    blocked = [path for path in folder.rglob("*") if path.is_file() and path.suffix.lower() in BLOCKED_EXTENSIONS]
    if blocked:
        raise RuntimeError(f"Blocked file type found: {blocked[0].relative_to(folder)}")
    if input(f"Publish {manifest['name']} v{version}? (Y/N): ").strip().lower() != "y":
        raise KeyboardInterrupt

    target_sparse = f"/Mods/{mod_id}/"
    set_sparse_path(repo, target_sparse)
    target_dir = repo / "Mods" / mod_id
    target_dir.mkdir(parents=True, exist_ok=True)
    archive = target_dir / f"{mod_id}_{version}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                output.write(path, Path(folder.name) / path.relative_to(folder))
    archive_sha256 = sha256_file(archive)
    archive_size = archive.stat().st_size

    versions = []
    for entry in index["mods"]:
        if normalized_id(entry.get("id", entry.get("uid", ""))) == mod_id:
            versions = [row for row in entry.get("versions", []) if str(row.get("version")) != version]
            break
    versions.append({
        "version": version,
        "download_url": f"{REPO_RAW}/Mods/{mod_id}/{archive.name}",
        "sha256": archive_sha256,
        "size": archive_size,
        "reloaded_version": (game / "Reloaded" / "Version.md").read_text(encoding="utf-8-sig").strip(),
        "changelog": "",
        "changelogurl": str(manifest.get("changelogurl", "")),
        "dependencies": manifest.get("dependencies", []),
    })
    entry = {
        "id": mod_id,
        "name": manifest["name"],
        "latest_version": version,
        "authors": manifest.get("authors", []),
        "description": manifest.get("description", ""),
        "tags": manifest.get("tags", []),
        "dependencies": manifest.get("dependencies", []),
        "changelogurl": manifest.get("changelogurl", ""),
        "versions": versions,
    }
    index["mods"] = [row for row in index["mods"] if normalized_id(row.get("id", row.get("uid", ""))) != mod_id] + [entry]
    return f"Publish {mod_id} v{version}"


def publish_profile(game, repo, index):
    profile_root = game / "Mods" / "Reloaded" / "Profiles"
    choices = []
    for path in sorted(profile_root.glob("*.json")):
        profile = read_json(path)
        choices.append((profile.get("name", path.stem), (path, profile)))
    path, profile = choose("Profiles available to publish:", choices)
    profile_id = normalized_id(profile.get("id") or profile.get("name", ""))
    if not profile_id:
        raise RuntimeError("The selected profile has an invalid id or name.")
    old = next((row for row in index["profiles"] if normalized_id(row.get("id", "")) == profile_id), None)
    previous = str(old.get("version", "")) if old else ""
    if version_ok(previous):
        major, minor, patch = map(int, previous.split("."))
        version = f"{major}.{minor}.{patch + 1}"
    else:
        version = "1.0.0"
    if input(f"Publish {profile.get('name', profile_id)} v{version}? (Y/N): ").strip().lower() != "y":
        raise KeyboardInterrupt

    target_sparse = f"/Profiles/{profile_id}/"
    set_sparse_path(repo, target_sparse)
    target_dir = repo / "Profiles" / profile_id
    target_dir.mkdir(parents=True, exist_ok=True)
    payload_path = target_dir / f"{profile_id}_{version}.json"
    manifests = {}
    for root_name in ("Mods", "ModDev"):
        for manifest_path in (game / root_name).glob("*/mod.json"):
            manifest = read_json(manifest_path)
            mod_id = normalized_id(manifest.get("id", ""))
            if mod_id:
                manifests[mod_id] = manifest
    referenced = []
    for key in ("enabled_mods", "disabled_mods", "load_order"):
        referenced.extend(profile.get(key, []) or [])
    settings = profile.get("mod_settings", {}) or {}
    if isinstance(settings, dict):
        referenced.extend(settings.keys())
    referenced = sorted({normalized_id(value) for value in referenced if normalized_id(value)})
    missing = [mod_id for mod_id in referenced if mod_id not in manifests]
    if missing:
        raise RuntimeError("Profile references missing mods: " + ", ".join(missing))
    mods = [{"id": mod_id, "version": str(manifests[mod_id].get("version", ""))} for mod_id in referenced]
    if not mods:
        raise RuntimeError("Profile does not reference any mods.")
    payload = {
        "format": "RLD-code",
        "version": 1,
        "preset_name": profile.get("name", profile_id),
        "reloaded_version": (game / "Reloaded" / "Version.md").read_text(encoding="utf-8-sig").strip(),
        "profile": profile,
        "mods": mods,
    }
    write_json(payload_path, payload)
    entry = {
        "id": profile_id,
        "name": profile.get("name", profile_id),
        "version": version,
        "authors": [],
        "description": profile.get("notes", ""),
        "tags": ["profile"],
        "reloaded_version": payload["reloaded_version"],
        "profile_url": f"{REPO_RAW}/Profiles/{profile_id}/{payload_path.name}",
        "changelogurl": profile.get("changelogurl", ""),
        "mods": mods,
    }
    index["profiles"] = [row for row in index["profiles"] if normalized_id(row.get("id", "")) != profile_id] + [entry]
    return f"Publish profile {profile_id} v{version}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--repo", required=True, type=Path)
    args = parser.parse_args()
    index = load_index(args.repo)
    kind = choose("What do you want to publish?", [("Mod", "mod"), ("Profile", "profile")])
    message = publish_mod(args.game, args.repo, index) if kind == "mod" else publish_profile(args.game, args.repo, index)
    write_json(args.repo / "index.json", index)
    (args.repo / ".reloaded_commit_message").write_text(message, encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Cancelled.")
        sys.exit(1)
    except Exception as error:
        print(f"[ERROR] {error}")
        sys.exit(1)
