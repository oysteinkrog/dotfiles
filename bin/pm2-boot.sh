#!/bin/bash
# Resurrect the PM2 daemon + saved process list at Windows logon.
# Invoked by pm2-resurrect.vbs in the Windows Startup folder via wsl.exe.
# nvm's node is not on PATH in a bare wsl.exe session, so add it explicitly.

NODE_BIN="/c/users/oystein/.nvm/versions/node/v22.14.0/bin"
export PATH="$NODE_BIN:$PATH"

LOG=/c/users/oystein/.pm2/boot.log
{
  echo "=== pm2-boot $(date -Is) ==="
  "$NODE_BIN/pm2" resurrect
  "$NODE_BIN/pm2" list
} >>"$LOG" 2>&1
