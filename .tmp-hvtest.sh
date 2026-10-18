#!/usr/bin/env bash
set -uo pipefail
OUT=/root/hvtest/out.txt
: >"$OUT"
{
  echo "== ps =="
  docker compose -f /root/hvtest/compose.yml ps 2>&1
  echo "== version =="
  docker compose -f /root/hvtest/compose.yml exec -T -u 10000:10000 -e HOME=/opt/data gateway hermes --version 2>&1
  echo "rc=$?"
  echo "== id =="
  docker compose -f /root/hvtest/compose.yml exec -T -u 10000:10000 gateway id 2>&1
  echo "rc=$?"
  echo "== config set =="
  docker compose -f /root/hvtest/compose.yml exec -T -u 10000:10000 -e HOME=/opt/data gateway hermes config set model.provider deepseek 2>&1
  echo "rc=$?"
  echo "== config get =="
  docker compose -f /root/hvtest/compose.yml exec -T -u 10000:10000 -e HOME=/opt/data gateway hermes config get model.provider 2>&1
  echo "rc=$?"
  echo "== data =="
  ls -la /root/hvtest/data | head -20
  echo "== ports =="
  ss -lntp 2>/dev/null | grep 9119 || true
  echo "== curl =="
  curl -sS -m 5 -o /dev/null -w "dash=%{http_code}\n" http://127.0.0.1:9119/ 2>&1
  echo "== dashboard logs =="
  docker compose -f /root/hvtest/compose.yml logs --tail=20 dashboard 2>&1
  echo "== gateway logs =="
  docker compose -f /root/hvtest/compose.yml logs --tail=30 gateway 2>&1
} >>"$OUT" 2>&1
cp "$OUT" /mnt/d/hvtest-out.txt
