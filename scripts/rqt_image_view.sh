#!/usr/bin/env bash
set -eo pipefail

export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"
source "/opt/ros/${ROS_DISTRO}/setup.bash"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

CAMERA_TOPIC="${CAMERA_TOPIC:-/camera/rgb/image_raw}"
WAIT_SEC="${RQT_WAIT_SEC:-120}"

echo "Waiting up to ${WAIT_SEC}s for publisher on: ${CAMERA_TOPIC} (RMW=${RMW_IMPLEMENTATION})"
deadline=$((SECONDS + WAIT_SEC))
while (( SECONDS < deadline )); do
  pub_count="$(ros2 topic info "${CAMERA_TOPIC}" 2>/dev/null | awk '/Publisher count:/ {print $3}')"
  if [[ -n "${pub_count}" && "${pub_count}" != "0" ]]; then
    echo "Found publisher on ${CAMERA_TOPIC}"
    break
  fi
  sleep 2
done

pub_count="$(ros2 topic info "${CAMERA_TOPIC}" 2>/dev/null | awk '/Publisher count:/ {print $3}')"
if [[ -z "${pub_count}" || "${pub_count}" == "0" ]]; then
  echo "No publisher on ${CAMERA_TOPIC}. Check: docker compose logs sim | grep ros_gz_bridge"
  exit 1
fi

echo "Launching rqt_image_view on ${CAMERA_TOPIC}"
exec ros2 run rqt_image_view rqt_image_view "${CAMERA_TOPIC}"
