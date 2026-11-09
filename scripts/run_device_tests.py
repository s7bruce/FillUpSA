#!/usr/bin/env python3
"""Run the shared test suite on the configured older-iPhone simulator matrix."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


DEFAULT_DEVICES = [
    "FillUpSA iPhone 11",
    "FillUpSA iPhone SE 3",
    "FillUpSA iPhone 13 mini",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", action="append", help="Simulator name or UUID; repeat for multiple devices")
    parser.add_argument("--results", type=Path, help="New directory for logs and xcresult bundles (default: temporary directory)")
    args = parser.parse_args()
    requested = args.device or DEFAULT_DEVICES
    inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    devices = [device for group in inventory["devices"].values() for device in group]
    selected = []
    for name in requested:
        matches = [device for device in devices if name in (device["name"], device["udid"])]
        if len(matches) != 1:
            parser.error(f"Expected one available simulator for {name!r}, found {len(matches)}. Create it in Xcode > Window > Devices and Simulators, or pass its UUID with --device.")
        selected.append(matches[0])

    results = args.results or Path(tempfile.mkdtemp(prefix="FillUpSA-compatibility-"))
    results = results.resolve()
    results.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    outcomes = []
    for index, device in enumerate(selected, 1):
        stem = f"{index}-{device['udid']}"
        bundle = results / f"{stem}.xcresult"
        log = results / f"{stem}.log"
        if bundle.exists():
            parser.error(f"Result bundle already exists: {bundle}; use a new results directory")
        print(f"Running {device['name']} ({device['udid']})", flush=True)
        command = [
            "xcodebuild", "test", "-project", str(root / "FillUpSA.xcodeproj"),
            "-scheme", "FillUpSA", "-destination", f"platform=iOS Simulator,id={device['udid']}",
            "-parallel-testing-enabled", "NO", "-resultBundlePath", str(bundle),
        ]
        with log.open("w") as output:
            result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
        outcomes.append({"device": device["name"], "udid": device["udid"],
                         "passed": result.returncode == 0, "log": str(log), "xcresult": str(bundle)})
        print(f"{'PASS' if result.returncode == 0 else 'FAIL'}: {device['name']} — {log}", flush=True)
    (results / "summary.json").write_text(json.dumps(outcomes, indent=2))
    print(f"Results: {results}")
    return 0 if all(outcome["passed"] for outcome in outcomes) else 1


if __name__ == "__main__":
    raise SystemExit(main())
