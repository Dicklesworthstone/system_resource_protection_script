#!/usr/bin/env python3
"""Execute installer functions and the embedded doctor with sandbox command mocks."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'install.sh').read_text()

def function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}', SOURCE, re.M | re.S)[0]

class Reliability(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, PATH=str(self.root)+':'+os.environ['PATH'], MOCK_ROOT=str(self.root))
        self.mock('sudo', 'exit 1')
        self.mock('sleep', ':')
        self.mock('systemctl', '''if [ "$1" != show ]; then exit 0; fi
n=$(cat "$MOCK_ROOT/count" 2>/dev/null || echo 0)
echo $((n+1)) > "$MOCK_ROOT/count"
printf 'ActiveState=active\\nSubState=running\\nExecMainStatus=0\\n'
echo "NRestarts=${RESTARTS:-0}"
echo "ExecMainStartTimestampMonotonic=${START:-100}"
''')
        self.mock('journalctl', 'echo "Worker initialized with 42 rules"')
        self.mock('ananicy-cpp', 'echo v1')
    def mock(self, name, body):
        p = self.root/name
        p.write_text('#!/bin/bash\n'+body+'\n')
        p.chmod(0o755)
    def run_shell(self, code):
        return subprocess.run(['bash','-c','set -euo pipefail\n'+code], env=self.env, text=True, capture_output=True)
    def installer(self, names, body):
        return self.run_shell('print_warning(){ echo "$*" >&2; }; print_info(){ :; }; print_success(){ :; }; print_step(){ :; }; die(){ echo "$*" >&2; exit 1; }\n'+ '\n'.join(function(n) for n in names)+'\n'+body)
    def test_loader_failure_and_recovery(self):
        names=['ananicy_cpp_bin','ananicy_cpp_installed']
        self.mock('ananicy-cpp', 'echo "error while loading shared libraries: libfmt.so: not found" >&2; exit 127')
        r=self.installer(names, 'ananicy_cpp_installed')
        self.assertNotEqual(r.returncode,0)
        self.assertIn('libfmt.so',r.stderr)
        self.mock('ananicy-cpp','echo v1')
        self.assertEqual(self.installer(names,'ananicy_cpp_installed').returncode,0)
    def test_rebuild_path_recovers(self):
        self.mock('ananicy-cpp','exit 127')
        # All package/build operations are mocks. make install replaces only our sandbox binary.
        self.mock('sudo','"$@"')
        self.mock('cmake', ':')
        self.mock('make', '''if [ "${1:-}" = install ]; then
printf '#!/bin/bash\\necho v1\\n' > "$MOCK_ROOT/ananicy-cpp"
fi''')
        names=['ananicy_cpp_bin','ananicy_cpp_installed','install_ananicy_cpp']
        r=self.installer(names, '''ENABLE_ANANICY=1; TOTAL_STEPS=5
apt_install(){ echo "$*" > "$MOCK_ROOT/packages"; }
maybe_dry_run(){ return 1; }
git_clone_retry(){ mkdir -p ananicy-cpp; }
install_ananicy_cpp
ananicy_cpp_installed''')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('libspdlog-dev',(self.root/'packages').read_text())
    def test_stable_service(self):
        self.assertEqual(self.installer(['srps_service_stable'],'srps_service_stable').returncode,0)
    def test_crash_loop_even_when_active(self):
        p=self.root/'systemctl'
        p.write_text(p.read_text().replace('${RESTARTS:-0}','$n'))
        self.assertNotEqual(self.installer(['srps_service_stable'],'srps_service_stable').returncode,0)
    def test_start_failure(self):
        self.mock('systemctl','echo ActiveState=failed; echo SubState=auto-restart; echo ExecMainStatus=127')
        self.assertNotEqual(self.installer(['srps_service_stable'],'srps_service_stable').returncode,0)
    def test_summary_fails_without_success_banner(self):
        self.mock('systemctl','exit 1')
        r=self.installer(['ananicy_cpp_bin','ananicy_cpp_installed','srps_service_stable','show_final_summary_install'], 'DRY_RUN=0; ENABLE_ANANICY=1; HAS_SYSTEMD=1; show_final_summary_install')
        self.assertNotEqual(r.returncode,0)
        self.assertNotIn('SETUP COMPLETE',r.stdout)
    def test_start_clears_exhausted_start_limit(self):
        # A unit that crash-looped into its start limit refuses manual starts
        # until reset-failed clears the limit; the start must not die on it.
        (self.root/'start-limit-hit').write_text('')
        self.mock('sudo','"$@"')
        self.mock('systemctl', '''echo "$*" >> "$MOCK_ROOT/calls"
case "$1" in
reset-failed) rm -f "$MOCK_ROOT/start-limit-hit" ;;
enable|restart) [ ! -e "$MOCK_ROOT/start-limit-hit" ] || exit 1 ;;
show) printf 'ActiveState=active\\nSubState=running\\nExecMainStatus=0\\nNRestarts=0\\nExecMainStartTimestampMonotonic=100\\n' ;;
esac''')
        names=['srps_service_stable','srps_start_ananicy_service']
        r=self.installer(names,'srps_start_ananicy_service; echo "startup=$SRPS_STARTUP_NRESTARTS"')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('startup=NRestarts=0',r.stdout)
        calls=(self.root/'calls').read_text().splitlines()
        self.assertEqual(calls[:3],['reset-failed ananicy-cpp','enable --now ananicy-cpp','restart ananicy-cpp'])
        # Without the reset, the same unit is refused and the installer stops.
        (self.root/'start-limit-hit').write_text('')
        self.mock('systemctl', '''case "$1" in
reset-failed) exit 1 ;;
enable|restart) [ ! -e "$MOCK_ROOT/start-limit-hit" ] || exit 1 ;;
esac''')
        r=self.installer(names,'srps_start_ananicy_service')
        self.assertNotEqual(r.returncode,0)
        self.assertIn('Failed to enable/start',r.stderr)
    def test_summary_detects_restart_after_startup(self):
        names=['ananicy_cpp_bin','ananicy_cpp_installed','srps_service_stable','show_final_summary_install']
        colors='CYAN= BOLD= NC= GREEN= RED= YELLOW= MAGENTA= SHELL_RC=/sandbox/rc; '
        self.env['RESTARTS']='1'
        r=self.installer(names, colors+'DRY_RUN=0; ENABLE_ANANICY=1; HAS_SYSTEMD=1; SRPS_STARTUP_NRESTARTS=NRestarts=0; show_final_summary_install')
        self.assertNotEqual(r.returncode,0)
        self.assertIn('restarted after startup verification',r.stdout+r.stderr)
        self.assertNotIn('SETUP COMPLETE',r.stdout)
        r=self.installer(names, colors+'DRY_RUN=0; ENABLE_ANANICY=1; HAS_SYSTEMD=1; SRPS_STARTUP_NRESTARTS=NRestarts=1; show_final_summary_install')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('SETUP COMPLETE',r.stdout)
    def test_healthy_summary_and_plan(self):
        names=['ananicy_cpp_bin','ananicy_cpp_installed','srps_service_stable','show_final_summary_install']
        colors='CYAN= BOLD= NC= GREEN= RED= YELLOW= MAGENTA= SHELL_RC=/sandbox/rc; '
        r=self.installer(names, colors+'DRY_RUN=0; ENABLE_ANANICY=1; HAS_SYSTEMD=1; show_final_summary_install')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('SETUP COMPLETE',r.stdout)
        self.mock('systemctl','exit 1')
        r=self.installer(names, 'DRY_RUN=1; show_final_summary_install')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertNotIn('SETUP COMPLETE',r.stdout)
    def doctor(self, json_mode=False):
        doctor=SOURCE.split('sudo tee "$srps_doctor" >/dev/null << \'EOF\'\n')[1].split('\nEOF')[0]
        self.env['SRPS_JSON']='1' if json_mode else '0'
        r=self.run_shell(doctor)
        self.assertEqual(r.returncode,0,r.stderr)
        return json.loads(r.stdout) if json_mode else r.stdout
    def test_healthy_doctor_completes(self):
        text=self.doctor()
        self.assertIn('none seen',text)
        self.assertIn('recommendations',text)
        self.assertEqual(self.doctor(True)['ananicy_errors'],[])
    def test_permissions_unknown(self):
        for body in ['echo "Hint: You are currently not seeing messages from other users" >&2; echo "-- No entries --"', 'echo "Permission denied" >&2; exit 1', 'echo "-- No entries --"']:
            self.mock('journalctl',body)
            self.assertIn('unknown:',self.doctor())
            self.assertIsNone(self.doctor(True)['ananicy_errors'])
    def test_log_lines_mentioning_permissions_are_evidence(self):
        # Access problems are reported on stderr. Log content that mentions
        # permissions is readable evidence, for ananicy and for system errors.
        lines=['Failed to set nice: Operation not permitted','error writing cgroup: Permission denied']
        self.mock('journalctl', "printf '%s\\n' " + ' '.join(repr(l) for l in lines))
        doc=self.doctor(True)
        self.assertEqual(doc['ananicy_errors'],lines)
        self.assertEqual(doc['ananicy_journal_status'],'readable')
        text=self.doctor()
        self.assertNotIn('unknown:',text)
        self.assertEqual(text.count(lines[1]),2)
    def test_sudo_journal_recovery(self):
        self.mock('journalctl','exit 1')
        self.mock('sudo','if [ "${2:-}" = env ]; then echo "Worker initialized"; else exit 1; fi')
        self.assertEqual(self.doctor(True)['ananicy_errors'],[])
    def test_error_json_escaping(self):
        self.mock('journalctl', '''printf '%s\\n' 'fatal: "libfmt" at C:\\lib missing' 'cgroup error already exists' ''')
        self.assertEqual(self.doctor(True)['ananicy_errors'],['fatal: "libfmt" at C:\\lib missing'])

if __name__ == '__main__':
    unittest.main(verbosity=2)
