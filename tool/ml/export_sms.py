#!/usr/bin/env python3
"""Step 0a: pull bank/wallet SMS from a connected phone into a dataset.

Only messages from recognised financial senders are read (the filter runs on
the phone). The raw dump also holds bank OTPs, so it lives in a temp file
that is deleted as soon as the parser has turned it into
tool/ml/data/dataset.jsonl. Nothing here prints a message body.

    python3 tool/ml/export_sms.py [--serial R3CT...]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DATA_DIR = os.path.join(ROOT, "tool", "ml", "data")
ROW = re.compile(r"^Row: \d+ address=(.*?), date=(\d+), body=(.*)\Z", re.S)


def find_adb():
    adb = shutil.which("adb") or os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
    if not os.path.exists(adb):
        sys.exit("adb not found; install Android platform-tools")
    return adb


def pick_serial(adb, wanted):
    out = subprocess.run([adb, "devices"], capture_output=True, text=True, check=True).stdout
    ready = [l.split()[0] for l in out.splitlines()[1:] if l.strip().endswith("device")]
    if wanted:
        if wanted not in ready:
            sys.exit(f"{wanted} is not connected and authorized (ready: {ready})")
        return wanted
    if len(ready) != 1:
        sys.exit(f"pass --serial; ready devices: {ready or 'none'}")
    return ready[0]


def dart(*args):
    return subprocess.run(
        ["dart", "run", "tool/ml/build_dataset.dart", *args],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout


def query_inbox(adb, serial, where):
    command = (
        "content query --uri content://sms/inbox --projection address:date:body "
        f'--sort "date ASC" --where "{where}"'
    )
    result = subprocess.run([adb, "-s", serial, "shell", command], capture_output=True, text=True)
    if result.returncode != 0 or result.stdout.startswith("Error"):
        # Never echo stdout: on success it is message bodies.
        sys.exit(f"content query failed: {result.stderr.strip()[:300]}")
    if result.stdout.strip() == "No result found.":
        return []
    rows = []
    for chunk in re.split(r"\n(?=Row: \d+ )", result.stdout.strip()):
        match = ROW.match(chunk)
        if not match:
            sys.exit("unexpected content query output; aborting without saving")
        sender, date, body = match.groups()
        rows.append({"sender": sender, "date": int(date), "body": body})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial", help="adb serial of the phone")
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    args = parser.parse_args()

    adb = find_adb()
    serial = pick_serial(adb, args.serial)
    rows = query_inbox(adb, serial, dart("where"))
    print(f"read {len(rows)} messages from financial senders")

    fd, raw_path = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(rows, f, ensure_ascii=False)
        meta = json.loads(dart("build", raw_path, os.path.abspath(args.data_dir)))
    finally:
        os.remove(raw_path)

    print(f"parser v{meta['parserVersion']}: {meta['transactions']} transactions, "
          f"{meta['ignoredByParser']} ignored (OTP/promo/failed), {meta['nonFinancial']} non-financial")
    print("rules' predictions:", ", ".join(f"{k} {v}" for k, v in meta["predicted"].items()))
    print(f"wrote {os.path.relpath(args.data_dir, ROOT)}/dataset.jsonl")


if __name__ == "__main__":
    main()
