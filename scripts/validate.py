import argparse
import hashlib
import json
import os
import platform
import re
import shlex
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


CASES = {
    "formal": [
        ("proofs", "proofs/run.sh", r"SUMMARY PASS=\d+ FAIL=0 TIMEOUT=0 TOTAL=\d+"),
    ],
    "runtime": [
        ("options_codec", "bench/smoke/options_codec.sh", "OPTIONS_CODEC_PASSED"),
        ("owner_options", "bench/smoke/owner_options.sh", "OWNER_OPTIONS_PASSED"),
        ("owner_generation_tokens", "bench/smoke/owner_generation_tokens.sh", "OWNER_GENERATION_PUBLIC_TOKENS_PASSED"),
        ("owner_retired_sst", "bench/smoke/owner_retired_sst.sh", "OWNER_RETIRED_SST_PASSED"),
        ("unix_socket_poll_many", "bench/smoke/unix_socket_poll_many.sh", "UNIX_SOCKET_POLL_MANY_PASSED"),
        ("owner_reactor_deadline", "bench/smoke/owner_reactor_deadline.sh", "OWNER_REACTOR_DEADLINE_PASSED"),
        ("owner_reactor_fairness", "bench/smoke/owner_reactor_fairness.sh", "OWNER_REACTOR_FAIRNESS_PASSED"),
        ("owner_reactor_write_backpressure", "bench/smoke/owner_reactor_write_backpressure.sh", "OWNER_REACTOR_WRITE_BACKPRESSURE_PASSED"),
        ("owner_queue", "bench/smoke/owner_queue.sh", "OWNER_QUEUE_PASSED"),
        ("coordinator_owner_dispatch", "bench/smoke/coordinator_owner_dispatch.sh", "OWNER_DISPATCH_PASSED"),
        ("owner_tx_budget", "bench/smoke/owner_tx_budget.sh", "OWNER_TX_BUDGET_PASSED"),
        ("owner_rx_budget", "bench/smoke/owner_rx_budget.sh", "OWNER_RX_BUDGET_PASSED"),
        ("owner_endpoint_lifecycle", "bench/crash/owner_endpoint_lifecycle.sh", "OWNER_ENDPOINT_LIFECYCLE_PASS"),
        ("restore_publish", "bench/crash/restore_publish.sh", "RESTORE_PUBLISH_CRASH_PASS"),
    ],
}


def git(root, *arguments):
    return subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout


def source_digest(root):
    if not (root / ".git").exists():
        return manifest_source_digest(root)
    base = git(root, "rev-parse", "HEAD").strip()
    tracked = git(root, "diff", "--name-only", "HEAD", "--").splitlines()
    untracked = git(root, "ls-files", "--others", "--exclude-standard").splitlines()
    paths = sorted(
        path
        for path in set(tracked + untracked)
        if path and not path.startswith(("docs/superpowers/", ".superpowers/"))
    )
    manifest = hashlib.sha256()
    for relative in paths:
        path = root / relative
        manifest.update(relative.encode("utf-8"))
        manifest.update(b"\0")
        if path.is_file():
            manifest.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            manifest.update(b"DELETED")
        manifest.update(b"\n")
    return hashlib.sha256((base + "\n").encode() + manifest.digest()).hexdigest()


def manifest_source_digest(root):
    manifest_path = root / "MANIFEST.sha256"
    content = manifest_path.read_bytes()
    seen = set()
    for line in content.decode("utf-8").splitlines():
        if not re.fullmatch(r"[0-9a-f]{64}  .+", line):
            raise ValueError("invalid source manifest entry")
        expected, relative = line.split("  ", 1)
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or relative in seen:
            raise ValueError("unsafe or duplicate source manifest entry")
        seen.add(relative)
        if hashlib.sha256((root / path).read_bytes()).hexdigest() != expected:
            raise ValueError("source manifest digest mismatch: " + relative)
    return "manifest-" + hashlib.sha256(content).hexdigest()


def bash5(environment):
    candidates = []
    for entry in environment.get("PATH", "").split(os.pathsep):
        candidate = Path(entry) / "bash"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            candidates.append(candidate)
    for candidate in candidates:
        result = subprocess.run(
            [str(candidate), "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        match = re.search(r"GNU bash, version (\d+)", result.stdout)
        if result.returncode == 0 and match and int(match.group(1)) >= 5:
            environment["PATH"] = str(candidate.parent) + os.pathsep + environment["PATH"]
            return str(candidate)
    raise RuntimeError("Bash 5 or newer is required; enter the pinned Nix devShell")


def last_nonempty_line(path):
    last = ""
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if line.strip():
                last = line.rstrip("\r\n")
    return last


def terminate(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def case_status(exit_code, timed_out, marker_matches):
    if timed_out:
        return "TIMEOUT"
    if exit_code == 0 and marker_matches:
        return "PASS"
    return "FAIL"


def run_case(root, output, name, relative, marker, bash, environment, host, digest, timeout):
    log = output / (name + ".log")
    command = [bash, str(root / relative)]
    started = time.monotonic_ns()
    exit_code = 124
    timed_out = False
    with log.open("wb") as stream:
        process = subprocess.Popen(
            command,
            cwd=root,
            env=environment,
            stdout=stream,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            terminate(process)
    elapsed = (time.monotonic_ns() - started) // 1_000_000
    final_line = last_nonempty_line(log)
    marker_matches = re.fullmatch(marker, final_line) is not None
    status = case_status(exit_code, timed_out, marker_matches)
    record = {
        "name": name,
        "suite": "formal" if name == "proofs" else "runtime",
        "host": host,
        "source_digest": digest,
        "command": shlex.join(command),
        "status": status,
        "exit_code": exit_code,
        "elapsed_ms": elapsed,
        "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    }
    print(json.dumps(record, sort_keys=True), flush=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("formal", "runtime", "all"), default="all")
    parser.add_argument("--case", action="append")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=1800)
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    environment = os.environ.copy()
    environment["TMPDIR"] = "/tmp"
    bash = bash5(environment)
    selected = []
    suites = ("formal", "runtime") if arguments.suite == "all" else (arguments.suite,)
    for suite in suites:
        selected.extend((name, path, marker) for name, path, marker in CASES[suite])
    if arguments.case:
        names = set(arguments.case)
        selected = [case for case in selected if case[0] in names]
        missing = names - {case[0] for case in selected}
        if missing:
            parser.error("unknown case(s): " + ", ".join(sorted(missing)))
    if not selected:
        parser.error("no validation cases selected")

    digest = source_digest(root)
    host = "{}-{}-{}".format(platform.system(), platform.release(), platform.machine())
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = arguments.output or root / "bench/results/validation-runs" / (stamp + "-" + digest[:12])
    output.mkdir(parents=True, exist_ok=True)
    failures = 0
    result_path = output / "results.jsonl"
    with result_path.open("w", encoding="utf-8") as results:
        for name, relative, marker in selected:
            record = run_case(root, output, name, relative, marker, bash,
                environment, host, digest, arguments.timeout_seconds)
            results.write(json.dumps(record, sort_keys=True) + "\n")
            results.flush()
            failures += record["status"] != "PASS"
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
