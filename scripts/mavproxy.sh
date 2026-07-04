#!/usr/bin/env bash
set -eo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
: > "${HOME}/.mavinit.scr"

until (echo > /dev/tcp/127.0.0.1/5760) 2>/dev/null; do
  sleep 2
done

# Interactive terminal: STABILIZE> prompt for ad-hoc commands (arm, mode, takeoff, …)
exec mavproxy.py \
  --master=tcp:127.0.0.1:5760 \
  --out=udp:127.0.0.1:14550
