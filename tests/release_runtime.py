#!/usr/bin/env python3
"""Probe a real Linux sysmoni binary; retain artifacts and deny unlink syscalls.

This runs no compiler, package manager, installer, privileged service command,
or cleanup. Passing this probe is not full installer/service qualification.
"""

import argparse
import ctypes
import errno
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import time
import urllib.request


RELEASE_URL = (
    "https://github.com/Dicklesworthstone/system_resource_protection_script/"
    "releases/download/v1.4.2/sysmoni-linux-amd64"
)
RELEASE_SHA256 = "2b59689cb5a978d69153c57257aeccf2d2457a61645dd1b8f05e8f5cc2e5e6fe"


def deny_unlink():
    """Install an inherited Linux x86-64 seccomp filter, without compiling."""
    # ubs:ignore - platform.machine is public host metadata, not a MAC or secret.
    if sys.platform != "linux" or platform.machine() != "x86_64":
        raise RuntimeError("this audited seccomp probe requires Linux x86_64")

    class Filter(ctypes.Structure):
        _fields_ = [
            ("code", ctypes.c_ushort),
            ("jt", ctypes.c_ubyte),
            ("jf", ctypes.c_ubyte),
            ("k", ctypes.c_uint32),
        ]

    class Program(ctypes.Structure):
        _fields_ = [("len", ctypes.c_ushort), ("filter", ctypes.POINTER(Filter))]

    # Check the kernel audit architecture before inspecting syscall numbers.
    instructions = [
        Filter(0x20, 0, 0, 4),
        Filter(0x15, 1, 0, 0xC000003E),
        Filter(0x06, 0, 0, 0x80000000),
        Filter(0x20, 0, 0, 0),
        Filter(0x45, 0, 1, 0x40000000),
        Filter(0x06, 0, 0, 0x00050000 | errno.EPERM),
    ]
    # unlink, unlinkat, rmdir, and renames that can replace existing files.
    for syscall in (87, 263, 84, 82, 264, 316):
        instructions.extend(
            [Filter(0x15, 0, 1, syscall), Filter(0x06, 0, 0, 0x00050000 | errno.EPERM)]
        )
    instructions.append(Filter(0x06, 0, 0, 0x7FFF0000))
    filters = (Filter * len(instructions))(*instructions)
    program = Program(len(instructions), filters)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(38, 1, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
    if libc.prctl(22, 2, ctypes.byref(program), 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-dir", required=True)
    parser.add_argument("--source-manifest", required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--binary", help="existing candidate binary; no compilation")
    parser.add_argument("--binary-sha256", help="required digest for --binary")
    args = parser.parse_args()
    root = pathlib.Path.cwd().resolve()
    results = pathlib.Path(args.result_dir).resolve()
    if not results.is_relative_to(root) or results == root:
        raise RuntimeError("results must be a retained subdirectory of the source root")
    results.mkdir(parents=True, exist_ok=False)
    events = []

    def record(case, passed, **details):
        event = {"case": case, "passed": passed, **details}
        events.append(event)
        print(json.dumps(event), flush=True)

    def persist():
        with (results / "events.json").open("x") as output:
            json.dump(events, output, indent=2)

    try:
        manifest_bytes = pathlib.Path(args.source_manifest).read_bytes()
        # ubs:ignore - this compares a public source-manifest checksum, not a secret.
        if hashlib.sha256(manifest_bytes).hexdigest() != args.manifest_sha256:
            raise RuntimeError("source manifest differs from the admitted command digest")
        expected = json.loads(manifest_bytes)
        actual = {}
        for name, digest in expected["files"].items():
            path = (root / name).resolve()
            if not path.is_relative_to(root):
                raise RuntimeError("source manifest path escaped the bound root")
            actual[name] = hashlib.sha256(path.read_bytes()).hexdigest()
            # ubs:ignore - source-file checksums are public integrity metadata.
            if actual[name] != digest:
                raise RuntimeError("source-content mismatch: " + name)
        with (results / "source-receipt.json").open("x") as output:
            json.dump({"base": expected["base"], "files": actual}, output, indent=2)
        record("source_content", True, base=expected["base"], files=len(actual))

        deny_unlink()
        proof = results / "retained-unlink-denial-proof"
        proof.write_text("This file must remain present after the probe.\n")
        status = pathlib.Path("/proc/self/status").read_text()
        fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
        if fields.get("Seccomp", "").strip() != "2" or fields.get("NoNewPrivs", "").strip() != "1":
            raise RuntimeError("inherited kernel seccomp filter is not active")
        record("kernel_unlink_denial", True, seccomp_mode=2, no_new_privileges=1)

        if args.binary:
            if not args.binary_sha256:
                raise RuntimeError("candidate binary requires its expected digest")
            binary = pathlib.Path(args.binary).resolve()
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            # ubs:ignore - the candidate asset checksum is public integrity metadata.
            if digest != args.binary_sha256:
                raise RuntimeError("candidate binary digest mismatch")
            label = "candidate"
        else:
            binary = results / "sysmoni-v1.4.2-linux-amd64"
            request = urllib.request.Request(
                RELEASE_URL, headers={"User-Agent": "SRPS-release-qualification/20261008"}
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                contents = response.read(12 * 1024 * 1024)
            digest = hashlib.sha256(contents).hexdigest()
            # ubs:ignore - this pinned public release digest contains no secret material.
            if digest != RELEASE_SHA256:
                raise RuntimeError("released binary digest mismatch")
            with binary.open("xb") as output:
                output.write(contents)
            binary.chmod(0o700)
            label = "v1.4.2"
        record("binary_digest", True, binary=label, sha256=digest)

        def run(name, flags, overrides=None, valid_json=False, clean_error=False, help_text=False):
            env = dict(os.environ)
            for key in ("SRPS_SYSMONI_INTERVAL", "HOST_PROC", "HOST_SYS", "HOST_ETC"):
                env.pop(key, None)
            env.update({"GOMAXPROCS": "2", "SRPS_SYSMONI_GPU": "0", "SRPS_SYSMONI_BATT": "0"})
            env.update(overrides or {})
            started = time.monotonic()
            completed = subprocess.run(
                [str(binary), *flags], env=env, capture_output=True, timeout=30, check=False
            )
            # Retain diagnostics; summarize JSON without publishing process arguments.
            with (results / (name + ".stderr")).open("xb") as output:
                output.write(completed.stderr)
            has_panic = b"panic:" in completed.stderr
            passed = False
            if valid_json:
                try:
                    value = json.loads(completed.stdout)
                    passed = (
                        completed.returncode == 0
                        and "CPU" in value
                        and value.get("Memory", {}).get("TotalBytes", 0) > 0
                    )
                except (ValueError, TypeError):
                    passed = False
            elif clean_error:
                passed = completed.returncode != 0 and not has_panic and not completed.stdout.strip()
            elif help_text:
                passed = (
                    completed.returncode == 0
                    and not has_panic
                    and b"Usage of sysmoni:" in completed.stdout + completed.stderr
                    and b'"CPU":' not in completed.stdout
                )
            record(
                name,
                passed,
                returncode=completed.returncode,
                panic=has_panic,
                duration_seconds=round(time.monotonic() - started, 6),
                stdout_bytes=len(completed.stdout),
            )

        run("real_procfs_snapshot", ["--json", "--interval=10ms"], valid_json=True)
        run("zero_flag_interval", ["--json", "--interval=0"], clean_error=True)
        run("negative_flag_interval", ["--json", "--interval=-1s"], clean_error=True)
        run("zero_env_interval", ["--json"], {"SRPS_SYSMONI_INTERVAL": "0"}, clean_error=True)
        run("unknown_flag", ["--json", "--definitely-invalid"], clean_error=True)
        run("help_exits_without_sampling", ["--help"], help_text=True)
        absent_proc = results / "missing-procfs"
        run("unavailable_procfs", ["--json", "--interval=10ms"], {"HOST_PROC": str(absent_proc)}, clean_error=True)
        record(
            "installer_service_coverage",
            False,
            status="not_exercised",
            reason="requires a real regular-user/sudo/systemd sandbox; no host services changed",
        )
        persist()
        return int(any(not event["passed"] for event in events if event["case"] != "installer_service_coverage"))
    except Exception as error:
        record("qualification_error", False, error_type=type(error).__name__, detail=str(error))
        persist()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
