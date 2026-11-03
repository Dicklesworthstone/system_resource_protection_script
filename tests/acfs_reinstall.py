#!/usr/bin/env python3
"""Offline SRPS reinstall regression through ACFS's real verified updater.

Run through the project's DSR qualification path, supplying an existing ACFS
checkout with --acfs-source (or SRPS_ACFS_SOURCE). No source is downloaded by
this test. The ACFS updater, checksum verifier, target environment, temporary
directory lifecycle, and complete SRPS installer entrypoint are real. Only the
download transport and account-home metadata are fixtures. An explicit srps.conf
disables host configuration and replaces system detection with sandbox checks.

This exercises the nightly stack's `run_cmd "SRPS" update_run_verified_installer
srps` call, not the unrelated nightly scheduler or installation of other tools.
Both Bash and Zsh start with the installed rc file after two block refreshes and
an unchanged reinstall. Fixtures and logs are retained; ACFS removes its own
transient staging files and per-installer TMPDIR normally.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
START = "# >>> system_resource_protection_script >>>"
END = "# <<< system_resource_protection_script <<<"
INSTALLER_URL = (
    "https://raw.githubusercontent.com/Dicklesworthstone/"
    "system_resource_protection_script/main/install.sh"
)

UPDATER = r'''
set -euo pipefail
source "$SRPS_TEST_ACFS/scripts/lib/update.sh"
source "$SRPS_TEST_ACFS/scripts/lib/security.sh"

# The actual runner still constructs HOME/PATH/TARGET_* and enters HOME. Only
# passwd/home metadata is redirected, including for root in root-only runners.
# No accounts, credentials, global rc files or installed binaries are changed.
update_target_home() {
    [[ "$1" == "$SRPS_TEST_ACCOUNT" && -d "$SRPS_TEST_HOME" && "$SRPS_TEST_HOME" != / ]] || return 1
    printf '%s\n' "$SRPS_TEST_HOME"
}
TARGET_USER="$SRPS_TEST_ACCOUNT"
TARGET_HOME="$SRPS_TEST_HOME"
ACFS_REPO_ROOT="$SRPS_TEST_ACFS"
UPDATE_LOG_FILE="$SRPS_TEST_CASE/update.log"
QUIET=true
VERBOSE=false
UPDATE_CMD_TIMEOUT=20
ACFS_UPDATE_RETRY_MAX_ATTEMPTS=1

# The trust input is an explicit fixture checksum file, loaded by ACFS itself.
# Mark metadata as already refreshed: this test must never use live network.
load_checksums "$SRPS_TEST_POLICY"
UPDATE_SECURITY_READY=true
ACFS_CHECKSUMS_REMOTE_REFRESHED=true

# Replace transport only. verify_checksum still hashes the exact bytes staged
# here, and its negative test must refuse a payload changed after pinning.
acfs_download_to_file() {
    [[ "$1" == "$SRPS_TEST_URL" && "$3" == srps ]] || return 90
    cat "$SRPS_TEST_INSTALLER" > "$2" || return 1
    if [[ "${SRPS_TEST_TAMPER:-0}" == 1 ]]; then
        printf '\n# transport corruption fixture\n' >> "$2"
    fi
}

# This is the stack-update call used by ACFS nightly reinstalls. Its real failure
# accounting must expose a checksum rejection rather than treating it as a skip.
run_cmd "SRPS" update_run_verified_installer srps
printf 'COUNTS=%s,%s,%s\n' "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
[[ "$SUCCESS_COUNT" == 1 && "$SKIP_COUNT" == 0 && "$FAIL_COUNT" == 0 ]]
'''

INSTALL_CONFIG = r'''
# Keep full installer control flow, with all system-changing phases disabled.
ENABLE_ANANICY=0
ENABLE_SYSCTL=0
ENABLE_WSL_LIMITS=0
ENABLE_TOOLS=0
ENABLE_SHELL_ALIASES=1
ENABLE_SAMPLER=0
ENABLE_HTML_REPORT=0
ENABLE_RULE_PULL=0
ENABLE_DIAGNOSTICS=0
detect_system() {
    [[ "$HOME" == "$SRPS_TEST_HOME" && "$PWD" == "$HOME" ]] || return 91
    [[ "$TARGET_HOME" == "$HOME" && "$TARGET_USER" == "$SRPS_TEST_ACCOUNT" ]] || return 92
    case "$TMPDIR" in "$HOME"/.cache/acfs/installer-tmp/srps.*) ;; *) return 93 ;; esac
    [[ -d "$TMPDIR" && -w "$TMPDIR" ]] || return 94
    printf '%s\0%s\0%s\0%s\0' "$HOME" "$PWD" "$TMPDIR" "${CARGO_TARGET_DIR-}" >> "$SRPS_TEST_CASE/installer-events"
    HAS_APT=1
    HAS_SYSTEMD=0
    IS_WSL=0
}
detect_power_profile() { ON_BATTERY=0; }
# A future regression must fail instead of running a privileged installer phase.
sudo() { printf 'unexpected privileged operation: %s\n' "$*" >&2; return 97; }
'''

PROBE = r'''
limited true
cargo-limited --version
alias unrelated >/dev/null
printf '%s\0' "${TMPDIR+x}" "${TMPDIR-}" "${CARGO_TARGET_DIR+x}" "${CARGO_TARGET_DIR-}" "$BEFORE" "$AFTER"
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def outside_block(text):
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.rstrip("\n") == START]
    ends = [i for i, line in enumerate(lines) if line.rstrip("\n") == END]
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise AssertionError("expected exactly one well-formed managed block")
    return "".join(lines[:starts[0]] + lines[ends[0] + 1:])


class AcfsReinstallTests(unittest.TestCase):
    acfs_source = None

    @classmethod
    def setUpClass(cls):
        if not sys.platform.startswith("linux"):
            raise unittest.SkipTest("ACFS's verified updater requires Linux")
        cls.shells = {name: shutil.which(name) for name in ("bash", "zsh")}
        missing = [name for name, executable in cls.shells.items() if not executable]
        if missing:
            raise RuntimeError("qualification requires both shells; missing " + ", ".join(missing))
        if cls.acfs_source is None:
            raise RuntimeError("pass --acfs-source CHECKOUT or set SRPS_ACFS_SOURCE; no online fallback is used")
        cls.acfs_source = cls.acfs_source.resolve(strict=True)
        cls.artifacts = Path(tempfile.mkdtemp(prefix="srps-acfs-reinstall-"))
        cls.snapshot = cls.artifacts / "acfs"
        sources = {}
        # Preserve exact upstream bytes, including relative library imports.
        for name in ("update.sh", "security.sh", "logging.sh", "holds.sh"):
            relative = Path("scripts/lib") / name
            source = cls.acfs_source / relative
            data = source.read_bytes()
            destination = cls.snapshot / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            sources[str(relative)] = digest(data)
        cls.installer = cls.artifacts / "install.sh"
        cls.installer.write_bytes((ROOT / "install.sh").read_bytes())
        cls.installer_sha = digest(cls.installer.read_bytes())
        cls.policy = cls.artifacts / "checksums.yaml"
        cls.policy.write_text(
            "installers:\n  srps:\n"
            f'    url: "{INSTALLER_URL}"\n'
            f'    sha256: "{cls.installer_sha}"\n'
        )
        (cls.artifacts / "source-evidence.json").write_text(json.dumps({
            "acfs_source": str(cls.acfs_source),
            "acfs_files_sha256": sources,
            "srps_installer_sha256": cls.installer_sha,
        }, indent=2) + "\n")
        cls.account = pwd.getpwuid(os.geteuid()).pw_name
        print("ACFS reinstall artifacts:", cls.artifacts, flush=True)

    def fixture(self, shell, scenario):
        self.case = Path(tempfile.mkdtemp(prefix=f"{shell}-{scenario}-", dir=self.artifacts))
        self.home = self.case / "home"
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.scratch = self.case / "build-volume/tmp with spaces"
        self.target = self.case / "build-volume/project target"
        self.scratch.mkdir(parents=True)
        self.target.mkdir(parents=True)
        (self.case / "coordinator-tmp").mkdir()
        self.rc = self.home / (".bashrc" if shell == "bash" else ".zshrc")
        self.config = self.case / "srps.conf"
        self.config.write_text(INSTALL_CONFIG)
        # Account-local inert commands allow the aliases and updater's binary
        # backup/health checks to run without invoking services or other tools.
        for name, body in {
            "systemd-run": 'printf "%s\\n" "$*" >> "$SRPS_TEST_ALIAS_LOG"\n',
            "srps": 'printf "srps fixture\\n"\n',
        }.items():
            path = self.bin / name
            path.write_text("#!/bin/sh\n" + body)
            path.chmod(0o755)
        self.shell = shell

    def install(self, *, tamper=False):
        env = {
            "HOME": str(self.home), "TARGET_HOME": str(self.home),
            "PATH": "/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin",
            "SHELL": self.shells[self.shell], "TERM": "dumb", "NO_COLOR": "1",
            "TMPDIR": str(self.case / "coordinator-tmp"),
            "CARGO_TARGET_DIR": str(self.case / "installer-only-cargo"),
            "SRPS_CONFIG_FILE": str(self.config),
            "SRPS_TEST_ACFS": str(self.snapshot), "SRPS_TEST_CASE": str(self.case),
            "SRPS_TEST_HOME": str(self.home), "SRPS_TEST_ACCOUNT": self.account,
            "SRPS_TEST_POLICY": str(self.policy), "SRPS_TEST_INSTALLER": str(self.installer),
            "SRPS_TEST_URL": INSTALLER_URL, "SRPS_TEST_TAMPER": "1" if tamper else "0",
        }
        result = subprocess.run([self.shells["bash"], "--noprofile", "--norc", "-c", UPDATER],
                                env=env, cwd=self.case, capture_output=True, text=True, timeout=40)
        log = self.case / "update.log"
        details = result.stdout + result.stderr + (log.read_text() if log.exists() else "")
        (self.case / "last-install-output").write_text(details)
        if tamper:
            self.assertNotEqual(result.returncode, 0, details)
            self.assertIn("CHECKSUM BLOCKED", details)
            self.assertIn("Refusing to execute unverified installer", details)
            return
        self.assertEqual(result.returncode, 0, details)
        self.assertIn("COUNTS=1,0,0", result.stdout)
        events = (self.case / "installer-events").read_bytes().split(b"\0")[:-1]
        self.assertEqual(len(events) % 4, 0)
        self.assertGreaterEqual(len(events), 4)
        home, cwd, temporary, cargo = [os.fsdecode(value) for value in events[-4:]]
        self.assertEqual(home, str(self.home))
        self.assertEqual(cwd, home)
        self.assertTrue(temporary.startswith(home + "/.cache/acfs/installer-tmp/srps."))
        self.assertFalse(Path(temporary).exists(), "ACFS must clean its per-install TMPDIR")
        self.assertEqual(cargo, env["CARGO_TARGET_DIR"])
        installed = self.rc.read_text()
        self.assertNotIn(temporary, installed, "installer TMPDIR must never become durable shell policy")
        self.assertNotIn(cargo, installed, "installer Cargo settings must never become durable shell policy")

    def fresh_shell(self, expected_tmp, expected_cargo, extra_env=None):
        alias_log = self.case / "aliases.log"
        env = {
            "HOME": str(self.home), "PATH": str(self.bin) + ":/usr/bin:/bin",
            "SHELL": self.shells[self.shell], "TERM": "dumb", "NO_COLOR": "1",
            "SRPS_TEST_ALIAS_LOG": str(alias_log),
        }
        env.update(extra_env or {})
        if self.shell == "bash":
            command = [self.shells["bash"], "--noprofile", "--rcfile", str(self.rc), "-i", "-c", PROBE]
        else:
            # -d disables global rc files; the new shell still reads its .zshrc.
            command = [self.shells["zsh"], "-d", "-i", "-c", PROBE]
        result = subprocess.run(command, env=env, cwd=self.home, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, os.fsdecode(result.stderr))
        observed = [os.fsdecode(value) for value in result.stdout.split(b"\0")[:-1]]
        expected = [
            "" if expected_tmp is None else "x", expected_tmp or "",
            "" if expected_cargo is None else "x", expected_cargo or "",
            "keep prefix", "keep suffix",
        ]
        self.assertEqual(observed, expected, os.fsdecode(result.stderr))
        self.assertEqual(alias_log.read_text().splitlines()[-2:], [
            "--user --scope -p CPUQuota=50% -- true",
            "--user --scope -p CPUQuota=75% -p MemoryMax=50G cargo --version",
        ])

    def test_verified_reinstalls_and_fresh_shells(self):
        scenarios = ("before", "after", "tmp-only", "inherited", "empty", "config", "xdg-config", "preserve", "custom-footer")
        for shell in self.shells:
            for scenario in scenarios:
                with self.subTest(shell=shell, scenario=scenario):
                    self.fixture(shell, scenario)
                    tmp, cargo = str(self.scratch), str(self.target)
                    prefix = "# operator prefix\nexport BEFORE='keep prefix'\n"
                    suffix = "export AFTER='keep suffix'\nalias unrelated='printf unrelated'\n# operator suffix\n"
                    assignments = f"export TMPDIR={shlex.quote(tmp)}\nexport CARGO_TARGET_DIR={shlex.quote(cargo)}\n"
                    footer = "export TMPDIR=/tmp\nexport CARGO_TARGET_DIR=/tmp/cargo-target\n"
                    runtime_env = {}
                    storage_config = None
                    expected_tmp, expected_cargo = tmp, cargo
                    if scenario == "before":
                        prefix += assignments
                    elif scenario == "after":
                        suffix += assignments
                    elif scenario == "tmp-only":
                        prefix += f"export TMPDIR={shlex.quote(tmp)}\n"
                        expected_cargo = None
                    elif scenario == "inherited":
                        runtime_env.update(TMPDIR=tmp, CARGO_TARGET_DIR=cargo)
                    elif scenario == "empty":
                        runtime_env.update(TMPDIR="", CARGO_TARGET_DIR="")
                        expected_tmp = expected_cargo = ""
                    elif scenario in ("config", "xdg-config", "preserve"):
                        config_home = self.home / ".config"
                        if scenario == "xdg-config":
                            config_home = self.home / "operator config"
                            runtime_env["XDG_CONFIG_HOME"] = str(config_home)
                        storage_config = config_home / "srps/storage.sh"
                        storage_config.parent.mkdir(parents=True)
                        if scenario == "preserve":
                            config_text = "# Operator controls storage; retain resource aliases.\nSRPS_STORAGE_POLICY=preserve\n"
                            expected_tmp = expected_cargo = None
                        else:
                            config_text = f"# Operator storage settings survive refreshes.\nSRPS_TMPDIR={shlex.quote(tmp)}\n"
                            expected_cargo = None
                            if scenario == "xdg-config":
                                config_text += f"SRPS_CARGO_TARGET_DIR={shlex.quote(cargo)}\n"
                                expected_cargo = cargo
                        storage_config.write_text(config_text)
                    elif scenario == "custom-footer":
                        # An operator fixed the old managed footer in place before
                        # this release. Migration must retain its guards and unset.
                        footer = (
                            "# operator-owned build-volume guard\n"
                            f"if [ -d {shlex.quote(tmp)} ] && [ -w {shlex.quote(tmp)} ]; then\n"
                            f"  export TMPDIR={shlex.quote(tmp)}\n"
                            "fi\nunset CARGO_TARGET_DIR\n"
                        )
                        expected_cargo = None
                    initial = prefix + START + "\n# Previous renderer\n# Rust / Cargo env\n" + footer + END + "\n" + suffix
                    self.rc.write_text(initial)
                    original_outside = outside_block(initial)
                    preserved_config = storage_config.read_bytes() if storage_config else None
                    migrated_outside = None
                    for generation in (1, 2):
                        if generation == 2:
                            # Force a genuine managed-block refresh, not merely a
                            # no-op reinstall of an already-current renderer.
                            self.rc.write_text(self.rc.read_text().replace(END, "# stale renderer annotation\n" + END))
                        previous = self.rc.read_bytes()
                        self.install()
                        self.assertEqual(Path(str(self.rc) + ".srps-bak").read_bytes(), previous)
                        installed = self.rc.read_text()
                        outside = outside_block(installed)
                        if scenario == "custom-footer":
                            self.assertTrue(outside.startswith(prefix))
                            self.assertTrue(outside.endswith(suffix))
                            self.assertEqual(outside.count(footer), 1, "custom footer must migrate verbatim exactly once")
                            if migrated_outside is not None:
                                self.assertEqual(outside, migrated_outside)
                            migrated_outside = outside
                        else:
                            self.assertEqual(outside, original_outside)
                        if storage_config:
                            self.assertEqual(storage_config.read_bytes(), preserved_config)
                        self.fresh_shell(expected_tmp, expected_cargo, runtime_env)
                    current = self.rc.read_bytes()
                    backup = Path(str(self.rc) + ".srps-bak").read_bytes()
                    modified = self.rc.stat().st_mtime_ns
                    self.install()
                    self.assertEqual(self.rc.read_bytes(), current)
                    self.assertEqual(self.rc.stat().st_mtime_ns, modified)
                    self.assertEqual(Path(str(self.rc) + ".srps-bak").read_bytes(), backup)
                    self.fresh_shell(expected_tmp, expected_cargo, runtime_env)

    def test_checksum_refusal_never_runs_installer(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                self.fixture(shell, "checksum-refusal")
                original = "# untouched operator rc\nexport TMPDIR=/operator/build-volume\n"
                self.rc.write_text(original)
                self.install(tamper=True)
                self.assertEqual(self.rc.read_text(), original)
                self.assertFalse((self.case / "installer-events").exists())
                self.assertFalse(Path(str(self.rc) + ".srps-bak").exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acfs-source", type=Path, default=os.environ.get("SRPS_ACFS_SOURCE"),
                        help="existing offline ACFS checkout containing scripts/lib/update.sh and security.sh")
    options, unittest_args = parser.parse_known_args()
    AcfsReinstallTests.acfs_source = options.acfs_source
    unittest.main(argv=[sys.argv[0], *unittest_args], verbosity=2)
