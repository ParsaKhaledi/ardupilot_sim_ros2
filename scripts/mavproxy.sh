#!/usr/bin/env bash
set -euo pipefail

mavproxy.py \
  --master=tcp:127.0.0.1:5760 \
  --out=udp:127.0.0.1:14550 \
  --map \
  --console
