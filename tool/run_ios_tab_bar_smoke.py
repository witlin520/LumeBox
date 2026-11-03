"""Run the UIKit check; require its result file and screenshot, not console delivery."""

import argparse
import json
import pathlib
import shutil
import subprocess
import time

BUNDLE = "com.lumebox.system-tab-bar-smoke"
PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def read_status(path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def run_check(device, data, output, timeout=180, grace=10):
    data, output = pathlib.Path(data), pathlib.Path(output)
    output.mkdir(parents=True, exist_ok=True)
    status = data / "Documents/native-tab-bar-status.json"
    screenshot = data / "Documents/native-tab-bar.png"
    for attempt in range(1, 3):
        subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        # A previous launch can never supply a passing result for this one.
        status.unlink(missing_ok=True)
        screenshot.unlink(missing_ok=True)
        log = output / f"launch-{attempt}.log"
        with log.open("w", encoding="utf-8") as console:
            process = subprocess.Popen(
                ["xcrun", "simctl", "launch", "--terminate-running-process", "--console",
                 device, BUNDLE], stdout=console, stderr=subprocess.STDOUT,
            )
            started = time.monotonic()
            exited_at = None
            result = None
            try:
                while time.monotonic() - started < timeout:
                    result = read_status(status)
                    if result is not None:
                        if result.get("phase") == "failed":
                            raise RuntimeError(f"UIKit assertion failed: {result.get('detail')}")
                        if result.get("phase") == "passed":
                            if not screenshot.exists() or not screenshot.read_bytes().startswith(PNG_HEADER):
                                raise RuntimeError("UIKit reported success without a valid screenshot")
                            shutil.copy2(status, output / status.name)
                            shutil.copy2(screenshot, output / screenshot.name)
                            print("LUME_SYSTEM_TAB_BAR_SMOKE_OK", flush=True)
                            return
                    if process.poll() is not None:
                        if exited_at is None:
                            exited_at = time.monotonic()
                        if time.monotonic() - exited_at >= grace:
                            break
                    time.sleep(.5)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)
                if status.exists():
                    shutil.copy2(status, output / f"status-{attempt}.json")
                print(log.read_text(encoding="utf-8", errors="replace")[-12000:], flush=True)
        # Retry only a transport/cold-launch failure before the test entered
        # UIApplication. Assertion failures and crashes after entry fail now.
        if result is not None or attempt == 2 or process.returncode not in (0, -15):
            raise RuntimeError(f"UIKit check did not finish: exit={process.returncode}, status={result}")
        print("No UIApplication entry; retrying the simulator launch once", flush=True)
        subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE], check=False)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=180)


def collect_diagnostics(device, output):
    output = pathlib.Path(output)
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "spawn", device, "log", "show", "--last", "5m",
             "--style", "compact", "--predicate", 'process == "Smoke"'],
            capture_output=True, text=True, timeout=30,
        )
        (output / "simulator.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    except (OSError, subprocess.TimeoutExpired) as error:
        (output / "diagnostics-error.txt").write_text(str(error), encoding="utf-8")
    reports = pathlib.Path.home() / "Library/Logs/DiagnosticReports"
    for report in sorted(reports.glob("Smoke*.ips"), key=lambda p: p.stat().st_mtime)[-3:]:
        shutil.copy2(report, output / report.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("device")
    parser.add_argument("data")
    parser.add_argument("output")
    args = parser.parse_args()
    try:
        run_check(args.device, args.data, args.output)
    except Exception:
        collect_diagnostics(args.device, args.output)
        raise
