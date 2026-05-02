#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
from urllib.parse import urlparse

def die(msg, code=1):
    print(f"[-] {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg):
    print(f"[+] {msg}")

def parse_args():
    ap = argparse.ArgumentParser(description="Extract partitions from a validated OTA ZIP")
    ap.add_argument("--source", required=True, help="Full OTA ZIP URL")
    ap.add_argument("--partition", required=True, choices=["boot", "init_boot", "both"], help="Partition to extract")
    ap.add_argument("--outdir", required=True, help="Output directory")
    return ap.parse_args()

def sanitize_name(text):
    text = re.sub(r"[^\w.\-]+", "-", text.strip(), flags=re.UNICODE)
    return re.sub(r"-{2,}", "-", text).strip("-._") or "ota"

def extract_short_ota_label(source):
    parsed = urlparse(source)
    raw = os.path.basename(parsed.path) if parsed.scheme else os.path.basename(source)
    if raw.lower().endswith(".zip"):
        raw = raw[:-4]
    
    base = sanitize_name(raw)
    
    codename = None
    if "-ota-" in base:
        codename = base.split("-ota-", 1)[0].lower()
    else:
        parts = base.split("-")
        if parts and parts[0].lower() not in ("ota", "full"):
            codename = parts[0].lower()

    date_match = re.search(r"\b[a-z0-9]+\.(\d{6})\.\d{3}\b", base, re.IGNORECASE)
    short_date = date_match.group(1) if date_match else None

    pieces = [p for p in (codename, short_date) if p]
    return "-".join(pieces) if pieces else base

def rename_outputs(outdir, partitions, source):
    renamed = []
    label = extract_short_ota_label(source)
    
    for partition in partitions:
        src = os.path.join(outdir, f"{partition}.img")
        if not os.path.exists(src):
            die(f"Expected output {src} not found after payload_dumper execution.")

        dst = os.path.join(outdir, f"{partition}-{label}.img")
        
        if os.path.exists(dst) and os.path.abspath(src) != os.path.abspath(dst):
            base, ext = os.path.splitext(dst)
            dst = f"{base}-runner{ext}"

        os.replace(src, dst)
        renamed.append(dst)

    return renamed

def extract_partitions(source, outdir, partitions):
    os.makedirs(outdir, exist_ok=True)
    
    # Since payload-dumper is installed via pip in the yaml, we just call it directly
    cmd = ["payload_dumper", "--out", outdir, "--partitions", ",".join(partitions), source]
    
    info(f"Extracting: {', '.join(partitions)}")
    info(f"Targeting: {extract_short_ota_label(source)}")
    
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        die(f"payload_dumper failed with exit code {e.returncode}")

    return rename_outputs(outdir, partitions, source)

def main():
    args = parse_args()
    partitions = ["boot", "init_boot"] if args.partition == "both" else [args.partition]
    
    renamed_paths = extract_partitions(args.source, args.outdir, partitions)

    info("Extraction & Renaming Complete:")
    for path in renamed_paths:
        print(f"    OK  {path}")

if __name__ == "__main__":
    main()
