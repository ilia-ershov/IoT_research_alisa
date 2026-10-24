#!/usr/bin/env python3
"""Upload a shell script to the router over SFTP and run it with `sh`."""
import sys, os
import paramiko

host, user, pw, local = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
remote = "/tmp/" + os.path.basename(local)

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(host, username=user, password=pw, timeout=10,
          allow_agent=False, look_for_keys=False,
          banner_timeout=20, auth_timeout=20)
sftp = c.open_sftp()
sftp.put(local, remote)
sftp.close()
stdin, stdout, stderr = c.exec_command(f"sh {remote}", timeout=180)
out = stdout.read().decode(errors="replace")
err = stderr.read().decode(errors="replace")
rc = stdout.channel.recv_exit_status()
sys.stdout.write(out)
if err:
    sys.stderr.write(err)
sys.stderr.write(f"=== EXIT {rc} ===\n")
c.exec_command(f"rm -f {remote}")
c.close()
