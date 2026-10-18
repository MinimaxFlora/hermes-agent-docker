#!/usr/bin/env bash
set -uo pipefail
OUT=/root/hvtest/procs.txt
: >"$OUT"
{
  echo "== gateway processes =="
  docker compose -f /root/hvtest/compose.yml exec -T gateway ps -eo pid,user,args 2>&1 | head -40
  echo "== dashboard processes =="
  docker compose -f /root/hvtest/compose.yml exec -T dashboard ps -eo pid,user,args 2>&1 | head -40
  echo "== gateway status =="
  docker compose -f /root/hvtest/compose.yml exec -T -u 10000:10000 -e HOME=/opt/data gateway hermes gateway status 2>&1 | head -30
  echo "== socat 8642 =="
  ss -lntp 2>/dev/null | grep 8642 || true
} >>"$OUT" 2>&1
cp "$OUT" /mnt/d/hvtest-procs.txt
