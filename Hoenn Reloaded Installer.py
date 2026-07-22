#!/usr/bin/env python3
"""AIO installer for Hoenn Reloaded under Proton and Steam Deck."""

import argparse
import bisect
import concurrent.futures
import email.utils
import hashlib
import io
import json
import os
import re
import random
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile


DOWNLOAD_CONNECTIONS = 6
SEGMENTED_DOWNLOAD_MINIMUM = 24 * 1024 * 1024
DOWNLOAD_RETRIES = 3
DOWNLOAD_RETRY_DELAY = 1.0
DISK_SPACE_MARGIN = 64 * 1024 * 1024
INSTALLER_VERSION = "4.2.0"
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
    "reloaded/installerincomplete.json",
    "graphics/custombattlers/sprite import/",
    "graphics/spritepacks/",
    ".git/",
)
TESTING_EXCLUDED_PATTERNS = tuple(
    re.compile(value, re.IGNORECASE)
    for value in (
        r"^(?:\.agents|\.codex|\.git|\.github|\.vscode)/",
        r"^(?:Admin Tools|Developer Tools)/",
        r"^ModDev/(?!Tools(?:/|$))",
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
        r"^Reloaded/InstallerIncomplete\.json$",
        r"^Reloaded/Documentation/(?:To-Do|VanillaChanges|ReloadedMart-To-Do)\.md$",
        r"^\.gitignore$",
        r"^\.DS_Store$",
        r"^outside\.zip$",
    )
)


class RangeUnsupported(RuntimeError):
    pass


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
        amount = " {:.1f}/{:.1f} MB".format(
            current / 1048576.0, total / 1048576.0
        )
        prefix = label + " ["
        suffix = "] {:3d}%{}".format(percent, amount)
        columns = shutil.get_terminal_size((120, 24)).columns
        width = max(16, columns - len(prefix) - len(suffix) - 1)
        filled = int(width * percent / 100)
        bar = ""
        if filled:
            bar += "\033[46m" + (" " * filled) + "\033[0m"
        if width - filled:
            bar += "\033[100m" + (" " * (width - filled)) + "\033[0m"
        text = "\r\033[2K{}{}{}".format(prefix, bar, suffix)
    else:
        text = "\r\033[2K{} {:.1f} MB".format(label, current / 1048576.0)
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


def part_meta_path(part):
    return part + ".meta.json"


def remove_partial(part):
    for path in (part, part_meta_path(part), part_meta_path(part) + ".tmp"):
        if os.path.isfile(path):
            os.remove(path)


def write_part_meta(part, value):
    path = part_meta_path(part)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8", newline="\n") as target:
        json.dump(value, target, separators=(",", ":"))
    os.replace(temporary, path)


def read_part_meta(part):
    try:
        with open(part_meta_path(part), "r", encoding="utf-8") as source:
            return json.load(source)
    except (OSError, ValueError, TypeError):
        return None


def url_digest(url):
    return hashlib.sha256(str(url).encode("utf-8")).hexdigest()


def remote_info(url):
    request = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "HoennReloadedInstaller/4"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return {
                "size": int(response.headers.get("Content-Length", "0") or 0),
                "etag": str(response.headers.get("ETag", "") or ""),
                "last_modified": str(
                    response.headers.get("Last-Modified", "") or ""
                ),
            }
    except (OSError, ValueError, urllib.error.URLError):
        return {"size": 0, "etag": "", "last_modified": ""}


def retry_after(error):
    headers = getattr(error, "headers", None)
    value = str(headers.get("Retry-After", "") if headers else "").strip()
    try:
        return max(0.0, float(value))
    except (TypeError, ValueError):
        pass
    try:
        parsed = email.utils.parsedate_to_datetime(value)
        return max(0.0, parsed.timestamp() - time.time())
    except (TypeError, ValueError, OverflowError):
        return 0.0


def retry_sleep(error, attempt):
    delay = DOWNLOAD_RETRY_DELAY * (2 ** max(0, attempt - 1))
    delay += random.random() * min(0.5, delay * 0.25)
    delay = max(delay, retry_after(error))
    print("Retrying in {:.1f} seconds...".format(delay))
    time.sleep(delay)


def ensure_disk_space(path, required, label):
    required = max(0, int(required or 0))
    if required <= 0:
        return
    root = path if os.path.isdir(path) else os.path.dirname(path)
    os.makedirs(root, exist_ok=True)
    free = shutil.disk_usage(root).free
    needed = required + DISK_SPACE_MARGIN
    if free < needed:
        raise RuntimeError(
            "Not enough free disk space for {}. Required {:.2f} GB; "
            "available {:.2f} GB.".format(
                label, needed / 1073741824.0, free / 1073741824.0
            )
        )


def valid_resume_meta(meta, url, total, info, mode):
    if not isinstance(meta, dict):
        return False
    if (
        int(meta.get("version", 0)) != 1
        or meta.get("mode") != mode
        or meta.get("url_sha256") != url_digest(url)
        or int(meta.get("total", 0)) != int(total)
    ):
        return False
    etag = str(info.get("etag", ""))
    modified = str(info.get("last_modified", ""))
    if etag and str(meta.get("etag", "")) != etag:
        return False
    if not etag and modified and str(meta.get("last_modified", "")) != modified:
        return False
    return True


def valid_segment_ranges(saved, expected):
    if not isinstance(saved, list) or len(saved) != len(expected):
        return False
    for row, wanted in zip(saved, expected):
        start = int(row.get("start", -1))
        end = int(row.get("end", -1))
        received = int(row.get("received", -1))
        length = int(wanted["end"]) - int(wanted["start"]) + 1
        if (
            start != int(wanted["start"])
            or end != int(wanted["end"])
            or received < 0
            or received > length
        ):
            return False
    return True


def segmented_received_bytes(meta, total, info, url):
    if not valid_resume_meta(meta, url, total, info, "segmented"):
        return -1
    base_size = total // DOWNLOAD_CONNECTIONS
    expected = []
    for index in range(DOWNLOAD_CONNECTIONS):
        start = index * base_size
        end = total - 1 if index == DOWNLOAD_CONNECTIONS - 1 else (
            ((index + 1) * base_size) - 1
        )
        expected.append({"start": start, "end": end})
    saved = meta.get("ranges")
    if not valid_segment_ranges(saved, expected):
        return -1
    return min(total, sum(int(row.get("received", 0)) for row in saved))


def download_single_http(url, part, expected_size, label, info, allow_resume=True):
    meta = read_part_meta(part)
    total_hint = int(expected_size or info.get("size", 0) or 0)
    if not valid_resume_meta(meta, url, total_hint, info, "single"):
        remove_partial(part)
        meta = None
    existing = os.path.getsize(part) if allow_resume and os.path.isfile(part) else 0
    if expected_size and existing > int(expected_size):
        remove_partial(part)
        existing = 0

    request = urllib.request.Request(
        url, headers={"User-Agent": "HoennReloadedInstaller/4"}
    )
    if existing:
        request.add_header("Range", "bytes={}-".format(existing))
        validator = str(info.get("etag") or info.get("last_modified") or "")
        if validator:
            request.add_header("If-Range", validator)
    response = urllib.request.urlopen(request, timeout=30)

    append = existing > 0 and response.getcode() == 206
    if not append:
        remove_partial(part)
        existing = 0
    total = int(expected_size or 0)
    if not total:
        length = int(response.headers.get("Content-Length", "0") or 0)
        total = existing + length if length else 0
    mode = "ab" if append else "wb"
    received = existing
    state = {
        "version": 1,
        "mode": "single",
        "url_sha256": url_digest(url),
        "total": total,
        "etag": str(info.get("etag", "")),
        "last_modified": str(info.get("last_modified", "")),
        "received": received,
    }
    write_part_meta(part, state)
    last_progress = 0.0
    with response, open(part, mode) as target:
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            target.write(block)
            received += len(block)
            state["received"] = received
            now = time.monotonic()
            if now - last_progress >= 0.25:
                write_part_meta(part, state)
                print_progress("Downloading " + label, received, total)
                last_progress = now
    write_part_meta(part, state)
    print_progress("Downloading " + label, received, total)
    print()


def download_range(url, part, row, info, state, lock):
    segment_size = (int(row["end"]) - int(row["start"])) + 1
    existing = int(row.get("received", 0))
    if existing >= segment_size:
        return

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "HoennReloadedInstaller/4",
            "Range": "bytes={}-{}".format(int(row["start"]) + existing, row["end"]),
        },
    )
    validator = str(info.get("etag") or info.get("last_modified") or "")
    if validator:
        request.add_header("If-Range", validator)
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.getcode() != 206:
            raise RangeUnsupported("Server rejected ranged download.")
        expected_start = int(row["start"]) + existing
        content_range = str(response.headers.get("Content-Range", ""))
        match = re.match(r"(?i)^bytes\s+(\d+)-(\d+)/(\d+|\*)$", content_range)
        if (
            not match
            or int(match.group(1)) != expected_start
            or int(match.group(2)) != int(row["end"])
            or (match.group(3) != "*" and int(match.group(3)) != int(state["total"]))
        ):
            raise RangeUnsupported("Server returned the wrong byte range.")
        with open(part, "r+b", buffering=0) as target:
            target.seek(expected_start)
            remaining = segment_size - existing
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                if len(block) > remaining:
                    raise RangeUnsupported("Server returned too much ranged data.")
                target.write(block)
                remaining -= len(block)
                with lock:
                    row["received"] = int(row.get("received", 0)) + len(block)

    if int(row.get("received", 0)) != segment_size:
        raise RuntimeError("A ranged download segment was incomplete.")


def download_segmented(url, part, total_size, label, info):
    if total_size < SEGMENTED_DOWNLOAD_MINIMUM:
        return False

    base_size = total_size // DOWNLOAD_CONNECTIONS
    ranges = []
    for index in range(DOWNLOAD_CONNECTIONS):
        start = index * base_size
        end = total_size - 1 if index == DOWNLOAD_CONNECTIONS - 1 else (
            ((index + 1) * base_size) - 1
        )
        ranges.append({"start": start, "end": end, "received": 0})

    state = read_part_meta(part)
    if not (
        valid_resume_meta(state, url, total_size, info, "segmented")
        and valid_segment_ranges(state.get("ranges"), ranges)
        and os.path.isfile(part)
        and os.path.getsize(part) == total_size
    ):
        remove_partial(part)
        state = {
            "version": 1,
            "mode": "segmented",
            "url_sha256": url_digest(url),
            "total": total_size,
            "etag": str(info.get("etag", "")),
            "last_modified": str(info.get("last_modified", "")),
            "ranges": ranges,
        }
        with open(part, "wb") as target:
            target.truncate(total_size)
        write_part_meta(part, state)

    lock = threading.Lock()
    try:
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=DOWNLOAD_CONNECTIONS
        ) as executor:
            futures = [
                executor.submit(
                    download_range, url, part, row, info, state, lock
                )
                for row in state["ranges"]
            ]
            pending = set(futures)
            while pending:
                with lock:
                    snapshot = json.loads(json.dumps(state))
                    received = sum(
                        int(row.get("received", 0)) for row in state["ranges"]
                    )
                write_part_meta(part, snapshot)
                print_progress(
                    "Downloading {} ({} connections)".format(
                        label, DOWNLOAD_CONNECTIONS
                    ),
                    received,
                    total_size,
                )
                _, pending = concurrent.futures.wait(
                    pending,
                    timeout=0.25,
                    return_when=concurrent.futures.FIRST_EXCEPTION,
                )
                if any(
                    future.done() and future.exception()
                    for future in futures
                ):
                    break
            for future in futures:
                future.result()

        received = sum(
            int(row.get("received", 0)) for row in state["ranges"]
        )
        if received != total_size:
            raise RuntimeError("The ranged download was incomplete.")
    finally:
        if os.path.isfile(part):
            with lock:
                snapshot = json.loads(json.dumps(state))
            write_part_meta(part, snapshot)
    print_progress(
        "Downloading {} ({} connections)".format(label, DOWNLOAD_CONNECTIONS),
        total_size,
        total_size,
    )
    print()
    if os.path.isfile(part_meta_path(part)):
        os.remove(part_meta_path(part))
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
    if force and os.path.isfile(part):
        remove_partial(part)
    if force:
        remove_partial(part)
    elif verified(destination, expected_size, expected_hash):
        remove_partial(part)
        print("Using verified cached {}.".format(label))
        return
    elif os.path.exists(destination):
        os.remove(destination)

    parsed = urllib.parse.urlparse(url)
    if parsed.scheme == "file":
        source_path = urllib.request.url2pathname(parsed.path)
        total = os.path.getsize(source_path)
        ensure_disk_space(part, total, label)
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

    info = remote_info(url)
    download_size = int(expected_size or 0) or int(info.get("size", 0))
    resume_meta = read_part_meta(part) or {}
    existing = 0
    if os.path.isfile(part):
        if resume_meta.get("mode") == "segmented":
            resume_received = segmented_received_bytes(
                resume_meta, download_size, info, url
            )
            if resume_received >= 0 and os.path.getsize(part) == download_size:
                existing = download_size
            else:
                remove_partial(part)
        else:
            existing = os.path.getsize(part)
    ensure_disk_space(part, max(0, download_size - existing), label)
    segmented = False
    if download_size >= SEGMENTED_DOWNLOAD_MINIMUM:
        for attempt in range(1, DOWNLOAD_RETRIES + 1):
            try:
                print(
                    "Downloading {} with {} connections...".format(
                        label, DOWNLOAD_CONNECTIONS
                    )
                )
                segmented = download_segmented(
                    url, part, download_size, label, info
                )
                break
            except RangeUnsupported:
                print(
                    "The server did not accept segmented downloading. "
                    "Using one connection."
                )
                remove_partial(part)
                break
            except (OSError, urllib.error.URLError, RuntimeError) as error:
                if attempt >= DOWNLOAD_RETRIES:
                    raise
                retry_sleep(error, attempt)
    if not segmented:
        for attempt in range(1, DOWNLOAD_RETRIES + 1):
            try:
                download_single_http(
                    url, part, download_size, label, info
                )
                break
            except (OSError, urllib.error.URLError, RuntimeError) as error:
                if attempt >= DOWNLOAD_RETRIES:
                    raise
                retry_sleep(error, attempt)

    os.replace(part, destination)
    if os.path.isfile(part_meta_path(part)):
        os.remove(part_meta_path(part))
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
    temporary = path + ".tmp"
    try:
        with open(temporary, "w", encoding="utf-8", newline="\n") as target:
            json.dump(value, target, indent=2)
            target.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.isfile(temporary):
            os.remove(temporary)


def write_install_marker(
    path,
    channel,
    install_type,
    version,
    phase,
    spritepack_build_id="",
):
    try:
        existing = read_json(path) or {}
    except (OSError, ValueError):
        existing = {}
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_json(
        path,
        {
            "schema": 1,
            "state": "incomplete",
            "channel": channel,
            "install_type": install_type,
            "version": version,
            "phase": phase,
            "spritepack_build_id": spritepack_build_id,
            "started_at": str(existing.get("started_at") or now),
            "updated_at": now,
        },
    )


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


def version_parts(value):
    return tuple(int(part) for part in re.findall(r"\d+", str(value))[:4])


def version_newer(left, right):
    a = version_parts(left)
    b = version_parts(right)
    width = max(len(a), len(b), 1)
    return a + (0,) * (width - len(a)) > b + (0,) * (width - len(b))


def maybe_self_update(manifest, args, game_root, temp_root):
    if args.skip_self_update or int(manifest.get("schema", 0)) < 3:
        return
    bootstrap = manifest.get("bootstrap") or {}
    remote_version = str(bootstrap.get("version") or manifest.get("version") or "")
    minimum = str(manifest.get("minimum_installer_version") or "")
    if not (
        version_newer(remote_version, INSTALLER_VERSION)
        or (minimum and version_newer(minimum, INSTALLER_VERSION))
    ):
        return
    if not bootstrap.get("url") or not bootstrap.get("sha256"):
        raise RuntimeError("The release manifest has no hash-verified installer update.")
    update_archive = os.path.join(
        temp_root, str(bootstrap.get("file") or "InstallerUpdate.zip")
    )
    download(
        bootstrap["url"],
        update_archive,
        bootstrap.get("size", 0),
        bootstrap.get("sha256", ""),
        "Installer update",
    )
    update_root = os.path.join(temp_root, "InstallerUpdate-" + remote_version)
    if os.path.isdir(update_root):
        shutil.rmtree(update_root)
    with zipfile.ZipFile(update_archive, "r") as package:
        for entry in package.infolist():
            relative = safe_relative(entry.filename)
            destination = os.path.abspath(os.path.join(update_root, relative))
            if not inside(update_root, destination):
                raise RuntimeError("The installer update contains an unsafe path.")
        package.extractall(update_root)
    staged_installer = os.path.join(update_root, "Hoenn Reloaded Installer.py")
    if not os.path.isfile(staged_installer):
        raise RuntimeError("The installer update package is invalid.")
    script_root = os.path.dirname(os.path.abspath(__file__))
    for root, _, files in os.walk(update_root):
        for name in files:
            source = os.path.join(root, name)
            relative = safe_relative(os.path.relpath(source, update_root))
            destination = os.path.abspath(os.path.join(script_root, relative))
            if not inside(script_root, destination):
                raise RuntimeError("The installer update contains an unsafe path.")
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.copy2(source, destination)
    updated = os.path.join(script_root, "Hoenn Reloaded Installer.py")
    command = [
        sys.executable,
        updated,
        "--game-root",
        game_root,
        "--skip-self-update",
        "--public-manifest-url",
        args.public_manifest_url,
        "--testing-archive-url",
        args.testing_archive_url,
        "--spritepack-catalog-url",
        args.spritepack_catalog_url,
    ]
    if args.channel:
        command += ["--channel", args.channel]
    if args.install_type:
        command += ["--install-type", args.install_type]
    if args.manifest_file:
        command += ["--manifest-file", args.manifest_file]
    if args.testing_archive_file:
        command += ["--testing-archive-file", args.testing_archive_file]
    if args.spritepack_catalog_file:
        command += ["--spritepack-catalog-file", args.spritepack_catalog_file]
    if args.repair:
        command.append("--repair")
    if args.keep_downloads:
        command.append("--keep-downloads")
    print(
        "Updating installer {} -> {}...".format(
            INSTALLER_VERSION, remote_version
        )
    )
    raise SystemExit(subprocess.call(command, cwd=script_root))


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
                temporary = destination + ".installing"
                try:
                    with package.open(entry, "r") as source, open(temporary, "wb") as target:
                        while True:
                            block = source.read(1024 * 1024)
                            if not block:
                                break
                            target.write(block)
                            complete += len(block)
                            print_progress("Installing " + label, complete, total)
                        target.flush()
                        os.fsync(target.fileno())
                    mode = (entry.external_attr >> 16) & 0o777
                    if mode:
                        try:
                            os.chmod(temporary, mode)
                        except OSError:
                            pass
                    os.replace(temporary, destination)
                finally:
                    if os.path.isfile(temporary):
                        os.remove(temporary)
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
        temporary = destination + ".installing"
        try:
            shutil.copy2(source, temporary)
            os.replace(temporary, destination)
        finally:
            if os.path.isfile(temporary):
                os.remove(temporary)
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
        "build_id": str(spritepack.get("build_id", "")),
        "parts": parts,
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
    parser.add_argument(
        "--install-type",
        choices=("core", "full"),
        default="",
        help=argparse.SUPPRESS,
    )
    parser.add_argument("--public-manifest-url", default=PUBLIC_MANIFEST_URL)
    parser.add_argument("--testing-archive-url", default=TESTING_ARCHIVE_URL)
    parser.add_argument("--spritepack-catalog-url", default=SPRITEPACK_CATALOG_URL)
    parser.add_argument("--manifest-file", default="")
    parser.add_argument("--testing-archive-file", default="")
    parser.add_argument("--spritepack-catalog-file", default="")
    parser.add_argument("--repair", action="store_true")
    parser.add_argument("--keep-downloads", action="store_true")
    parser.add_argument("--skip-self-update", action="store_true")
    args = parser.parse_args()

    game_root = os.path.abspath(args.game_root)
    temp_root = os.path.join(
        game_root, "REQUIRED_BY_INSTALLER_UPDATER", "Cache"
    )
    stage_root = os.path.join(temp_root, "TestingStage")
    managed_path = os.path.join(game_root, "Reloaded", "InstallerFiles.json")
    incomplete_path = os.path.join(
        game_root, "Reloaded", "InstallerIncomplete.json"
    )
    previous_managed = os.path.join(temp_root, "PreviousInstallerFiles.json")
    os.makedirs(temp_root, exist_ok=True)

    print("\n============================================================")
    print(" Hoenn Reloaded Installer - Proton")
    print("============================================================")
    print(" Install directory: {}".format(game_root))

    incomplete = {}
    if os.path.isfile(incomplete_path):
        try:
            incomplete = read_json(incomplete_path) or {}
        except (OSError, ValueError):
            incomplete = {}
        args.repair = True
        if incomplete.get("channel") in ("public", "testing"):
            args.channel = incomplete["channel"]
        print("\nAn interrupted installation was detected.")
        print("Repair mode is required and has been enabled.")

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
    install_type = "full"
    args.channel = channel
    args.install_type = install_type
    include_spritepacks = True
    print("\n Channel: {}".format(channel.title()))
    print(" Package: Core + Full Spritepack")
    print(" Existing saves, mods, settings, profiles, and imports are preserved.")

    print("\n[1/5] Checking source")
    public_manifest = json_source(
        args.manifest_file,
        args.public_manifest_url,
        temp_root,
        "Public Core manifest",
    )
    if (
        int(public_manifest.get("schema", 0)) not in (1, 2, 3)
        or public_manifest.get("ready") is False
        or not public_manifest.get("core")
    ):
        raise RuntimeError("The Public Core manifest is invalid or not ready.")
    maybe_self_update(public_manifest, args, game_root, temp_root)
    if channel == "public":
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
        ensure_disk_space(
            game_root,
            int(core.get("installed_size", 0) or core.get("size", 0)),
            "Core installation",
        )
        write_install_marker(
            incomplete_path, channel, install_type, version, "core"
        )
        extract_direct(core_path, game_root, "Hoenn Reloaded Public Core")
    else:
        write_install_marker(
            incomplete_path, channel, install_type, version, "core"
        )
        version = install_testing_snapshot(
            core_path, stage_root, game_root, managed_path
        )
    new_files = managed_files(managed_path)
    if not new_files:
        raise RuntimeError("The installed Core did not provide a managed file inventory.")

    print("\n[4/5] Checking Full Spritepack")
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
            sprite_download_size = sum(
                int(row.get("size", 0) or 0)
                for row in list(spritepack.get("parts") or [])
            ) or int(spritepack.get("size", 0) or 0)
            ensure_disk_space(
                game_root,
                int(spritepack.get("installed_size", 0) or sprite_download_size),
                "Full Spritepack installation",
            )
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
                write_install_marker(
                    incomplete_path,
                    channel,
                    install_type,
                    version,
                    "spritepack",
                    wanted,
                )
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
                write_install_marker(
                    incomplete_path,
                    channel,
                    install_type,
                    version,
                    "spritepack",
                    wanted,
                )
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
    print("\n[5/5] Finalizing installation")
    write_install_marker(
        incomplete_path,
        channel,
        install_type,
        version,
        "finalizing",
        wanted,
    )
    remove_obsolete(game_root, old_files, new_files)
    if os.path.isfile(previous_managed):
        os.remove(previous_managed)
    if os.path.isdir(stage_root):
        shutil.rmtree(stage_root)
    if os.path.isfile(incomplete_path):
        os.remove(incomplete_path)
    if not args.keep_downloads:
        for path in [core_path] + sprite_paths:
            if path and os.path.isfile(path):
                os.remove(path)
        if os.path.isdir(temp_root):
            shutil.rmtree(temp_root)
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
