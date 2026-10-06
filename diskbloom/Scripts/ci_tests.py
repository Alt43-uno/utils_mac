#!/usr/bin/env python3
"""Run CI checks with a bounded timeout and macOS runner diagnostics."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
process = subprocess.Popen([str(root / 'Scripts/test.sh')], cwd=root, start_new_session=True)
try:
    sys.exit(process.wait(timeout=120))
except subprocess.TimeoutExpired:
    print('Test driver exceeded 120 seconds; collecting process stacks.', flush=True)
    rows = subprocess.check_output(['ps', '-axo', 'pid,ppid,etime,state,comm'], text=True)
    print(rows, flush=True)
    reports = root / '.build/ci-diagnostics'
    reports.mkdir(parents=True, exist_ok=True)
    for line in rows.splitlines()[1:]:
        if 'DiskBloomPackageTests' not in line and 'swift-test' not in line:
            continue
        pid = line.split()[0]
        report = reports / ('sample-' + pid + '.txt')
        subprocess.run(['sample', pid, '3', '1', '-file', str(report)], timeout=15, check=False)
        if report.exists():
            print(report.read_text(errors='replace'), flush=True)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(1)
