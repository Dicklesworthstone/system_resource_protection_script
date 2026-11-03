#!/usr/bin/env python3
"""Exercise the emitted SRPS shell policy in Bash and Zsh without installing it.

Only the pure renderer is evaluated. Candidate directories and filesystem probes
are fixtures: these tests do not mount filesystems, alter /data, or run services.
Execute through the repository's DSR qualification path.
"""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "install.sh"


PROBE = r'''import json, os, sys
tool = os.path.basename(sys.argv[0])
args = sys.argv[1:]
with open(os.environ["SRPS_TEST_CALLS"], "a") as log:
    log.write(json.dumps([tool, args]) + "\n")
with open(os.environ["SRPS_TEST_TOPOLOGY"]) as src:
    topology = json.load(src)
if tool == "stat":
    target = args[-1]
    item = topology.get(target, {})
    if item.get("stat_rc", 0):
        sys.exit(item["stat_rc"])
    print(item.get("device", ""))
elif tool == "findmnt":
    target = None
    columns = None
    for i, arg in enumerate(args):
        if arg in ("-T", "--target"):
            target = args[i + 1]
        elif arg.startswith("--target="):
            target = arg.split("=", 1)[1]
        elif arg in ("-o", "--output", "-no", "-rnlo", "-nro"):
            columns = args[i + 1]
        elif arg.startswith("--output="):
            columns = arg.split("=", 1)[1]
    if target is None or columns is None:
        sys.exit("unsupported findmnt fixture invocation: " + repr(args))
    item = topology.get(target, {})
    if item.get("findmnt_rc", 0):
        sys.exit(item["findmnt_rc"])
    values = {"FSTYPE": item.get("fstype", ""),
              "MAJ:MIN": item.get("major_minor", "")}
    requested = columns.split(",")
    if any(column not in values for column in requested):
        sys.exit("unsupported findmnt fixture columns: " + columns)
    print(" ".join(values[column] for column in requested))
else:
    sys.exit("unexpected fixture executable: " + tool)
'''


SNAPSHOT = r'''import json, os, sys
print(json.dumps({
    "tmp_set": sys.argv[1] == "x", "tmp": sys.argv[2],
    "cargo_set": sys.argv[3] == "x", "cargo": sys.argv[4],
    "exported_tmp": os.environ.get("TMPDIR"),
    "exported_cargo": os.environ.get("CARGO_TARGET_DIR"),
    "aliases": sys.argv[5] == "yes",
}))
'''


class PolicyCases:
    @classmethod
    def setUpClass(cls):
        cls.shell_bin = shutil.which(cls.shell)
        if cls.shell_bin is None:
            raise RuntimeError(f"{cls.shell} is required for storage qualification")
        text = SOURCE.read_text()
        match = re.search(
            r"(?ms)^srps_shell_block\(\) \{\n.*?^EOF\n\}", text
        )
        if match is None:
            raise RuntimeError("cannot extract the pure srps_shell_block renderer")
        rendered = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c",
             match.group(0) + "\nsrps_shell_block\n"],
            check=True, capture_output=True, text=True,
        )
        cls.block_text = rendered.stdout

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="srps-storage-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.data_tmp = self.root / "data/tmp"
        self.build_tmp = self.root / "data/build/tmp/shell"
        self.custom_tmp = self.root / "operator build/tmp scratch"
        self.custom_target = self.root / "operator build/cargo target"
        for directory in (self.home, self.bin, self.data_tmp, self.build_tmp,
                          self.custom_tmp, self.custom_target):
            directory.mkdir(parents=True)
        self.topology = {
            "/": self.filesystem("1", "8:1", "ext4"),
            str(self.data_tmp): self.filesystem("1", "8:1", "ext4"),
            str(self.build_tmp): self.filesystem("2", "8:2", "xfs"),
        }
        self.topology_file = self.root / "topology.json"
        self.calls_file = self.root / "calls.jsonl"
        self.calls_file.write_text("")
        for tool in ("stat", "findmnt"):
            self.executable(tool, f"#!{sys.executable}\n" + PROBE)
        for tool in ("systemd-run", "sysmoni", "check-throttled"):
            self.executable(tool, "#!/bin/sh\nexit 0\n")
        self.executable("nproc", "#!/bin/sh\nprintf '4\\n'\n")
        self.block = self.root / "block.sh"
        self.block.write_text(
            self.block_text.replace("/data/build/tmp/shell", str(self.build_tmp))
            .replace("/data/tmp", str(self.data_tmp))
        )
        self.snapshot = self.root / "snapshot.py"
        self.snapshot.write_text(SNAPSHOT)
        self.env = {
            "PATH": str(self.bin), "HOME": str(self.home), "LC_ALL": "C",
            "SRPS_TEST_TOPOLOGY": str(self.topology_file),
            "SRPS_TEST_CALLS": str(self.calls_file),
        }

    @staticmethod
    def filesystem(device, major_minor, fstype, **extra):
        return dict(device=device, major_minor=major_minor, fstype=fstype, **extra)

    def executable(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def config(self, contents, path=None):
        path = path or self.home / ".config/srps/storage.sh"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def run_policy(self, env=None, prelude="", repeats=1, nested=False,
                   startup=False, denied_access=None):
        self.topology_file.write_text(json.dumps(self.topology))
        environment = dict(self.env, **(env or {}))
        check = (
            'if alias limited >/dev/null 2>&1 && '
            'alias cargo-limited >/dev/null 2>&1 && '
            'alias sys >/dev/null 2>&1 && '
            'alias throttled >/dev/null 2>&1; then srps_test_aliases=yes; '
            'else srps_test_aliases=no; fi\n'
            f'{shlex.quote(sys.executable)} {shlex.quote(str(self.snapshot))} '
            '"${TMPDIR+x}" "${TMPDIR-}" '
            '"${CARGO_TARGET_DIR+x}" "${CARGO_TARGET_DIR-}" "$srps_test_aliases"\n'
        )
        sources = f'. {shlex.quote(str(self.block))}\n' * repeats
        code = "set -eu\n" + prelude + "\n" + sources
        if nested:
            child = "set -eu\n" + sources + check
            code += f'exec {shlex.quote(self.shell_bin)} -c {shlex.quote(child)}\n'
        else:
            code += check
        if startup:
            rc = self.home / (".bashrc" if self.shell == "bash" else ".zshrc")
            rc.write_text("set -eu\n" + prelude + "\n" + sources)
            if self.shell == "bash":
                args = [self.shell_bin, "--noprofile", "--rcfile", str(rc),
                        "-i", "-c", check]
            else:
                environment["ZDOTDIR"] = str(self.home)
                args = [self.shell_bin, "-d", "-i", "-c", check]
        else:
            args = [self.shell_bin, "-c", code]
        privileges = {}
        bypasses_permissions = False
        if denied_access:
            directory, access = denied_access
            predicate = {os.W_OK: "-w", os.X_OK: "-x", os.R_OK: "-r"}[access]
            permission = subprocess.run(
                [self.shell_bin, "-c", f'[ {predicate} "$1" ]',
                 "srps-permission-probe", str(directory)],
                env=environment, capture_output=True, text=True, timeout=15,
            )
            self.assertIn(permission.returncode, (0, 1), permission.stderr)
            bypasses_permissions = permission.returncode == 0
        if bypasses_permissions:
            # Root's -w checks bypass directory mode bits. Run these cases with
            # real unprivileged permissions instead of pretending chmod suffices.
            # Probe the shell itself: Zsh and Bash differ for root without DAC
            # capabilities, so Python os.access alone is not a reliable oracle.
            if os.geteuid() != 0:
                self.skipTest("runner cannot exercise the requested permission denial")
            self.root.chmod(0o755)
            self.calls_file.chmod(0o666)
            privileges = {"user": 65534, "group": 65534, "extra_groups": []}
        try:
            result = subprocess.run(args, env=environment, capture_output=True,
                                    text=True, timeout=15, **privileges)
        except PermissionError:
            if privileges:
                self.skipTest("runner bypasses directory permissions and cannot drop privileges")
            raise
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        try:
            state = json.loads(result.stdout)
        except json.JSONDecodeError:
            self.fail(f"unexpected shell output: {result.stdout!r}; {result.stderr}")
        self.assertTrue(state["aliases"], "storage policy suppressed resource aliases")
        return state, result.stderr

    def assert_unset(self, state, variable):
        self.assertFalse(state[variable + "_set"])
        self.assertEqual(state[variable], "")
        self.assertIsNone(state["exported_" + variable])

    def probes(self):
        return [json.loads(line) for line in self.calls_file.read_text().splitlines()]

    def no_separate_storage(self):
        self.topology[str(self.build_tmp)] = self.filesystem("1", "8:1", "ext4")

    def test_explicit_build_tmp_and_unset_cargo_survive_os_data_tmp(self):
        state, _ = self.run_policy({"TMPDIR": str(self.custom_tmp)})
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assert_unset(state, "cargo")
        self.assertEqual(self.probes(), [], "explicit TMPDIR must bypass detection")

    def test_explicit_both_paths_survive(self):
        state, _ = self.run_policy({"TMPDIR": str(self.custom_tmp),
                                    "CARGO_TARGET_DIR": str(self.custom_target)})
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assertEqual(state["cargo"], str(self.custom_target))
        self.assertEqual(state["exported_cargo"], str(self.custom_target))

    def test_explicit_empty_values_are_preserved(self):
        state, _ = self.run_policy({"TMPDIR": "", "CARGO_TARGET_DIR": ""})
        self.assertTrue(state["tmp_set"])
        self.assertTrue(state["cargo_set"])
        self.assertEqual(state["tmp"], "")
        self.assertEqual(state["cargo"], "")
        self.assertEqual(self.probes(), [])

    def test_unexported_operator_variables_are_not_overridden(self):
        prelude = (f'TMPDIR={shlex.quote(str(self.custom_tmp))}\n'
                   f'CARGO_TARGET_DIR={shlex.quote(str(self.custom_target))}\n')
        state, _ = self.run_policy(prelude=prelude)
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assertEqual(state["cargo"], str(self.custom_target))
        self.assertIsNone(state["exported_tmp"])
        self.assertIsNone(state["exported_cargo"])

    def test_existing_missing_operator_paths_are_not_rewritten(self):
        state, _ = self.run_policy({"TMPDIR": "/operator/offline-volume/tmp",
                                    "CARGO_TARGET_DIR": "project/custom-target"})
        self.assertEqual(state["tmp"], "/operator/offline-volume/tmp")
        self.assertEqual(state["cargo"], "project/custom-target")

    def test_separate_build_volume_is_preferred_to_os_data_tmp(self):
        state, _ = self.run_policy()
        self.assertEqual(state["tmp"], str(self.build_tmp))
        self.assertEqual(state["exported_tmp"], str(self.build_tmp))
        self.assert_unset(state, "cargo")

    def test_separate_build_volume_is_preferred_to_other_separate_volume(self):
        self.topology[str(self.data_tmp)] = self.filesystem("3", "8:3", "ext4")
        state, _ = self.run_policy()
        self.assertEqual(state["tmp"], str(self.build_tmp))
        self.assert_unset(state, "cargo")

    def test_separate_data_tmp_can_supply_scratch_without_global_cargo(self):
        self.build_tmp.rmdir()
        self.topology[str(self.data_tmp)] = self.filesystem("3", "8:3", "ext4")
        state, _ = self.run_policy()
        self.assertEqual(state["tmp"], str(self.data_tmp))
        self.assert_unset(state, "cargo")

    def test_writable_os_directory_is_not_storage_evidence(self):
        self.no_separate_storage()
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")

    def test_missing_candidates_are_not_created(self):
        self.build_tmp.rmdir()
        self.data_tmp.rmdir()
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertFalse(self.build_tmp.exists())
        self.assertFalse(self.data_tmp.exists())

    def test_non_directory_candidate_is_rejected(self):
        self.build_tmp.rmdir()
        self.build_tmp.write_text("not a directory")
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_non_writable_candidate_is_rejected(self):
        self.build_tmp.chmod(0o555)
        self.data_tmp.chmod(0o777)
        state, _ = self.run_policy(denied_access=(self.build_tmp, os.W_OK))
        self.assert_unset(state, "tmp")

    def test_non_searchable_candidate_is_rejected(self):
        self.build_tmp.chmod(0o666)
        self.data_tmp.chmod(0o777)
        state, _ = self.run_policy(denied_access=(self.build_tmp, os.X_OK))
        self.assert_unset(state, "tmp")

    def test_memory_and_unrecognized_filesystems_are_rejected(self):
        for fstype in ("tmpfs", "ramfs", "overlay", "unknown", "", "xfs\next4"):
            with self.subTest(fstype=fstype):
                self.topology[str(self.build_tmp)]["fstype"] = fstype
                state, _ = self.run_policy()
                self.assert_unset(state, "tmp")
                self.assert_unset(state, "cargo")

    def test_failed_filesystem_probe_does_not_select_directory(self):
        self.topology[str(self.build_tmp)]["findmnt_rc"] = 1
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_failed_device_probe_does_not_select_directory(self):
        self.topology[str(self.build_tmp)]["stat_rc"] = 1
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_missing_probes_leave_normal_system_defaults(self):
        for tool in ("stat", "findmnt"):
            with self.subTest(tool=tool):
                path = self.bin / tool
                hidden = self.root / (tool + ".hidden")
                path.rename(hidden)
                try:
                    state, _ = self.run_policy()
                    self.assert_unset(state, "tmp")
                    self.assert_unset(state, "cargo")
                finally:
                    hidden.rename(path)

    def test_invalid_device_evidence_fails_closed(self):
        for device in ("", "unknown", "2\n3", "2x"):
            with self.subTest(device=device):
                self.topology[str(self.build_tmp)]["device"] = device
                state, _ = self.run_policy()
                self.assert_unset(state, "tmp")

    def test_disagreeing_device_and_mount_identity_fails_closed(self):
        self.topology[str(self.build_tmp)]["major_minor"] = "8:1"
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_invalid_mount_identity_fails_closed(self):
        for mount in ("", "unknown", "8", ":2", "8:", "8:2:3",
                      "8:2\n8:3", "8:2 extra"):
            with self.subTest(mount=mount):
                self.topology[str(self.build_tmp)]["major_minor"] = mount
                state, _ = self.run_policy()
                self.assert_unset(state, "tmp")

    def test_failed_root_probe_fails_closed(self):
        self.topology["/"]["stat_rc"] = 1
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_invalid_root_mount_identity_fails_closed(self):
        for mount in ("", "unknown", "8", "8:1\n8:2"):
            with self.subTest(mount=mount):
                self.topology["/"]["major_minor"] = mount
                state, _ = self.run_policy()
                self.assert_unset(state, "tmp")

    def test_failed_root_mount_probe_fails_closed(self):
        self.topology["/"]["findmnt_rc"] = 1
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")

    def test_explicit_scratch_configuration_works_on_os_filesystem(self):
        state, _ = self.run_policy({"SRPS_TMPDIR": str(self.data_tmp)})
        self.assertEqual(state["tmp"], str(self.data_tmp))
        self.assert_unset(state, "cargo")
        self.assertEqual(self.probes(), [])

    def test_empty_scratch_override_disables_automatic_selection(self):
        state, _ = self.run_policy({"SRPS_TMPDIR": ""})
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertEqual(self.probes(), [])

    def test_invalid_explicit_scratch_does_not_fall_back_elsewhere(self):
        missing = self.root / "offline-volume/tmp"
        state, diagnostic = self.run_policy({"SRPS_TMPDIR": str(missing)})
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertFalse(missing.exists())
        self.assertTrue(diagnostic.strip(), "invalid explicit storage needs a diagnostic")
        self.assertEqual(self.probes(), [])

    def test_non_writable_explicit_scratch_is_reported(self):
        self.custom_tmp.chmod(0o555)
        state, diagnostic = self.run_policy(
            {"SRPS_TMPDIR": str(self.custom_tmp)},
            denied_access=(self.custom_tmp, os.W_OK)
        )
        self.assert_unset(state, "tmp")
        self.assertTrue(diagnostic.strip())

    def test_global_cargo_is_only_an_explicit_choice(self):
        target = self.root / "not-created-yet/cargo-target"
        state, _ = self.run_policy({"SRPS_CARGO_TARGET_DIR": str(target)})
        self.assertEqual(state["cargo"], str(target))
        self.assertEqual(state["exported_cargo"], str(target))
        self.assertFalse(target.exists(), "the shell must not create build directories")

    def test_explicit_environment_wins_over_configured_defaults(self):
        self.config(f'SRPS_TMPDIR={shlex.quote(str(self.data_tmp))}\n'
                    'SRPS_CARGO_TARGET_DIR=/configured/default/target\n')
        state, _ = self.run_policy({"TMPDIR": str(self.custom_tmp),
                                    "CARGO_TARGET_DIR": str(self.custom_target)})
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assertEqual(state["cargo"], str(self.custom_target))

    def test_durable_user_configuration_is_read_at_shell_startup(self):
        config = self.config(f'SRPS_TMPDIR={shlex.quote(str(self.custom_tmp))}\n')
        before = config.read_bytes()
        state, _ = self.run_policy(startup=True)
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assert_unset(state, "cargo")
        self.assertEqual(config.read_bytes(), before)

    def test_xdg_and_explicit_config_locations(self):
        for explicit in (False, True):
            with self.subTest(explicit=explicit):
                xdg = self.root / "xdg config"
                location = (self.root / "operator storage.sh" if explicit
                            else xdg / "srps/storage.sh")
                self.config(f'SRPS_TMPDIR={shlex.quote(str(self.custom_tmp))}\n'
                            f'SRPS_CARGO_TARGET_DIR={shlex.quote(str(self.custom_target))}\n',
                            path=location)
                env = ({"SRPS_STORAGE_CONFIG": str(location)} if explicit
                       else {"XDG_CONFIG_HOME": str(xdg)})
                state, _ = self.run_policy(env)
                self.assertEqual(state["tmp"], str(self.custom_tmp))
                self.assertEqual(state["cargo"], str(self.custom_target))

    def test_explicit_missing_config_does_not_use_automatic_storage(self):
        missing = self.root / "operator-missing.conf"
        state, diagnostic = self.run_policy({"SRPS_STORAGE_CONFIG": str(missing),
                                             "SRPS_CARGO_TARGET_DIR": "/target"})
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())
        self.assertFalse(missing.exists())
        self.assertEqual(self.probes(), [])

    def test_explicit_config_directory_is_rejected(self):
        state, diagnostic = self.run_policy({"SRPS_STORAGE_CONFIG": str(self.home)})
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())
        self.assertEqual(self.probes(), [])

    def test_dangling_default_config_symlink_fails_closed(self):
        config = self.home / ".config/srps/storage.sh"
        config.parent.mkdir(parents=True)
        config.symlink_to(self.root / "missing-storage-policy")
        state, diagnostic = self.run_policy()
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())
        self.assertEqual(self.probes(), [])

    def test_unreadable_config_fails_closed(self):
        config = self.config('SRPS_STORAGE_POLICY=preserve\n')
        config.chmod(0o000)
        state, diagnostic = self.run_policy(denied_access=(config, os.R_OK))
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())
        self.assertEqual(self.probes(), [])

    def test_absent_optional_config_still_allows_verified_storage(self):
        self.assertFalse((self.home / ".config/srps/storage.sh").exists())
        state, _ = self.run_policy()
        self.assertEqual(state["tmp"], str(self.build_tmp))
        self.assert_unset(state, "cargo")

    def test_preserve_mode_keeps_aliases_and_leaves_storage_unset(self):
        self.config('SRPS_STORAGE_POLICY=preserve\n'
                    f'SRPS_TMPDIR={shlex.quote(str(self.custom_tmp))}\n'
                    'SRPS_CARGO_TARGET_DIR=/configured/default/target\n')
        state, _ = self.run_policy()
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertEqual(self.probes(), [])

    def test_preserve_mode_keeps_explicit_environment(self):
        state, _ = self.run_policy({"SRPS_STORAGE_POLICY": "preserve",
                                    "TMPDIR": str(self.custom_tmp),
                                    "CARGO_TARGET_DIR": str(self.custom_target)})
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assertEqual(state["cargo"], str(self.custom_target))

    def test_unknown_policy_does_not_apply_storage_defaults(self):
        state, diagnostic = self.run_policy({"SRPS_STORAGE_POLICY": "typo",
                                             "SRPS_CARGO_TARGET_DIR": "/target"})
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())

    def test_failed_configuration_does_not_apply_defaults(self):
        self.config('SRPS_CARGO_TARGET_DIR=/target\nreturn 1\n')
        state, diagnostic = self.run_policy()
        self.assert_unset(state, "tmp")
        self.assert_unset(state, "cargo")
        self.assertTrue(diagnostic.strip())

    def test_repeated_sourcing_and_nested_shell_keep_operator_storage(self):
        state, _ = self.run_policy({"TMPDIR": str(self.custom_tmp)},
                                    repeats=3, nested=True)
        self.assertEqual(state["tmp"], str(self.custom_tmp))
        self.assert_unset(state, "cargo")
        self.assertEqual(self.probes(), [])


class BashStoragePolicy(PolicyCases, unittest.TestCase):
    shell = "bash"


class ZshStoragePolicy(PolicyCases, unittest.TestCase):
    shell = "zsh"


if __name__ == "__main__":
    unittest.main(verbosity=2)
