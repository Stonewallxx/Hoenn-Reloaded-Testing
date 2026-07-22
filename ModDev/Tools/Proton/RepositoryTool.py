#!/usr/bin/env python3
"""Hoenn Reloaded GitHub release publisher for Proton and Steam Deck."""

import argparse
import base64
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import zipfile
from pathlib import Path


DEFAULT_REPOSITORY = "Stonewallxx/Hoenn-Reloaded-Mods"
DEFAULT_BRANCH = "main"
MAX_PACKAGE_BYTES = 1024 * 1024 * 1024
BLOCKED_EXTENSIONS = {
    ".exe", ".dll", ".bat", ".cmd", ".ps1", ".psm1", ".vbs", ".js",
    ".jar", ".msi", ".scr", ".com", ".sh", ".py",
}
SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
ID_PATTERN = re.compile(r"^[a-z0-9_]+$")
SANITIZE_ROOTS = []


class ToolError(RuntimeError):
    pass


class CommandError(ToolError):
    def __init__(self, message, output=""):
        super().__init__(message)
        self.output = output


class Console:
    def __init__(self):
        self.frames = [
            "\u280b", "\u2819", "\u2839", "\u2838", "\u283c",
            "\u2834", "\u2826", "\u2827", "\u2807", "\u280f",
        ]

    def title(self, action, kind):
        print("=" * 60)
        print(f" Hoenn Reloaded {action.title()} - {kind.title()}")
        print("=" * 60)

    def phase(self, current, total, message):
        print(f"\n[{current}/{total}] {message}")

    def progress(self, current, total, label=""):
        ratio = 1.0 if total <= 0 else max(0.0, min(1.0, current / total))
        percent = int(ratio * 100)
        suffix = f"] {percent:3d}%" + (f" {label}" if label else "")
        columns = shutil.get_terminal_size((120, 24)).columns
        width = max(16, columns - len(suffix) - 2)
        filled = int(width * ratio)
        bar = ""
        if filled:
            bar += "\033[46m" + (" " * filled) + "\033[0m"
        if width - filled:
            bar += "\033[100m" + (" " * (width - filled)) + "\033[0m"
        print(f"[{bar}{suffix}")

    def spin(self, label, callback):
        done = threading.Event()

        def animate():
            index = 0
            while not done.is_set():
                sys.stdout.write(f"\r  {self.frames[index % len(self.frames)]} {label}")
                sys.stdout.flush()
                index += 1
                done.wait(0.09)

        thread = threading.Thread(target=animate, daemon=True)
        thread.start()
        try:
            return callback()
        finally:
            done.set()
            thread.join(timeout=0.5)
            sys.stdout.write("\r" + " " * (len(label) + 8) + "\r")
            sys.stdout.flush()


CONSOLE = Console()


def normalized_id(value):
    value = re.sub(r"[^a-z0-9_]+", "_", str(value).strip().lower())
    return value.strip("_")


def semver_key(value):
    if not SEMVER_PATTERN.fullmatch(str(value)):
        return None
    return tuple(int(part) for part in str(value).split("."))


def increment_patch(value):
    parsed = semver_key(value)
    if not parsed:
        return "1.0.0"
    return f"{parsed[0]}.{parsed[1]}.{parsed[2] + 1}"


def iso_timestamp():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def read_json(path):
    with Path(path).open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def write_json(path, value):
    with Path(path).open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=True)
        handle.write("\n")


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def choose(title, rows):
    if not rows:
        raise ToolError(f"No choices are available for {title.lower()}.")
    print(f"\n{title}")
    for index, row in enumerate(rows, 1):
        print(f"  {index}. {row[0]}")
    print("  0. Cancel")
    raw = input("Choice: ").strip()
    if raw == "0" or not raw:
        raise KeyboardInterrupt
    if not raw.isdigit() or not 1 <= int(raw) <= len(rows):
        raise ToolError("Invalid selection.")
    return rows[int(raw) - 1][1]


def prompt_version(default):
    value = input(f"Version [{default}]: ").strip() or default
    if not SEMVER_PATTERN.fullmatch(value):
        raise ToolError("Version must use Major.Minor.Patch.")
    return value


def confirm_exact(prompt, expected):
    print(f"\n{prompt}")
    value = input(f"Type {expected} to continue: ").strip()
    if value != expected:
        raise KeyboardInterrupt


def short_value(value, maximum=42):
    if isinstance(value, list):
        text = ", ".join(str(item) for item in value)
    else:
        text = str(value or "")
    text = text.replace("\r", " ").replace("\n", " ").strip()
    if not text:
        return "<empty>"
    return text if len(text) <= maximum else text[:max(1, maximum - 3)] + "..."


def prompt_online_text(label, current, required=False):
    print(f"\nCurrent {label.lower()}: {short_value(current, 90)}")
    value = input(f"{label} (blank keeps current; type <clear> to clear): ").strip()
    if not value:
        return str(current or "")
    if value == "<clear>":
        if required:
            raise ToolError(f"{label} cannot be empty.")
        return ""
    return value


def prompt_online_list(label, current, required=False):
    existing = [str(value) for value in current or []]
    print(f"\nCurrent {label.lower()}: {short_value(existing, 90)}")
    value = input(
        f"{label}, comma-separated (blank keeps current; type <clear> to clear): "
    ).strip()
    if not value:
        return existing
    if value == "<clear>":
        if required:
            raise ToolError(f"{label} cannot be empty.")
        return []
    items = [part.strip() for part in value.split(",") if part.strip()]
    if required and not items:
        raise ToolError(f"{label} cannot be empty.")
    return items


def run_command(arguments, cwd=None, allow_failure=False):
    process = subprocess.run(
        [str(value) for value in arguments], cwd=cwd, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    output = process.stdout or ""
    if process.returncode and not allow_failure:
        raise CommandError(f"Command failed: {arguments[0]}", output.strip())
    return process.returncode, output


class GitHubRepository:
    def __init__(self, repository, temp_root):
        self.repository = repository
        self.owner = repository.split("/", 1)[0].lower()
        self.temp_root = Path(temp_root)
        self.login = ""

    def authenticate(self):
        if shutil.which("gh") is None:
            raise ToolError("GitHub CLI was not found. Install it, then run gh auth login.")
        try:
            _, output = run_command(["gh", "api", "user", "--jq", ".login"])
        except CommandError as error:
            if any(marker in error.output for marker in ("401", "Requires authentication", "Bad credentials")):
                raise ToolError(
                    "GitHub authentication is expired or invalid. Run: "
                    "gh auth login --hostname github.com --web"
                )
            raise
        self.login = output.strip()
        if not self.login:
            raise ToolError("GitHub authentication did not return a user name.")

    def fetch_index(self):
        _, output = run_command([
            "gh", "api", f"repos/{self.repository}/contents/index.json?ref={DEFAULT_BRANCH}"
        ])
        response = json.loads(output)
        content = base64.b64decode(response.get("content", "")).decode("utf-8-sig")
        data = json.loads(content) if content.strip() else {}
        if isinstance(data, list):
            data = {"version": 1, "mods": data, "profiles": []}
        data.setdefault("version", 1)
        data.setdefault("mods", [])
        data.setdefault("profiles", [])
        return data, response.get("sha", "")

    def put_index(self, data, sha, message):
        request_path = self.temp_root / "index-request.json"
        content = json.dumps(data, indent=2, ensure_ascii=True) + "\n"
        request = {
            "message": message,
            "content": base64.b64encode(content.encode("utf-8")).decode("ascii"),
            "branch": DEFAULT_BRANCH,
        }
        if sha:
            request["sha"] = sha
        write_json(request_path, request)
        run_command([
            "gh", "api", "--method", "PUT",
            f"repos/{self.repository}/contents/index.json", "--input", str(request_path),
        ])

    def mutate_index(self, mutation, message):
        last_error = None
        for attempt in range(1, 4):
            data, sha = self.fetch_index()
            updated = mutation(copy.deepcopy(data))
            try:
                self.put_index(updated, sha, message)
                return updated
            except CommandError as error:
                last_error = error
                if "409" not in error.output and "422" not in error.output:
                    raise
                time.sleep(attempt)
        raise last_error or ToolError("The online index changed repeatedly; retry the operation.")

    def release(self, tag):
        fields = "tagName,name,body,url,isImmutable,assets"
        code, output = run_command([
            "gh", "release", "view", tag, "--repo", self.repository, "--json", fields
        ], allow_failure=True)
        if code:
            code, output = run_command([
                "gh", "release", "view", tag, "--repo", self.repository,
                "--json", "tagName,name,body,url,assets",
            ], allow_failure=True)
        return None if code else json.loads(output)

    def create_release(self, tag, title, body_path, asset):
        run_command([
            "gh", "release", "create", tag, str(asset), "--repo", self.repository,
            "--title", title, "--notes-file", str(body_path),
        ])

    def upload_asset(self, tag, asset):
        run_command(["gh", "release", "upload", tag, str(asset), "--repo", self.repository])

    def download_asset(self, tag, asset_name, destination):
        run_command([
            "gh", "release", "download", tag, "--repo", self.repository,
            "--pattern", asset_name, "--dir", str(destination),
        ])

    def delete_asset(self, tag, asset_name):
        run_command([
            "gh", "release", "delete-asset", tag, asset_name,
            "--repo", self.repository, "--yes",
        ])

    def edit_release(self, tag, title, body_path):
        run_command([
            "gh", "release", "edit", tag, "--repo", self.repository,
            "--title", title, "--notes-file", str(body_path),
        ])

    def delete_release(self, tag):
        run_command([
            "gh", "release", "delete", tag, "--repo", self.repository,
            "--cleanup-tag", "--yes",
        ])


class RepositoryTool:
    def __init__(self, args, temp_root):
        self.action = args.action
        self.kind = args.kind
        self.game = Path(args.game).resolve()
        self.dry_run = args.dry_run
        self.temp_root = Path(temp_root)
        self.github = GitHubRepository(args.repository, self.temp_root)
        self.collection = "mods" if self.kind == "mod" else "profiles"
        SANITIZE_ROOTS.append((str(self.game), "<Game>"))
        SANITIZE_ROOTS.append((str(self.temp_root), "<Temp>"))

    def execute(self):
        CONSOLE.title(self.action, self.kind)
        if not self.game.is_dir() or not (self.game / "Reloaded").is_dir():
            raise ToolError("The Hoenn Reloaded game directory is invalid.")
        if self.dry_run:
            return self.local_dry_run()
        phase_total = 4 if self.action == "update" else 6
        CONSOLE.phase(1, phase_total, "Checking GitHub authentication")
        CONSOLE.spin("Authenticating with GitHub", self.github.authenticate)
        print(f"[OK] Authenticated as {self.github.login}")
        CONSOLE.phase(2, phase_total, "Reading the online index")
        index, _sha = CONSOLE.spin("Fetching index.json", self.github.fetch_index)
        if self.action == "delete":
            return self.delete(index)
        if self.action == "update":
            CONSOLE.phase(3, phase_total, "Choosing owned published content")
            entry = self.select_owned_online_entry(index)
            CONSOLE.phase(4, phase_total, "Editing the online listing")
            return self.edit_online_listing(entry)
        source = self.select_source(index)
        CONSOLE.phase(3, 6, "Validating local content")
        metadata = self.prepare_metadata(source, index)
        print(f"[OK] {metadata['name']} {metadata['version']} passed validation")
        CONSOLE.phase(4, 6, "Building the release asset")
        asset = self.build_asset(source, metadata)
        metadata["asset_name"] = asset.name
        metadata["size"] = asset.stat().st_size
        metadata["sha256"] = sha256_file(asset)
        CONSOLE.progress(1, 1, f"{asset.name} ({metadata['size']} bytes)")
        CONSOLE.phase(5, 6, "Publishing to GitHub")
        if metadata["old"]:
            self.update(asset, metadata, index)
        else:
            self.publish(asset, metadata)
        CONSOLE.phase(6, 6, "Verifying the published entry")
        self.verify(metadata)
        print(f"\n[SUCCESS] {metadata['name']} {metadata['version']} is published.")

    def local_dry_run(self):
        if self.action == "update":
            CONSOLE.phase(1, 1, "Checking the metadata-only Update workflow")
            print("[OK] Update edits owned online listings and never reads or packages local content.")
            print("[SUCCESS] Dry run completed without network or repository changes.")
            return
        CONSOLE.phase(1, 2, "Scanning local content")
        sources = self.local_sources()
        print(f"[OK] Found {len(sources)} local {self.kind}(s).")
        CONSOLE.phase(2, 2, "Validating local source files")
        failures = []
        for source in sources:
            try:
                self.validate_source(source)
            except Exception as error:
                failures.append(f"{source['path'].name}: {error}")
        if failures:
            raise ToolError("Dry-run validation failed:\n" + "\n".join(failures))
        print("[SUCCESS] Dry run completed without network or repository changes.")

    def local_sources(self):
        if self.kind == "profile":
            root = self.game / "Mods" / "Reloaded" / "Profiles"
            return [
                {"path": path, "data": read_json(path)}
                for path in sorted(root.glob("*.json")) if path.is_file()
            ] if root.is_dir() else []
        sources = []
        for root_name in ("Mods", "ModDev"):
            root = self.game / root_name
            if not root.is_dir():
                continue
            for path in sorted(root.glob("*/mod.json")):
                if path.parent.name.lower() == "tools":
                    continue
                sources.append({"path": path.parent, "data": read_json(path), "root": root_name})
        return sources

    def select_source(self, index):
        sources = self.local_sources()
        rows = [(self.source_label(source), source) for source in sources]
        return choose(f"Choose a {self.kind} to publish", rows)

    def source_label(self, source):
        data = source["data"]
        version = data.get("version", "") if self.kind == "mod" else ""
        label = f"{data.get('name', source['path'].stem)} {version}".strip()
        source_labels = {"Mods": "Installed", "ModDev": "ModDev"}
        location = source_labels.get(source.get("root"))
        return f"[{location}] {label}" if location else label

    @staticmethod
    def online_entry_label(entry):
        name = entry.get("name") or entry.get("id", "")
        version = entry.get("latest_version") or entry.get("version", "")
        return f"{name} {version}".strip()

    def select_owned_online_entry(self, index):
        entries = sorted(
            (row for row in index[self.collection] if self.can_manage(row)),
            key=lambda row: (str(row.get("name", "")).lower(), str(row.get("id", ""))),
        )
        return choose(f"Choose an owned online {self.kind}", [
            (self.online_entry_label(row), row) for row in entries
        ])

    def edit_online_listing_fields(self, entry):
        working = copy.deepcopy(entry)
        while True:
            field = choose(f"Edit online listing for {working.get('name', working.get('id'))}", [
                (f"Name: {short_value(working.get('name'))}", "name"),
                (f"Authors: {short_value(working.get('authors', []))}", "authors"),
                (f"Description: {short_value(working.get('description'))}", "description"),
                (f"Tags: {short_value(working.get('tags', []))}", "tags"),
                (f"Changelog URL: {short_value(working.get('changelogurl'))}", "changelogurl"),
                (f"Homepage URL: {short_value(working.get('homepage_url'))}", "homepage_url"),
                ("Save Online Listing", "save"),
            ])
            if field == "name":
                working[field] = prompt_online_text("Name", working.get(field), required=True)
            elif field == "authors":
                working[field] = prompt_online_list("Authors", working.get(field, []), required=True)
            elif field == "description":
                working[field] = prompt_online_text("Description", working.get(field), required=True)
            elif field == "tags":
                working[field] = prompt_online_list("Tags", working.get(field, []))
            elif field in ("changelogurl", "homepage_url"):
                label = "Changelog URL" if field == "changelogurl" else "Homepage URL"
                working[field] = prompt_online_text(label, working.get(field))
            else:
                for name in ("changelogurl", "homepage_url"):
                    value = str(working.get(name, "")).strip()
                    if value and not re.match(r"^https?://", value, re.IGNORECASE):
                        raise ToolError(f"{name} must use a complete http:// or https:// URL.")
                return working

    def write_online_release_body(self, entry, body_path):
        version = str(entry.get("latest_version") or entry.get("version", ""))
        record = next((
            row for row in entry.get("versions", [])
            if str(row.get("version", "")) == version
        ), None)
        minimum = str(entry.get("reloaded_version", ""))
        if not minimum and record:
            minimum = str(record.get("reloaded_version", ""))
        self.release_body({
            "description": str(entry.get("description", "")),
            "authors": list(entry.get("authors", [])),
            "version": version,
            "reloaded_version": minimum,
            "publisher_login": str(entry.get("publisher_login", "")),
        }, body_path)

    def edit_online_listing(self, entry):
        self.require_owner(entry)
        edited = self.edit_online_listing_fields(entry)
        entry_id = normalized_id(entry.get("id", ""))
        confirm_exact(
            "This changes the public listing and release page without replacing any version assets.",
            f"SAVE ONLINE {entry_id}",
        )
        tag = f"{self.kind}-{entry_id}"
        release = self.github.release(tag)
        if not release:
            raise ToolError("The persistent GitHub release is missing. The repository owner must repair it.")
        if release.get("isImmutable") is True:
            raise ToolError("This GitHub release is immutable. Disable immutable releases before editing it.")
        body = self.temp_root / "online-release-body.txt"
        self.write_online_release_body(edited, body)
        version = str(edited.get("latest_version") or edited.get("version", ""))
        title = f"{edited.get('name', entry_id)} {version}".strip()
        fields = ("name", "authors", "description", "tags", "changelogurl", "homepage_url")
        changes = {name: copy.deepcopy(edited.get(name, [] if name in ("authors", "tags") else "")) for name in fields}
        CONSOLE.spin("Updating release page", lambda: self.github.edit_release(tag, title, body))
        try:
            def mutation(data):
                rows = data[self.collection]
                position = next((
                    index for index, row in enumerate(rows)
                    if normalized_id(row.get("id", "")) == entry_id
                ), None)
                if position is None:
                    raise ToolError("The online index entry disappeared during the edit.")
                self.require_owner(rows[position])
                for name, value in changes.items():
                    rows[position][name] = copy.deepcopy(value)
                rows[position]["updated_at"] = iso_timestamp()
                return data
            CONSOLE.spin(
                "Updating index.json",
                lambda: self.github.mutate_index(mutation, f"Edit online listing for {self.kind} {entry_id}"),
            )
        except Exception:
            old_body = self.temp_root / "old-online-release-body.txt"
            old_body.write_text(str(release.get("body", "")), encoding="utf-8")
            self.github.edit_release(tag, str(release.get("name", entry_id)), old_body)
            raise
        current_index, _sha = self.github.fetch_index()
        current = next((
            row for row in current_index[self.collection]
            if normalized_id(row.get("id", "")) == entry_id
        ), None)
        if not current:
            raise ToolError("The edited online listing could not be verified.")
        for name, expected in changes.items():
            if current.get(name, [] if name in ("authors", "tags") else "") != expected:
                raise ToolError(f"The edited {name} field could not be verified.")
        print(f"\n[SUCCESS] Updated the online listing for {edited.get('name', entry_id)}.")

    def source_id(self, source):
        data = source["data"]
        return normalized_id(data.get("id") or data.get("name") or source["path"].stem)

    def validate_source(self, source):
        data = source["data"]
        content_id = self.source_id(source)
        if not ID_PATTERN.fullmatch(content_id):
            raise ToolError("The content id must use lowercase letters, numbers, and underscores.")
        if not str(data.get("name", "")).strip():
            raise ToolError("A display name is required.")
        if self.kind == "profile":
            for key in ("enabled_mods", "disabled_mods", "load_order"):
                if not isinstance(data.get(key, []), list):
                    raise ToolError(f"Profile field {key} must be a list.")
            return
        version = str(data.get("version", ""))
        if not SEMVER_PATTERN.fullmatch(version):
            raise ToolError("The mod version must use Major.Minor.Patch.")
        if not isinstance(data.get("authors"), list) or not data.get("authors"):
            raise ToolError("The mod manifest needs at least one author.")
        if not isinstance(data.get("dependencies", []), list):
            raise ToolError("The mod dependencies field must be a list.")
        if data.get("game") and normalized_id(data.get("game")) not in ("hoenn", "hoenn_reloaded", "hoennreloaded"):
            raise ToolError("The manifest targets a different game.")
        seen = set()
        total = 0
        for path in source["path"].rglob("*"):
            if path.is_symlink():
                raise ToolError(f"Symbolic links are not allowed: {path.name}")
            if not path.is_file():
                continue
            if path.suffix.lower() in BLOCKED_EXTENSIONS:
                raise ToolError(f"Blocked file type: {path.relative_to(source['path'])}")
            key = str(path.relative_to(source["path"])).replace("\\", "/").lower()
            if key in seen:
                raise ToolError(f"Case-colliding package path: {key}")
            seen.add(key)
            total += path.stat().st_size
        if total > MAX_PACKAGE_BYTES:
            raise ToolError("The package exceeds the 1 GiB mod-package limit.")

    def prepare_metadata(self, source, index):
        self.validate_source(source)
        data = source["data"]
        content_id = self.source_id(source)
        old = next((row for row in index[self.collection] if normalized_id(row.get("id", "")) == content_id), None)
        if old:
            self.require_owner(old)
        if self.kind == "mod":
            version = str(data.get("version", ""))
            authors = [str(value) for value in data.get("authors", [])]
            description = str(data.get("description", ""))
            tags = data.get("tags", []) if isinstance(data.get("tags", []), list) else []
            dependencies = data.get("dependencies", [])
            mods = []
        else:
            default = "1.0.0" if not old else increment_patch(old.get("latest_version") or old.get("version"))
            version = prompt_version(default)
            authors = list(old.get("authors", [])) if old else [self.github.login]
            authors = authors or [self.github.login]
            description = str(data.get("notes", "")) or f"Hoenn Reloaded profile {data.get('name', content_id)}."
            tags = ["Profile"]
            dependencies = []
            mods = self.profile_mods(data)
            if not mods:
                raise ToolError("A published profile must reference at least one mod.")
        if old:
            latest = str(old.get("latest_version") or old.get("version", ""))
            if semver_key(version) and semver_key(latest) and semver_key(version) < semver_key(latest):
                confirm_exact("This version is older than the published latest version.", f"ALLOW OLDER {content_id} {version}")
        return {
            "id": content_id,
            "name": str(data.get("name", content_id)),
            "version": version,
            "authors": authors,
            "description": description,
            "tags": tags,
            "dependencies": dependencies,
            "mods": mods,
            "source": source,
            "old": old,
            "tag": f"{self.kind}-{content_id}",
            "release_url": f"https://github.com/{self.github.repository}/releases/tag/{self.kind}-{content_id}",
            "reloaded_version": self.reloaded_version(),
            "publisher_login": str(old.get("publisher_login", "")) if old else self.github.login,
        }

    def profile_mods(self, profile):
        manifests = {}
        for source in self.local_sources_for_mods():
            manifests[self.source_id(source)] = source["data"]
        ids = []
        for key in ("enabled_mods", "disabled_mods", "load_order"):
            ids.extend(profile.get(key, []) or [])
        settings = profile.get("mod_settings", {})
        if isinstance(settings, dict):
            ids.extend(settings.keys())
        result = []
        for mod_id in sorted({normalized_id(value) for value in ids if normalized_id(value)}):
            manifest = manifests.get(mod_id)
            if not manifest:
                raise ToolError(f"Profile references a missing local mod: {mod_id}")
            result.append({"id": mod_id, "version": str(manifest.get("version", ""))})
        return result

    def local_sources_for_mods(self):
        original = self.kind
        self.kind = "mod"
        try:
            return self.local_sources()
        finally:
            self.kind = original

    def build_asset(self, source, metadata):
        if self.kind == "profile":
            asset = self.temp_root / f"{metadata['id']}-{metadata['version']}.json"
            payload = {
                "format": "RLD-code", "version": 1,
                "preset_name": metadata["name"],
                "reloaded_version": metadata["reloaded_version"],
                "profile": source["data"], "mods": metadata["mods"],
            }
            write_json(asset, payload)
            return asset
        asset = self.temp_root / f"{metadata['id']}-{metadata['version']}.zip"
        files = [path for path in source["path"].rglob("*") if path.is_file()]
        with zipfile.ZipFile(asset, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
            for index, path in enumerate(sorted(files), 1):
                relative = Path(source["path"].name) / path.relative_to(source["path"])
                output.write(path, relative)
                if index == len(files) or index % 100 == 0:
                    CONSOLE.progress(index, len(files), path.name)
        return asset

    def version_record(self, metadata):
        url = f"https://github.com/{self.github.repository}/releases/download/{metadata['tag']}/{metadata['asset_name']}"
        record = {
            "version": metadata["version"], "sha256": metadata["sha256"],
            "size": metadata["size"], "reloaded_version": metadata["reloaded_version"],
        }
        if self.kind == "mod":
            record["download_url"] = url
            record["dependencies"] = metadata["dependencies"]
            record["changelogurl"] = str(metadata["source"]["data"].get("changelogurl", ""))
        else:
            record["profile_url"] = url
            record["mods"] = metadata["mods"]
        return record

    def build_entry(self, metadata, existing=None):
        now = iso_timestamp()
        versions = list(existing.get("versions", [])) if existing else []
        versions = [row for row in versions if str(row.get("version", "")) != metadata["version"]]
        versions.append(self.version_record(metadata))
        versions.sort(key=lambda row: semver_key(row.get("version")) or (0, 0, 0), reverse=True)
        latest = versions[0]
        entry = copy.deepcopy(existing) if existing else {}
        entry.update({
            "id": metadata["id"], "name": metadata["name"],
            "latest_version": latest["version"], "version": latest["version"],
            "authors": metadata["authors"], "description": metadata["description"],
            "tags": metadata["tags"], "publisher_login": existing.get("publisher_login", self.github.login) if existing else self.github.login,
            "release_url": metadata["release_url"],
            "published_at": existing.get("published_at", now) if existing else now,
            "updated_at": now, "versions": versions,
        })
        if self.kind == "mod":
            entry["dependencies"] = metadata["dependencies"]
            entry["download_url"] = latest["download_url"]
            entry["sha256"] = latest["sha256"]
            entry["size"] = latest["size"]
            entry["changelogurl"] = str(metadata["source"]["data"].get("changelogurl", ""))
        else:
            entry["profile_url"] = latest["profile_url"]
            entry["sha256"] = latest["sha256"]
            entry["size"] = latest["size"]
            entry["reloaded_version"] = latest["reloaded_version"]
            entry["mods"] = latest["mods"]
        return entry

    def release_body(self, metadata, body_path):
        authors = ", ".join(metadata["authors"]) or self.github.login
        publisher = str(metadata.get("publisher_login", "")) or self.github.login
        lines = [metadata["description"].strip(), "", f"Authors: {authors}",
                 f"Latest Version: {metadata['version']}",
                 f"Publisher: @{publisher}",
                 f"Minimum Reloaded: {metadata['reloaded_version']}"]
        body_path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")

    def publish(self, asset, metadata):
        if self.github.release(metadata["tag"]):
            raise ToolError("The stable release tag already exists but is missing from the online index. The repository owner must repair it.")
        body = self.temp_root / "release-body.txt"
        self.release_body(metadata, body)
        title = f"{metadata['name']} {metadata['version']}"
        CONSOLE.spin("Creating release and uploading asset", lambda: self.github.create_release(metadata["tag"], title, body, asset))
        try:
            def mutation(data):
                rows = data[self.collection]
                if any(normalized_id(row.get("id", "")) == metadata["id"] for row in rows):
                    raise ToolError("The id was published by another operation. Run Publish again.")
                rows.append(self.build_entry(metadata))
                return data
            CONSOLE.spin("Updating index.json", lambda: self.github.mutate_index(mutation, f"Publish {self.kind} {metadata['id']} {metadata['version']}"))
        except Exception:
            self.github.delete_release(metadata["tag"])
            raise

    def update(self, asset, metadata, index):
        existing = metadata["old"]
        release = self.github.release(metadata["tag"])
        if not release:
            raise ToolError("The persistent GitHub release is missing. The repository owner must repair it.")
        if release.get("isImmutable") is True:
            raise ToolError("This GitHub release is immutable. Disable immutable releases before updating it.")
        old_version = next((row for row in existing.get("versions", []) if str(row.get("version")) == metadata["version"]), None)
        backup = None
        if old_version:
            confirm_exact("This version is already published and will be replaced.", f"REPLACE {metadata['id']} {metadata['version']}")
            old_url = old_version.get("download_url") or old_version.get("profile_url") or ""
            old_asset_name = Path(urllib.parse.urlparse(old_url).path).name
            if not old_asset_name:
                raise ToolError("The existing release asset name could not be determined.")
            backup_dir = self.temp_root / "asset-backup"
            backup_dir.mkdir()
            self.github.download_asset(metadata["tag"], old_asset_name, backup_dir)
            backup = backup_dir / old_asset_name
            self.github.delete_asset(metadata["tag"], old_asset_name)
        CONSOLE.spin("Uploading version asset", lambda: self.github.upload_asset(metadata["tag"], asset))
        body = self.temp_root / "release-body.txt"
        self.release_body(metadata, body)
        self.github.edit_release(metadata["tag"], f"{metadata['name']} {metadata['version']}", body)
        try:
            def mutation(data):
                rows = data[self.collection]
                position = next((i for i, row in enumerate(rows) if normalized_id(row.get("id", "")) == metadata["id"]), None)
                if position is None:
                    raise ToolError("The online index entry disappeared during the update.")
                self.require_owner(rows[position])
                rows[position] = self.build_entry(metadata, rows[position])
                return data
            CONSOLE.spin("Updating index.json", lambda: self.github.mutate_index(mutation, f"Publish {self.kind} {metadata['id']} {metadata['version']}"))
        except Exception:
            self.github.delete_asset(metadata["tag"], metadata["asset_name"])
            if backup and backup.is_file():
                self.github.upload_asset(metadata["tag"], backup)
            old_body = self.temp_root / "old-release-body.txt"
            old_body.write_text(str(release.get("body", "")), encoding="utf-8")
            self.github.edit_release(metadata["tag"], str(release.get("name", metadata["name"])), old_body)
            raise

    def delete(self, index):
        CONSOLE.phase(3, 6, "Choosing published content")
        entries = [row for row in index[self.collection] if self.can_manage(row)]
        entry = choose(f"Choose a {self.kind} to delete", [
            (f"{row.get('name', row.get('id'))} {row.get('latest_version', row.get('version', ''))}", row)
            for row in entries
        ])
        self.require_owner(entry)
        versions = list(entry.get("versions", []))
        rows = [(f"Version {row.get('version')}", ("version", row)) for row in versions]
        rows.append(("Entire entry and release", ("entry", None)))
        mode, version = choose("Choose what to delete", rows)
        warnings = self.dependency_warnings(index, entry["id"])
        if warnings:
            print("\n[WARNING] This content is referenced by:")
            for warning in warnings:
                print(f"  - {warning}")
        expected = str(entry["id"]) if mode == "entry" else f"{entry['id']} {version.get('version')}"
        confirm_exact("This permanently changes the public repository.", expected)
        CONSOLE.phase(4, 6, "Updating the public index")
        before = copy.deepcopy(entry)
        remaining = [] if mode == "entry" else [row for row in versions if str(row.get("version")) != str(version.get("version"))]
        if not remaining:
            mode = "entry"
        def remove_mutation(data):
            rows_value = data[self.collection]
            position = next((i for i, row in enumerate(rows_value) if normalized_id(row.get("id", "")) == normalized_id(entry["id"])), None)
            if position is None:
                raise ToolError("The entry is no longer present in the online index.")
            self.require_owner(rows_value[position])
            if mode == "entry":
                rows_value.pop(position)
            else:
                current = copy.deepcopy(rows_value[position])
                current_versions = [row for row in current.get("versions", []) if str(row.get("version")) != str(version.get("version"))]
                current_versions.sort(key=lambda row: semver_key(row.get("version")) or (0, 0, 0), reverse=True)
                latest = current_versions[0]
                current["versions"] = current_versions
                current["version"] = latest["version"]
                current["latest_version"] = latest["version"]
                current["updated_at"] = iso_timestamp()
                if self.kind == "mod":
                    current["download_url"] = latest["download_url"]
                    current["sha256"] = latest.get("sha256", "")
                    current["size"] = latest.get("size", 0)
                else:
                    current["profile_url"] = latest["profile_url"]
                    current["mods"] = latest.get("mods", [])
                    current["sha256"] = latest.get("sha256", "")
                    current["size"] = latest.get("size", 0)
                rows_value[position] = current
            return data
        self.github.mutate_index(remove_mutation, f"Delete {self.kind} {expected}")
        CONSOLE.phase(5, 6, "Deleting GitHub release content")
        tag = f"{self.kind}-{normalized_id(entry['id'])}"
        try:
            if mode == "entry":
                CONSOLE.spin("Deleting release and tag", lambda: self.github.delete_release(tag))
            else:
                url = version.get("download_url") or version.get("profile_url") or ""
                asset_name = Path(urllib.parse.urlparse(url).path).name
                if not asset_name:
                    raise ToolError("The release asset name could not be determined.")
                CONSOLE.spin("Deleting release asset", lambda: self.github.delete_asset(tag, asset_name))
                latest = sorted(remaining, key=lambda row: semver_key(row.get("version")) or (0, 0, 0), reverse=True)[0]
                body = self.temp_root / "release-body.txt"
                metadata = {
                    "description": entry.get("description", ""), "authors": entry.get("authors", []),
                    "version": latest["version"], "reloaded_version": latest.get("reloaded_version", ""),
                }
                self.release_body(metadata, body)
                self.github.edit_release(tag, f"{entry.get('name', entry['id'])} {latest['version']}", body)
        except Exception:
            def restore(data):
                rows_value = data[self.collection]
                rows_value[:] = [row for row in rows_value if normalized_id(row.get("id", "")) != normalized_id(before["id"])]
                rows_value.append(before)
                return data
            self.github.mutate_index(restore, f"Restore {self.kind} {entry['id']} after failed delete")
            raise
        CONSOLE.phase(6, 6, "Verifying deletion")
        current, _sha = self.github.fetch_index()
        current_entry = next((row for row in current[self.collection] if normalized_id(row.get("id", "")) == normalized_id(entry["id"])), None)
        if mode == "entry" and current_entry:
            raise ToolError("The entry still exists after deletion.")
        if mode != "entry" and any(str(row.get("version")) == str(version.get("version")) for row in current_entry.get("versions", [])):
            raise ToolError("The deleted version still exists in the index.")
        print(f"\n[SUCCESS] Deleted {expected}.")

    def verify(self, metadata):
        index, _sha = self.github.fetch_index()
        entry = next((row for row in index[self.collection] if normalized_id(row.get("id", "")) == metadata["id"]), None)
        if not entry:
            raise ToolError("The published entry was not found in index.json.")
        version = next((row for row in entry.get("versions", []) if str(row.get("version")) == metadata["version"]), None)
        if not version or int(version.get("size", 0)) != metadata["size"] or str(version.get("sha256", "")) != metadata["sha256"]:
            raise ToolError("The online version metadata did not match the uploaded asset.")
        release = self.github.release(metadata["tag"])
        if not release:
            raise ToolError("The persistent release could not be verified.")
        asset = next((row for row in release.get("assets", []) if row.get("name") == metadata["asset_name"]), None)
        if not asset or int(asset.get("size", 0)) != metadata["size"]:
            raise ToolError("The uploaded GitHub release asset size could not be verified.")
        print("[OK] Index entry, checksum, release asset, and remote size are present.")

    def can_manage(self, entry):
        publisher = str(entry.get("publisher_login", "")).strip().lower()
        login = self.github.login.lower()
        return login == self.github.owner or (publisher and publisher == login)

    def require_owner(self, entry):
        publisher = str(entry.get("publisher_login", "")).strip()
        if self.can_manage(entry):
            return
        if not publisher:
            raise ToolError("This legacy entry has no publisher owner. The repository owner must migrate it.")
        raise ToolError(f"Only @{publisher} or the repository owner can change this entry.")

    def dependency_warnings(self, index, content_id):
        wanted = normalized_id(content_id)
        warnings = []
        for mod in index.get("mods", []):
            deps = mod.get("dependencies", [])
            ids = [normalized_id(value.get("id", "") if isinstance(value, dict) else value) for value in deps]
            if wanted in ids:
                warnings.append(f"Mod: {mod.get('name', mod.get('id'))}")
        for profile in index.get("profiles", []):
            ids = [normalized_id(value.get("id", "") if isinstance(value, dict) else value) for value in profile.get("mods", [])]
            if wanted in ids:
                warnings.append(f"Profile: {profile.get('name', profile.get('id'))}")
        return warnings

    def reloaded_version(self):
        path = self.game / "Reloaded" / "Version.md"
        return path.read_text(encoding="utf-8-sig").strip() if path.is_file() else ""


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", required=True, choices=("publish", "update", "delete"))
    parser.add_argument("--kind", choices=("mod", "profile"), default=None)
    parser.add_argument("--game", required=True)
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.kind:
        args.kind = choose("Choose content type", [("Mod", "mod"), ("Profile", "profile")])
    return args


def main():
    args = parse_arguments()
    with tempfile.TemporaryDirectory(prefix="hoenn-reloaded-publisher.") as temp_root:
        RepositoryTool(args, temp_root).execute()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[CANCELLED] No further changes were made.")
        sys.exit(2)
    except Exception as error:
        detail = error.output if isinstance(error, CommandError) and error.output else str(error)
        for root, replacement in SANITIZE_ROOTS:
            detail = detail.replace(root, replacement).replace(root.replace("\\", "/"), replacement)
        print(f"\n[FAILED] {detail}")
        sys.exit(1)
