#!/usr/bin/env bash
set -eo pipefail

export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"
source "/opt/ros/${ROS_DISTRO}/setup.bash"

CAMERA_TOPIC="${CAMERA_TOPIC:-/camera/image}"
WAIT_SEC="${RQT_WAIT_SEC:-120}"

echo "Waiting up to ${WAIT_SEC}s for topic: ${CAMERA_TOPIC}"
deadline=$((SECONDS + WAIT_SEC))
while (( SECONDS < deadline )); do
  if ros2 topic list 2>/dev/null | grep -Fxq "${CAMERA_TOPIC}"; then
    echo "Found ${CAMERA_TOPIC}"
    break
  fi
  sleep 2
done

if ! ros2 topic list 2>/dev/null | grep -Fxq "${CAMERA_TOPIC}"; then
  echo "Topic ${CAMERA_TOPIC} not available. Check sim logs: docker compose logs sim"
  exit 1
fi

echo "Launching rqt_image_view on ${CAMERA_TOPIC}"
exec ros2 run rqt_image_view rqt_image_view "${CAMERA_TOPIC}"
