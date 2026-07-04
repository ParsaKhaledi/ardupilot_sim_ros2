#!/usr/bin/env python3
"""Set gimbal pitch to nadir via MAVLink RC override on channel 7."""

import sys
import time

from pymavlink import mavutil

MASTER = sys.argv[1] if len(sys.argv) > 1 else "tcp:127.0.0.1:5760"
PITCH_PWM = int(sys.argv[2]) if len(sys.argv) > 2 else 1300
INTERVAL_SEC = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
DURATION_SEC = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0

NO_OVERRIDE = 65535


def main() -> int:
    mav = mavutil.mavlink_connection(MASTER, source_system=255)
    print(f"Waiting for heartbeat on {MASTER}...")
    mav.wait_heartbeat(timeout=60)

    if DURATION_SEC > 0:
        print(f"Holding RC7={PITCH_PWM} for {DURATION_SEC}s")
        deadline = time.time() + DURATION_SEC
    else:
        print(f"Holding RC7={PITCH_PWM} until stopped")
        deadline = None

    while deadline is None or time.time() < deadline:
        mav.mav.rc_channels_override_send(
            mav.target_system,
            mav.target_component,
            NO_OVERRIDE,
            NO_OVERRIDE,
            NO_OVERRIDE,
            NO_OVERRIDE,
            NO_OVERRIDE,
            NO_OVERRIDE,
            PITCH_PWM,
            NO_OVERRIDE,
        )
        time.sleep(INTERVAL_SEC)

    print("Done holding gimbal pitch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
