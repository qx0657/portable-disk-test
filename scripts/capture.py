#!/usr/bin/env python3
"""Capture native QA states. Import/empty fixtures are diagnostic-only, never saved."""
from pathlib import Path
import argparse
import re
import subprocess
import textwrap

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--device", help="Optional BSD device ID for the general capture states")
parser.add_argument("--ata-device", help="Optional BSD device ID for ATA-specific capture states")
options = parser.parse_args()
for value in [options.device, options.ata_device]:
    if value is not None and re.fullmatch(r"disk[0-9]+", value) is None:
        parser.error("Use a whole-disk BSD identifier such as disk4")
work = root / "work"
work.mkdir(parents=True, exist_ok=True)
review = root / ".impeccable/review"
review.mkdir(parents=True, exist_ok=True)
source = (root / "Tests/DiskCoreTests/DiskCoreTests.swift").read_text()
fixture = re.search(r'static let benchmark = """\n(.*?)\n    """', source, re.S)
if fixture is None:
    parser.error("The synthetic benchmark fixture was not found")
fixture_file = root / "work/import-fixture.txt"
fixture_file.write_text(textwrap.dedent(fixture.group(1)))
exe = root / "outputs/移动硬盘测试.app/Contents/MacOS/PortableDiskTest"
if not exe.exists():
    parser.error("Build the application with bash scripts/build.sh first")
cases = [
    ("desktop", ["--light"]),
    ("compact", ["--compact", "--light"]),
    ("smart", ["--page=smart", "--light"]),
    ("speed", ["--page=speed", "--light"]),
    ("speed-quick", ["--page=speed", "--purpose=quick", "--light"]),
    ("speed-large", ["--page=speed", "--purpose=large", "--light"]),
    ("dark", ["--dark"]),
    ("empty", ["--empty-preview"]),
    ("import", ["--import-preview=" + str(fixture_file)]),
]
if options.ata_device:
    cases.append(("speed-sata", ["--page=speed", "--device=" + options.ata_device, "--compact", "--light"]))
for name, args in cases:
    if options.device and not any(arg.startswith("--device=") for arg in args):
        args = [*args, "--device=" + options.device]
    target = review / (name + ".png")
    result = subprocess.run([str(exe), *args, "--capture=" + str(target)], capture_output=True, timeout=35)
    (root / ("work/capture-" + name + ".log")).write_bytes(result.stdout + result.stderr)
    if result.returncode or not target.exists():
        raise RuntimeError(f"Capture {name} failed: {result.returncode}")
    print(name, result.returncode, target.stat().st_size, flush=True)
