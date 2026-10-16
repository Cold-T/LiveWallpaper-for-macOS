#!/usr/bin/env python3
"""Publish real per-player helper output to a bounded, versioned PE snapshot.

Default mode requires a fixture. Live mode must explicitly name a player and
--allow-automation. It never asks for permission or starts a player. Fixture
snapshots are labelled in flags and rejected by the PE DLL unless an explicit
LWMEDIA_ALLOW_FIXTURE=1 opt-in is set. No network/artwork downloads occur.
"""
import argparse
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import time
import base64
import urllib.parse
import urllib.request

MAGIC = b"LWMEDIA1"
HEADER = struct.Struct("<8sIIIIqqqq")
SLOTS = (128, 512, 256, 256)
MAX_ART = 16 * 1024 * 1024
SIZE = HEADER.size + sum(n * 2 for n in SLOTS)
ART_HEADER = struct.Struct("<8sIIII")
COMMAND = struct.Struct("<8sIIq256s")
ACK = struct.Struct("<8sIIII")
CAPABILITIES = {"play":1,"pause":2,"next":3,"previous":4,"toggle":5,"seek":6}


def fetch_artwork(payload, cache, opener=urllib.request.urlopen):
    """Optional real HTTPS artwork fetch; never called by default or fixtures."""
    session = payload.get("session", payload)
    if not isinstance(session, dict) or session.get("artworkBase64"):
        return payload
    url = session.get("artworkURL")
    if not isinstance(url, str):
        return payload
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        return payload
    try:
        if url not in cache:
            request = urllib.request.Request(url, headers={"User-Agent":"LiveWallpaper-MediaBridge/1"})
            with opener(request, timeout=5) as response:
                if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                    return payload
                image = response.read(MAX_ART + 1)
            if len(image) > MAX_ART:
                return payload
            mime = "image/png" if image.startswith(b"\x89PNG\r\n\x1a\n") else "image/jpeg" if image.startswith(b"\xff\xd8") else None
            if not mime:
                return payload
            if len(cache) >= 32:
                cache.pop(next(iter(cache)))
            cache[url] = image, mime
        image, mime = cache[url]
        session["artworkBase64"] = base64.b64encode(image).decode("ascii")
        session["artworkMimeType"] = mime
    except (OSError, ValueError):
        # Metadata remains usable and Thumbnail stays null; no fake cover bytes.
        pass
    return payload


def utf16(value, units):
    text = str(value or "")
    raw = text.encode("utf-16-le")[:(units - 1) * 2]
    # Never terminate with an unmatched UTF-16 high surrogate.
    if raw and 0xD800 <= int.from_bytes(raw[-2:], "little") <= 0xDBFF:
        raw = raw[:-2]
    return raw + b"\0" * (units * 2 - len(raw))


def ticks(value):
    if not isinstance(value, (float, int)) or not math.isfinite(value):
        return 0
    return max(0, min(int(value * 10_000_000), 2**63 - 1))


def pack_snapshot(payload, generation, fixture=False):
    if not isinstance(payload, dict):
        raise ValueError("snapshot must be an object")
    session = payload.get("session", payload)
    if not isinstance(session, dict):
        raise ValueError("session must be an object")
    bundle = session.get("bundleIdentifier")
    available = payload.get("available", bool(bundle)) and bool(bundle)
    flags = int(bool(available)) | (2 if fixture else 0)
    capabilities = session.get("capabilities", {})
    if isinstance(capabilities, dict):
        for key, bit in CAPABILITIES.items():
            if capabilities.get(key) is True:
                flags |= 1 << (7 + bit)
    state = {"playing": 4, "paused": 5, "stopped": 3}.get(session.get("state"), 0)
    observed = session.get("observedUnixSeconds", time.time())
    observed = observed if isinstance(observed, (int, float)) and math.isfinite(observed) else time.time()
    # WinRT DateTime uses 1601 epoch, TimeSpan uses 100ns.
    timestamp = int((observed + 11644473600) * 10_000_000)
    header = HEADER.pack(MAGIC, 1, SIZE, generation, flags, state,
                         ticks(session.get("durationSeconds")), ticks(session.get("positionSeconds")), timestamp)
    data = header + b"".join(utf16(session.get(k), n) for k, n in
                            zip(("bundleIdentifier", "title", "artist", "album"), SLOTS))
    return data, {"schemaVersion": 1, "fixture": fixture, "generation": generation,
                  "available": bool(available), "observedWinRTTicks": timestamp,
                  "session": session}


def publish(output, payload, generation, fixture=False):
    data, info = pack_snapshot(payload, generation, fixture)
    output = Path(output)
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = output.with_name(output.name + f".{os.getpid()}.tmp")
    session = info["session"]
    artwork = b""
    mime = 0
    value = session.get("artworkBase64")
    if isinstance(value, str) and len(value) <= MAX_ART * 2:
        candidate = base64.b64decode(value, validate=True)
        if len(candidate) > MAX_ART:
            raise ValueError("artwork too large")
        if candidate.startswith(b"\xff\xd8"):
            artwork, mime = candidate, 1
        elif candidate.startswith(b"\x89PNG\r\n\x1a\n"):
            artwork, mime = candidate, 2
    art_temp = temporary.with_suffix(".art.tmp")
    art_temp.write_bytes(ART_HEADER.pack(b"LWMART01", 1, generation, mime, len(artwork)) + artwork)
    os.chmod(art_temp, 0o600)
    versioned_art = Path(str(output) + f".art.{generation}")
    os.replace(art_temp, versioned_art)
    os.link(versioned_art, art_temp)
    os.replace(art_temp, Path(str(output) + ".art"))
    temporary.write_bytes(data)
    os.chmod(temporary, 0o600)
    os.replace(temporary, output)
    # Human-readable provenance is separate from the strict ABI payload.
    provenance = output.with_suffix(output.suffix + ".json")
    provenance_temporary = temporary.with_suffix(".json.tmp")
    provenance_temporary.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")
    os.chmod(provenance_temporary, 0o600)
    os.replace(provenance_temporary, provenance)
    # Keep a bounded history so a properties object can obtain its matching
    # artwork while a new snapshot is being published; bytes are captured in PE.
    versions = [p for p in output.parent.glob(output.name + ".art.*")
                if p.name.rsplit(".",1)[-1].isdigit()]
    for old in sorted(versions,key=lambda p:p.stat().st_mtime_ns,reverse=True)[8:]:
        old.unlink(missing_ok=True)
    return info


def handle_requests(directory, player, helper, fixture, runner=subprocess.run):
    """Consume bounded requests from this user's private directory; no implicit consent."""
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_mode & 0o077:
        raise ValueError("command directory must be private (0700)")
    bundle = {"music":"com.apple.Music", "spotify":"com.spotify.client"}.get(player)
    commands = {1:"play",2:"pause",3:"next",4:"previous",5:"toggle",6:"seek"}
    for request in sorted(directory.glob("*.req"))[:32]:
        # A GUID generated by the PE caller is the only accepted filename.
        import uuid
        processing = None
        try:
            if str(uuid.UUID(request.stem)).lower() != request.stem.lower() or request.is_symlink():
                continue
            ack_path = request.with_suffix(".ack")
            if ack_path.exists():
                request.unlink()
                continue
            descriptor = os.open(request, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "rb") as stream:
                raw = stream.read(COMMAND.size + 1)
            # Reserve before invoking the player. Failed/ambiguous execution must
            # never be retried automatically (especially next-track/seek).
            processing = request.with_suffix(".processing")
            os.replace(request, processing)
            ok, error = False, 0
            if len(raw) != COMMAND.size:
                error = 0x80070057
            else:
                magic, version, command, position, target = COMMAND.unpack(raw)
                target = target.decode("utf-16-le").split("\0",1)[0]
                if magic != b"LWMCMD01" or version != 1 or command not in commands or position < 0:
                    error = 0x80070057
                elif fixture:
                    # Fixtures never send real commands or synthesize success.
                    error = 0x80070005
                elif not bundle or target != bundle:
                    error = 0x80070005
                else:
                    args = [str(Path(helper).resolve()), "--command", commands[command], "--player", player, "--allow-automation"]
                    if command == 6:
                        args += ["--position", str(position / 10_000_000)]
                    result = runner(args, capture_output=True, text=True, timeout=10)
                    response = json.loads(result.stdout)
                    ok = result.returncode == 0 and response.get("ok") is True
                    if not ok:
                        error = 0x80070005 if response.get("error") == "automation_permission_required" else 0x80004005
            temporary = ack_path.with_suffix(".ack.tmp")
            temporary.write_bytes(ACK.pack(b"LWMACK01",1,int(ok),error,2 if fixture else 0))
            os.chmod(temporary, 0o600)
            os.replace(temporary, ack_path)
            processing.unlink()
        except (ValueError, UnicodeError, OSError, subprocess.SubprocessError):
            if processing is not None:
                try:
                    temporary = ack_path.with_suffix(".ack.tmp")
                    temporary.write_bytes(ACK.pack(b"LWMACK01",1,0,0x80004005,2 if fixture else 0))
                    os.chmod(temporary,0o600)
                    os.replace(temporary,ack_path)
                    processing.unlink(missing_ok=True)
                except OSError:
                    pass
            # Invalid/replaced paths cannot cause fake acknowledgements or replay.
            continue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--fixture", type=Path)
    source.add_argument("--player", choices=("music", "spotify"))
    parser.add_argument("--allow-automation", action="store_true")
    parser.add_argument("--helper", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--commands-dir", type=Path)
    parser.add_argument("--fetch-artwork", action="store_true", help="opt in to fetching real HTTPS player artwork (live mode only)")
    args = parser.parse_args()
    if args.player and (not args.allow_automation or not args.helper):
        parser.error("live mode requires --helper and explicit --allow-automation; permission is never requested here")
    generation = 0
    artwork_cache = {}
    while True:
        if args.fixture:
            payload = json.loads(args.fixture.read_text())
        else:
            result = subprocess.run([str(args.helper.resolve()), "--snapshot", "--player", args.player,
                                     "--allow-automation"], capture_output=True, text=True, timeout=10)
            if result.returncode:
                raise RuntimeError(f"helper failed ({result.returncode}): {result.stderr[:500]}")
            payload = json.loads(result.stdout)
            if args.fetch_artwork:
                payload = fetch_artwork(payload, artwork_cache)
        generation += 1
        info = publish(args.output, payload, generation, bool(args.fixture))
        print(json.dumps({k: info[k] for k in ("fixture", "generation", "available")}), flush=True)
        if args.commands_dir:
            handle_requests(args.commands_dir, args.player, args.helper, bool(args.fixture))
        if not args.watch:
            break
        time.sleep(max(0.25, args.interval))


if __name__ == "__main__":
    main()
