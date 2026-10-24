#!/usr/bin/env python3
"""Minimal non-interactive SSH runner (password auth, no local pty needed)."""
import sys
import paramiko

host, user, pw, cmd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(
    host,
    username=user,
    password=pw,
    timeout=10,
    allow_agent=False,
    look_for_keys=False,
    banner_timeout=20,
    auth_timeout=20,
)
stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
out = stdout.read().decode(errors="replace")
err = stderr.read().decode(errors="replace")
rc = stdout.channel.recv_exit_status()
if out:
    sys.stdout.write(out)
    if not out.endswith("\n"):
        sys.stdout.write("\n")
if err:
    sys.stderr.write(err)
    if not err.endswith("\n"):
        sys.stderr.write("\n")
sys.stderr.write(f"=== EXIT {rc} ===\n")
client.close()
