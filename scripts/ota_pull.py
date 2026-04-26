#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile
from urllib.parse import urlparse

try:
    from payload_dumper.update_metadata_pb2 import DeltaArchiveManifest
except ImportError:
    print("[-] Missing required package: payload_dumper.update_metadata_pb2", file=sys.stderr)
    sys.exit(1)


TARGETS = ("boot", "init_boot")


def die(msg, code=1):
    print(f"[-] {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg):
    print(f"[+] {msg}")


def is_url(value):
    p = urlparse(value)
    return p.scheme in ("http", "https") and bool(p.netloc)


def have_cmd(cmd):
    return shutil.which(cmd) is not None


def ensure_payload_dumper():
    if have_cmd("payload_dumper"):
        return ["payload_dumper"]

    try:
        subprocess.run(
            [sys.executable, "-m", "payload_dumper", "--help"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return [sys.executable, "-m", "payload_dumper"]
    except Exception:
        die("payload_dumper CLI not available")


def parse_args():
    ap = argparse.ArgumentParser(description="Pull stock boot/init_boot from a full OTA ZIP URL or local OTA ZIP")
    ap.add_argument("--source", required=True, help="Full OTA ZIP URL or local ota.zip")
    ap.add_argument("--partition", required=True, choices=["boot", "init_boot", "both"], help="Partition to extract")
    ap.add_argument("--outdir", required=True, help="Output directory")
    return ap.parse_args()


def validate_source_kind(source):
    if is_url(source):
        if source.lower().endswith(".bin"):
            die("Direct payload.bin URLs are not allowed. Use a full OTA ZIP URL.")
        return "remote_zip"

    if not os.path.exists(source):
        die(f"Source not found: {source}")

    if os.path.isdir(source):
        die("Source is a directory, not a full OTA ZIP.")

    if source.lower().endswith(".bin"):
        die("Direct payload.bin input is not allowed. Use a full OTA ZIP file.")

    if not zipfile.is_zipfile(source):
        die("Source is not a valid ZIP file. Full OTA ZIP required.")

    return "local_zip"


def open_remote_zip(source):
    from remotezip import RemoteZip
    try:
        return RemoteZip(source)
    except Exception as e:
        die(f"Failed to open remote ZIP: {e}")


def get_zip_entry_names(source, source_kind):
    if source_kind == "local_zip":
        with zipfile.ZipFile(source, "r") as zf:
            return zf.namelist()

    if source_kind == "remote_zip":
        rz = open_remote_zip(source)
        try:
            return rz.namelist()
        finally:
            rz.close()

    die(f"Unsupported source kind: {source_kind}")


def ensure_full_ota_structure(entry_names):
    needed = {"payload.bin", "payload_properties.txt"}
    missing = [x for x in needed if x not in entry_names]
    if missing:
        die(
            "ZIP does not look like a supported full OTA package.\n"
            f"Missing required entry(s): {', '.join(missing)}"
        )


def read_payload_properties(source, source_kind):
    if source_kind == "local_zip":
        with zipfile.ZipFile(source, "r") as zf:
            try:
                return zf.read("payload_properties.txt").decode("utf-8", errors="replace")
            except KeyError:
                die("payload_properties.txt not found in local ZIP")

    if source_kind == "remote_zip":
        rz = open_remote_zip(source)
        try:
            return rz.read("payload_properties.txt").decode("utf-8", errors="replace")
        except KeyError:
            die("payload_properties.txt not found in remote ZIP")
        finally:
            rz.close()

    die(f"Unsupported source kind: {source_kind}")


def abort_if_incremental(payload_props_text):
    lowered = payload_props_text.lower()
    suspicious = [
        "delta",
        "incremental",
        "old_build",
        "old-version",
        "pre-build",
        "pre-build-incremental",
    ]
    found = [s for s in suspicious if s in lowered]
    if found:
        die("Incremental/delta OTA detected or suspected. Full OTA ZIP required.")


def open_payload_stream(source, source_kind):
    if source_kind == "local_zip":
        zf = zipfile.ZipFile(source, "r")
        try:
            return zf.open("payload.bin")
        except KeyError:
            zf.close()
            die("payload.bin not found in local ZIP")

    if source_kind == "remote_zip":
        rz = open_remote_zip(source)
        try:
            return rz.open("payload.bin")
        except KeyError:
            rz.close()
            die("payload.bin not found in remote ZIP")

    die(f"Unsupported source kind: {source_kind}")


def read_exact(fp, n):
    data = fp.read(n)
    if len(data) != n:
        die(f"Failed to read {n} bytes from payload stream")
    return data


def read_manifest_from_payload_stream(source, source_kind):
    fp = open_payload_stream(source, source_kind)
    try:
        magic = read_exact(fp, 4)
        if magic != b"CrAU":
            die("payload.bin exists but does not have a valid CrAU header")

        version = struct.unpack(">Q", read_exact(fp, 8))[0]
        manifest_size = struct.unpack(">Q", read_exact(fp, 8))[0]

        sig_size = 0
        if version >= 2:
            sig_size = struct.unpack(">I", read_exact(fp, 4))[0]

        manifest_bytes = read_exact(fp, manifest_size)

        manifest = DeltaArchiveManifest()
        manifest.ParseFromString(manifest_bytes)
        return manifest, version, sig_size
    finally:
        fp.close()


def detect_available_targets_from_full_ota(source):
    source_kind = validate_source_kind(source)
    entry_names = get_zip_entry_names(source, source_kind)
    ensure_full_ota_structure(entry_names)

    props = read_payload_properties(source, source_kind)
    abort_if_incremental(props)

    manifest, version, sig_size = read_manifest_from_payload_stream(source, source_kind)

    all_parts = [p.partition_name for p in manifest.partitions]
    found = [p for p in TARGETS if p in all_parts]

    return found, all_parts, version, sig_size, source_kind


def sanitize_name(text):
    text = re.sub(r"[^\w.\-]+", "-", text.strip(), flags=re.UNICODE)
    text = re.sub(r"-{2,}", "-", text)
    return text.strip("-._") or "ota"


def parse_ota_basename(source):
    raw = source
    if is_url(source):
        parsed = urlparse(source)
        raw = os.path.basename(parsed.path)

    raw = os.path.basename(raw)
    if raw.lower().endswith(".zip"):
        raw = raw[:-4]

    return sanitize_name(raw)


def extract_short_ota_label(source):
    base = parse_ota_basename(source)

    codename = None
    if "-ota-" in base:
        codename = base.split("-ota-", 1)[0].lower()
    else:
        parts = base.split("-")
        if parts:
            first = parts[0].lower()
            if first and first not in ("ota", "full"):
                codename = first

    date_match = re.search(r"\b[a-z0-9]+\.(\d{6})\.\d{3}\b", base, re.IGNORECASE)
    short_date = date_match.group(1) if date_match else None

    pieces = []
    if codename:
        pieces.append(codename)
    if short_date:
        pieces.append(short_date)

    if pieces:
        return "-".join(pieces)

    return base


def build_output_filename(partition, source):
    label = extract_short_ota_label(source)
    return f"{partition}-{label}.img"


def rename_outputs(outdir, partitions, source):
    renamed = []
    for partition in partitions:
        src = os.path.join(outdir, f"{partition}.img")
        if not os.path.exists(src):
            continue

        dst = os.path.join(outdir, build_output_filename(partition, source))
        if os.path.abspath(src) == os.path.abspath(dst):
            renamed.append(dst)
            continue

        if os.path.exists(dst):
            base, ext = os.path.splitext(dst)
            dst = f"{base}-runner{ext}"

        os.replace(src, dst)
        renamed.append(dst)

    return renamed


def extract_partitions(source, outdir, partitions):
    dumper = ensure_payload_dumper()
    os.makedirs(outdir, exist_ok=True)

    cmd = dumper + ["--out", outdir, "--partitions", ",".join(partitions), source]

    info(f"Extracting: {', '.join(partitions)}")
    info(f"Output directory: {os.path.abspath(outdir)}")
    info(f"OTA label: {extract_short_ota_label(source)}")

    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        die(f"Extraction failed with exit code {e.returncode}")

    info("Extraction complete")
    return rename_outputs(outdir, partitions, source)


def main():
    args = parse_args()

    partitions = ["boot", "init_boot"] if args.partition == "both" else [args.partition]

    found, all_parts, version, sig_size, source_kind = detect_available_targets_from_full_ota(args.source)

    info(f"Source type: {source_kind}")
    info(f"Payload version: {version}")
    info(f"Metadata signature bytes: {sig_size}")
    info(f"Partitions in manifest: {len(all_parts)}")
    info("Detected target partitions: " + ", ".join(found))

    missing = [p for p in partitions if p not in found]
    if missing:
        die("Requested partition(s) not present in OTA: " + ", ".join(missing))

    renamed_paths = extract_partitions(args.source, args.outdir, partitions)

    info("Result:")
    for path in renamed_paths:
        print(f"    OK  {path}")

    if not renamed_paths:
        die("No output image was produced.")


if __name__ == "__main__":
    main()
