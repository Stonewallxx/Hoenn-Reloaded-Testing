#!/usr/bin/env python3
"""AIO installer for Hoenn Reloaded under Proton and Steam Deck."""

import argparse
import bisect
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile


PUBLIC_MANIFEST_URL = (
    "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/"
    "main/Reloaded/InstallerManifest.json"
)
TESTING_ARCHIVE_URL = (
    "https://github.com/Stonewallxx/Hoenn-Reloaded-Testing/"
    "archive/refs/heads/main.zip"
)
SPRITEPACK_CATALOG_URL = (
    "https://raw.githubusercontent.com/Stonewallxx/Hoenn-Reloaded/"
    "main/Reloaded/Spritepacks.json"
)
PROTECTED_PREFIXES = (
    "mods/",
    "reloaded/logging/",
    "reloaded/cache/",
    "reloaded/settings.txt",
    "graphics/custombattlers/sprite import/",
    "graphics/spritepacks/",
    ".git/",
)
TESTING_EXCLUDED_PATTERNS = tuple(
    re.compile(value, re.IGNORECASE)
    for value in (
        r"^(?:\.agents|\.codex|\.git|\.github|\.vscode)/",
        r"^(?:Admin Tools|Developer Tools|ModDev)/",
        r"^REQUIRED_BY_INSTALLER_UPDATER/",
        r"^Mods/",
        r"^Graphics/SpritePacks/",
        r"^Graphics/CustomBattlers/(?:Sprite Import|custom_sprites|"
        r"local_sprites/(?:BaseSprites|indexed)|"
        r"spritesheets/spritesheets_(?:base|custom))/",
        r"^Reloaded/(?:Cache|Logging)/",
        r"^Reloaded/Settings\.txt$",
        r"^Reloaded/InstallerManifest\.json$",
        r"^Reloaded/InstallerFiles\.json$",
        r"^Reloaded/Documentation/(?:To-Do|VanillaChanges|ReloadedMart-To-Do)\.md$",
        r"^\.gitignore$",
        r"^\.DS_Store$",
        r"^outside\.zip$",
    )
)


class MultiPartReader(io.RawIOBase):
    """Seekable view over sequential raw ZIP parts without joining them."""

    def __init__(self, paths):
        super().__init__()
        self.paths = list(paths)
        self.offsets = [0]
        for path in self.paths:
            self.offsets.append(self.offsets[-1] + os.path.getsize(path))
        self.position = 0
        self.handle = None
        self.handle_index = -1

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=os.SEEK_SET):
        if whence == os.SEEK_SET:
            position = offset
        elif whence == os.SEEK_CUR:
            position = self.position + offset
        elif whence == os.SEEK_END:
            position = self.offsets[-1] + offset
        else:
            raise ValueError("Unsupported seek mode")
        if position < 0:
            raise ValueError("Negative seek position")
        self.position = min(position, self.offsets[-1])
        return self.position

    def _select_handle(self, index):
        if self.handle_index == index and self.handle is not None:
            return self.handle
        if self.handle is not None:
            self.handle.close()
        self.handle = open(self.paths[index], "rb")
        self.handle_index = index
        return self.handle

    def read(self, size=-1):
        remaining = self.offsets[-1] - self.position
        if remaining <= 0:
            return b""
        wanted = remaining if size is None or size < 0 else min(size, remaining)
        chunks = []
        while wanted > 0 and self.position < self.offsets[-1]:
            index = bisect.bisect_right(self.offsets, self.position) - 1
            index = min(index, len(self.paths) - 1)
            local_offset = self.position - self.offsets[index]
            available = self.offsets[index + 1] - self.position
            amount = min(wanted, available)
            handle = self._select_handle(index)
            handle.seek(local_offset)
            block = handle.read(amount)
            if not block:
                break
            chunks.append(block)
            self.position += len(block)
            wanted -= len(block)
        return b"".join(chunks)

    def close(self):
        if self.handle is not None:
            self.handle.close()
            self.handle = None
        super().close()


def safe_relative(value):
    normalized = str(value).replace("\\", "/").lstrip("/")
    parts = normalized.split("/")
    if (
        not normalized
        or os.path.isabs(str(value))
        or any(part == ".." for part in parts)
        or (len(normalized) > 1 and normalized[1] == ":")
    ):
        raise RuntimeError("Unsafe package path: {}".format(value))
    return normalized


def protected(relative):
    value = relative.replace("\\", "/").lstrip("/").lower()
    return any(
        value == prefix.rstrip("/") or value.startswith(prefix)
        for prefix in PROTECTED_PREFIXES
    )


def testing_excluded(relative):
    value = relative.replace("\\", "/").lstrip("/")
    return any(pattern.search(value) for pattern in TESTING_EXCLUDED_PATTERNS)


def inside(root, path):
    try:
        return os.path.commonpath((os.path.abspath(root), os.path.abspath(path))) == os.path.abspath(root)
    except ValueError:
        return False


def print_progress(label, current, total):
    if total > 0:
        percent = min(100, int(current * 100 / total))
        width = 32
        filled = int(width * percent / 100)
        bar = "#" * filled + "-" * (width - filled)
        text = "\r{} [{}] {:3d}% {:.1f}/{:.1f} MB".format(
            label, bar, percent, current / 1048576.0, total / 1048576.0
        )
    else:
        text = "\r{} {:.1f} MB".format(label, current / 1048576.0)
    sys.stdout.write(text)
    sys.stdout.flush()


def sha256(path):
    digest = hashlib.sha256()
    total = os.path.getsize(path)
    complete = 0
    with open(path, "rb") as source:
        while True:
            block = source.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
            complete += len(block)
            print_progress("Verifying " + os.path.basename(path), complete, total)
    print()
    return digest.hexdigest()


def verified(path, expected_size=0, expected_hash=""):
    if not os.path.isfile(path):
        return False
    if expected_size and os.path.getsize(path) != int(expected_size):
        return False
    if expected_hash and sha256(path).lower() != str(expected_hash).lower():
        return False
    return True


def download(
    url,
    destination,
    expected_size=0,
    expected_hash="",
    label="Package",
    force=False,
):
    part = destination + ".part"
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if force and os.path.isfile(destination):
        os.remove(destination)
    elif verified(destination, expected_size, expected_hash):
        print("Using verified cached {}.".format(label))
        return
    elif os.path.exists(destination):
        os.remove(destination)

    parsed = urllib.parse.urlparse(url)
    if parsed.scheme == "file":
        source_path = urllib.request.url2pathname(parsed.path)
        total = os.path.getsize(source_path)
        complete = 0
        with open(source_path, "rb") as source, open(part, "wb") as target:
            while True:
                block = source.read(1024 * 1024)
                if not block:
                    break
                target.write(block)
                complete += len(block)
                print_progress("Copying " + label, complete, total)
        print()
        os.replace(part, destination)
        if not verified(destination, expected_size, expected_hash):
            os.remove(destination)
            raise RuntimeError("{} failed size or SHA-256 verification.".format(label))
        return

    existing = os.path.getsize(part) if os.path.isfile(part) else 0
    if expected_size and existing > int(expected_size):
        os.remove(part)
        existing = 0

    request = urllib.request.Request(
        url, headers={"User-Agent": "HoennReloadedInstaller/2"}
    )
    if existing:
        request.add_header("Range", "bytes={}-".format(existing))
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError:
        if existing:
            os.remove(part)
            return download(
                url,
                destination,
                expected_size,
                expected_hash,
                label,
                force,
            )
        raise

    append = existing > 0 and getattr(response, "status", 200) == 206
    if not append:
        existing = 0
    total = int(expected_size or 0)
    if not total:
        length = int(response.headers.get("Content-Length", "0") or 0)
        total = existing + length if length else 0
    mode = "ab" if append else "wb"
    received = existing
    with response, open(part, mode) as target:
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            target.write(block)
            received += len(block)
            print_progress("Downloading " + label, received, total)
    print()
    os.replace(part, destination)
    if not verified(destination, expected_size, expected_hash):
        os.remove(destination)
        raise RuntimeError("{} failed size or SHA-256 verification.".format(label))


def read_json(path):
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8-sig") as source:
        return json.load(source)


def write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as target:
        json.dump(value, target, indent=2)
        target.write("\n")


def json_source(local_file, url, temp_root, name):
    if local_file:
        data = read_json(os.path.abspath(local_file))
        if data is None:
            raise RuntimeError("{} file is missing or invalid.".format(name))
        return data
    target = os.path.join(temp_root, re.sub(r"[^0-9A-Za-z._-]", "_", name) + ".json")
    if os.path.isfile(target):
        os.remove(target)
    download(url, target, label=name, force=True)
    data = read_json(target)
    if data is None:
        raise RuntimeError("{} download was invalid.".format(name))
    return data


def extract_direct(archive, game_root, label, allow_protected=False):
    print("Installing {} directly into:\n  {}".format(label, game_root))
    multipart = MultiPartReader(archive) if isinstance(archive, (list, tuple)) else None
    source_archive = multipart if multipart is not None else archive
    try:
        with zipfile.ZipFile(source_archive, "r") as package:
            entries = package.infolist()
            total = sum(max(0, entry.file_size) for entry in entries)
            complete = 0
            for entry in entries:
                relative = safe_relative(entry.filename)
                if not allow_protected and protected(relative):
                    raise RuntimeError("Core package contains protected user/runtime content.")
                destination = os.path.abspath(os.path.join(game_root, relative))
                if not inside(game_root, destination):
                    raise RuntimeError("Archive entry leaves the game directory.")
                if entry.is_dir():
                    os.makedirs(destination, exist_ok=True)
                    continue
                os.makedirs(os.path.dirname(destination), exist_ok=True)
                with package.open(entry, "r") as source, open(destination, "wb") as target:
                    while True:
                        block = source.read(1024 * 1024)
                        if not block:
                            break
                        target.write(block)
                        complete += len(block)
                        print_progress("Installing " + label, complete, total)
                mode = (entry.external_attr >> 16) & 0o777
                if mode:
                    try:
                        os.chmod(destination, mode)
                    except OSError:
                        pass
    finally:
        if multipart is not None:
            multipart.close()
    print()


def extract_testing_snapshot(archive, stage_root):
    if os.path.isdir(stage_root):
        shutil.rmtree(stage_root)
    os.makedirs(stage_root)
    with zipfile.ZipFile(archive, "r") as package:
        entries = package.infolist()
        total = sum(max(0, entry.file_size) for entry in entries)
        complete = 0
        for entry in entries:
            relative = safe_relative(entry.filename)
            destination = os.path.abspath(os.path.join(stage_root, relative))
            if not inside(stage_root, destination):
                raise RuntimeError("Testing archive entry leaves its temporary folder.")
            if entry.is_dir():
                os.makedirs(destination, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            with package.open(entry, "r") as source, open(destination, "wb") as target:
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    target.write(block)
                    complete += len(block)
                    print_progress("Opening Testing snapshot", complete, total)
    print()


def install_testing_snapshot(archive, stage_root, game_root, managed_path):
    extract_testing_snapshot(archive, stage_root)
    source_root = stage_root
    if not os.path.isdir(os.path.join(source_root, "Reloaded")):
        candidates = []
        for name in os.listdir(stage_root):
            path = os.path.join(stage_root, name)
            if os.path.isdir(os.path.join(path, "Reloaded")):
                candidates.append(path)
        if len(candidates) != 1:
            raise RuntimeError("The Testing repository snapshot has an unexpected layout.")
        source_root = candidates[0]

    source_files = []
    for root, _, files in os.walk(source_root):
        for name in files:
            source_files.append(os.path.join(root, name))
    managed = []
    copied = 0
    for source in source_files:
        relative = safe_relative(os.path.relpath(source, source_root))
        if testing_excluded(relative) or protected(relative):
            continue
        destination = os.path.abspath(os.path.join(game_root, relative))
        if not inside(game_root, destination):
            raise RuntimeError("Testing snapshot file leaves the install directory.")
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)
        managed.append(relative)
        copied += 1
        print_progress("Installing Testing", copied, len(source_files))
    print()

    version_path = os.path.join(source_root, "Reloaded", "Version.md")
    if os.path.isfile(version_path):
        with open(version_path, "r", encoding="utf-8-sig") as source:
            version = source.read().strip()
    else:
        version = "Testing"
    managed.append("Reloaded/InstallerFiles.json")
    write_json(
        managed_path,
        {
            "schema": 1,
            "version": version,
            "channel": "testing",
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "files": sorted(set(managed), key=str.lower),
        },
    )
    return version


def managed_files(path):
    data = read_json(path) or {}
    return [safe_relative(value) for value in data.get("files", [])]


def remove_obsolete(game_root, old_files, new_files):
    current = {value.lower() for value in new_files}
    removed = 0
    for relative in old_files:
        if relative.lower() in current or protected(relative):
            continue
        target = os.path.abspath(os.path.join(game_root, relative))
        if not inside(game_root, target):
            continue
        if os.path.isfile(target) or os.path.islink(target):
            os.remove(target)
            removed += 1
    print("Removed {} obsolete managed Core file(s).".format(removed))


def latest_full_spritepack(catalog):
    full = [row for row in catalog.get("files", []) if row.get("full") is True]
    if not full:
        raise RuntimeError("The online Spritepack catalog has no Full Spritepack.")
    latest = [row for row in full if row.get("latest") is True]
    pack = (latest or full)[0]
    if not pack.get("build_id"):
        raise RuntimeError("The published Full Spritepack entry has no build_id.")
    return pack


def installed_spritepack_id(game_root):
    data = read_json(
        os.path.join(game_root, "Graphics", "SpritePacks", "manifest.json")
    )
    return str((data or {}).get("build_id", ""))


def write_spritepack_state(game_root, spritepack):
    path = os.path.join(game_root, "Mods", "Reloaded", "SpritepacksInstalled.json")
    data = read_json(path) or {"version": 1, "files": {}}
    files = data.get("files")
    if not isinstance(files, dict):
        files = {}
    parts = list(spritepack.get("parts") or [])
    source_url = str(spritepack.get("url", ""))
    if not source_url and parts:
        source_url = str(parts[0].get("url", ""))
    identifier = str(spritepack["id"])
    files[identifier] = {
        "id": identifier,
        "name": str(spritepack.get("name", "Full Spritepack")),
        "url": source_url,
        "components": [],
        "updated_at": str(spritepack.get("updated_at", "")),
        "full": True,
        "monthly": False,
        "manual": False,
        "files_total": 0,
        "files_copied": 0,
        "files_skipped": 0,
        "files_failed": 0,
        "import_elapsed_seconds": "0.00",
        "installed_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "destination": ".",
    }
    write_json(path, {"version": 1, "files": files})


def choose(title, options):
    while True:
        print("\n" + title)
        for index, option in enumerate(options, 1):
            print("  {}. {}".format(index, option))
        answer = input("Select an option: ").strip()
        if answer.isdigit() and 1 <= int(answer) <= len(options):
            return int(answer)
        print("Enter a number from 1 to {}.".format(len(options)))


def file_uri(path):
    return urllib.parse.urljoin("file:", urllib.request.pathname2url(os.path.abspath(path)))


def main():
    parser = argparse.ArgumentParser(description="Hoenn Reloaded AIO Installer")
    parser.add_argument(
        "--game-root", default=os.path.dirname(os.path.abspath(__file__))
    )
    parser.add_argument("--channel", choices=("public", "testing"), default="")
    parser.add_argument("--install-type", choices=("core", "full"), default="")
    parser.add_argument("--public-manifest-url", default=PUBLIC_MANIFEST_URL)
    parser.add_argument("--testing-archive-url", default=TESTING_ARCHIVE_URL)
    parser.add_argument("--spritepack-catalog-url", default=SPRITEPACK_CATALOG_URL)
    parser.add_argument("--manifest-file", default="")
    parser.add_argument("--testing-archive-file", default="")
    parser.add_argument("--spritepack-catalog-file", default="")
    parser.add_argument("--repair", action="store_true")
    parser.add_argument("--keep-downloads", action="store_true")
    args = parser.parse_args()

    game_root = os.path.abspath(args.game_root)
    path_hash = hashlib.sha256(game_root.lower().encode("utf-8")).hexdigest()[:12]
    temp_root = os.path.join(
        tempfile.gettempdir(), "HoennReloadedInstaller", path_hash
    )
    stage_root = os.path.join(temp_root, "TestingStage")
    managed_path = os.path.join(game_root, "Reloaded", "InstallerFiles.json")
    previous_managed = os.path.join(temp_root, "PreviousInstallerFiles.json")
    os.makedirs(temp_root, exist_ok=True)

    print("\n============================================================")
    print(" Hoenn Reloaded Installer - Proton")
    print("============================================================")
    print(" Install directory: {}".format(game_root))

    channel = args.channel
    if not channel:
        channel = (
            "public"
            if choose(
                "Choose a game channel:",
                ("Hoenn Reloaded", "Hoenn Reloaded Testing"),
            )
            == 1
            else "testing"
        )
    install_type = args.install_type
    if not install_type:
        install_type = (
            "core"
            if choose("Choose what to install:", ("Core", "Core + Spritepacks"))
            == 1
            else "full"
        )
    include_spritepacks = install_type == "full"
    print("\n Channel: {}".format(channel.title()))
    print(
        " Package: {}".format(
            "Core + Spritepacks" if include_spritepacks else "Core"
        )
    )
    print(" Existing saves, mods, settings, profiles, and imports are preserved.")

    print("\n[1/5] Checking source")
    public_manifest = None
    if channel == "public":
        public_manifest = json_source(
            args.manifest_file,
            args.public_manifest_url,
            temp_root,
            "Public Core manifest",
        )
        if (
            int(public_manifest.get("schema", 0)) not in (1, 2)
            or public_manifest.get("ready") is False
            or not public_manifest.get("core")
        ):
            raise RuntimeError("The Public Core manifest is invalid or not ready.")
        version = str(public_manifest.get("version", "unknown"))
        core = public_manifest["core"]
        core_name = str(
            core.get("file")
            or os.path.basename(urllib.parse.urlparse(core["url"]).path)
        )
        core_path = os.path.join(temp_root, core_name)
    else:
        version = "Testing"
        core_path = os.path.join(temp_root, "Hoenn-Reloaded-Testing-main.zip")
    print("Selected version: {}".format(version))

    if os.path.isfile(previous_managed):
        old_files = managed_files(previous_managed)
    else:
        old_files = managed_files(managed_path)
        if os.path.isfile(managed_path):
            shutil.copyfile(managed_path, previous_managed)

    print("\n[2/5] Downloading Core")
    if channel == "public":
        download(
            core["url"],
            core_path,
            core.get("size", 0),
            core.get("sha256", ""),
            "Hoenn Reloaded Public Core",
        )
    else:
        testing_url = (
            file_uri(args.testing_archive_file)
            if args.testing_archive_file
            else args.testing_archive_url
        )
        download(
            testing_url,
            core_path,
            label="Hoenn Reloaded Testing",
            force=True,
        )

    print("\n[3/5] Installing Core")
    if channel == "public":
        extract_direct(core_path, game_root, "Hoenn Reloaded Public Core")
    else:
        version = install_testing_snapshot(
            core_path, stage_root, game_root, managed_path
        )
    new_files = managed_files(managed_path)
    if not new_files:
        raise RuntimeError("The installed Core did not provide a managed file inventory.")

    print(
        "\n[4/5] {}".format(
            "Checking Spritepacks" if include_spritepacks else "Preserving Spritepacks"
        )
    )
    sprite_paths = []
    if include_spritepacks:
        catalog_url = str(
            (public_manifest or {}).get(
                "spritepack_catalog_url", args.spritepack_catalog_url
            )
        )
        catalog = json_source(
            args.spritepack_catalog_file,
            catalog_url,
            temp_root,
            "Spritepack catalog",
        )
        spritepack = latest_full_spritepack(catalog)
        wanted = str(spritepack["build_id"])
        installed = installed_spritepack_id(game_root)
        if args.repair or not installed or installed != wanted:
            parts = list(spritepack.get("parts") or [])
            if parts:
                for index, part in enumerate(parts, 1):
                    name = str(
                        part.get("file")
                        or os.path.basename(urllib.parse.urlparse(part["url"]).path)
                    )
                    path = os.path.join(temp_root, name)
                    download(
                        part["url"],
                        path,
                        part.get("size", 0),
                        part.get("sha256", ""),
                        "Full Spritepack part {}/{}".format(index, len(parts)),
                    )
                    sprite_paths.append(path)
                extract_direct(
                    sprite_paths,
                    game_root,
                    "Full Spritepack",
                    allow_protected=True,
                )
            else:
                if not spritepack.get("url"):
                    raise RuntimeError(
                        "Full Spritepack has no download URL or parts."
                    )
                name = os.path.basename(
                    urllib.parse.urlparse(spritepack["url"]).path
                )
                path = os.path.join(temp_root, name)
                download(
                    spritepack["url"],
                    path,
                    spritepack.get("size", 0),
                    spritepack.get("sha256", ""),
                    "Full Spritepack",
                )
                sprite_paths.append(path)
                extract_direct(
                    path, game_root, "Full Spritepack", allow_protected=True
                )
            if installed_spritepack_id(game_root) != wanted:
                raise RuntimeError(
                    "The installed Full Spritepack manifest does not match the catalog."
                )
            write_spritepack_state(game_root, spritepack)
        else:
            print("Full Spritepack {} is already installed.".format(installed))
    else:
        print("Core-only selected. Existing Spritepacks were not changed.")

    print("\n[5/5] Finalizing installation")
    remove_obsolete(game_root, old_files, new_files)
    if os.path.isfile(previous_managed):
        os.remove(previous_managed)
    if os.path.isdir(stage_root):
        shutil.rmtree(stage_root)
    if not args.keep_downloads:
        for path in [core_path] + sprite_paths:
            if path and os.path.isfile(path):
                os.remove(path)
    print(
        "\nHoenn Reloaded {} ({}) is installed.".format(channel.title(), version)
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("\nERROR: {}".format(error), file=sys.stderr)
        print(
            "Rerun the installer to resume or repair the installation.",
            file=sys.stderr,
        )
        sys.exit(1)
