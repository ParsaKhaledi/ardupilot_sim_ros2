#!/usr/bin/env bash
set -eo pipefail

export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"
source "/opt/ros/${ROS_DISTRO}/setup.bash"

export GZ_VERSION="${GZ_VERSION:-harmonic}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="/home/ardupilot/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
export GZ_SIM_RESOURCE_PATH="/home/ardupilot/ardupilot_gazebo/models:/home/ardupilot/ardupilot_gazebo/worlds:/workspace/worlds:${GZ_SIM_RESOURCE_PATH:-}"

CAMERA_PROFILE="${CAMERA_PROFILE:-gimbal}"
WORLD_PROFILE="${WORLD_PROFILE:-world-default}"
MODEL_PROFILE="${MODEL_PROFILE:-iris_with_gimbal}"
SIM_SPEEDUP="${SIM_SPEEDUP:-1}"
PHYSICS_STEP_SIZE="${PHYSICS_STEP_SIZE:-0.002}"
GZ_HEADLESS="${GZ_HEADLESS:-false}"
GZ_SERVER_ONLY="${GZ_SERVER_ONLY:-false}"
ENABLE_GST_STREAM="${ENABLE_GST_STREAM:-false}"

DEFAULTS_FILE="Tools/autotest/default_params/copter.parm,/home/ardupilot/ardupilot_gazebo/config/gazebo-iris-gimbal.parm"
ROBOT_NAME="${MODEL_PROFILE}"
CAMERA_LINK="pitch_link"
BRIDGE_FILE="/tmp/ros_gz_bridge.yaml"

case "${WORLD_PROFILE}" in
  world-default)
    WORLD_FILE="/workspace/worlds/iris_simple.sdf"
    WORLD_NAME="iris_simple"
    ;;
  world-runway)
    WORLD_FILE="/home/ardupilot/ardupilot_gazebo/worlds/iris_runway.sdf"
    WORLD_NAME="iris_runway"
    ;;
  world-alt)
    WORLD_FILE="/home/ardupilot/ardupilot_gazebo/worlds/iris_warehouse.sdf"
    WORLD_NAME="iris_warehouse"
    ;;
  world-aruco)
    WORLD_FILE="/workspace/worlds/iris_aruco_4tags.sdf"
    WORLD_NAME="iris_aruco_4tags"
    ;;
  *)
    echo "Unsupported WORLD_PROFILE: ${WORLD_PROFILE}"
    exit 1
    ;;
esac

if [[ "${CAMERA_PROFILE}" == "fixed-down" ]]; then
  CAMERA_LINK="pitch_link"
fi

export WORLD_NAME ROBOT_NAME CAMERA_LINK
sed -e "s/\${WORLD_NAME}/${WORLD_NAME}/g" \
    -e "s/\${ROBOT_NAME}/${ROBOT_NAME}/g" \
    -e "s/\${CAMERA_LINK}/${CAMERA_LINK}/g" \
  /workspace/config/bridge_template.yaml > "${BRIDGE_FILE}"

WORLD_RUNTIME="/tmp/world_runtime.sdf"
cp "${WORLD_FILE}" "${WORLD_RUNTIME}"
sed -i "s|<max_step_size>.*</max_step_size>|<max_step_size>${PHYSICS_STEP_SIZE}</max_step_size>|" "${WORLD_RUNTIME}"

GZ_ARGS=(-v4 -r "${WORLD_RUNTIME}")
if [[ "${GZ_SERVER_ONLY}" == "true" ]]; then
  GZ_ARGS=(-v4 -s -r "${WORLD_RUNTIME}")
elif [[ "${GZ_HEADLESS}" == "true" ]]; then
  GZ_ARGS=(-v4 -r --headless-rendering "${WORLD_RUNTIME}")
fi

echo "Launching Gazebo (server_only=${GZ_SERVER_ONLY}, headless=${GZ_HEADLESS}): ${WORLD_RUNTIME}"
gz sim "${GZ_ARGS[@]}" &
GZ_PID=$!

sleep 4

echo "Starting SITL with defaults: ${DEFAULTS_FILE}"
cd /home/ardupilot/ardupilot
./build/sitl/bin/arducopter -S \
  --model JSON \
  --speedup "${SIM_SPEEDUP}" \
  --defaults "${DEFAULTS_FILE}" \
  --sim-address=127.0.0.1 \
  -I0 &
SITL_PID=$!

sleep 4

if [[ "${ENABLE_GST_STREAM}" == "true" ]]; then
  CAMERA_ENABLE_TOPIC="$(gz topic -l | grep "/enable_streaming$" | head -n 1 || true)"
  if [[ -n "${CAMERA_ENABLE_TOPIC}" ]]; then
    echo "Enabling streaming on topic: ${CAMERA_ENABLE_TOPIC}"
    gz topic -t "${CAMERA_ENABLE_TOPIC}" -m gz.msgs.Boolean -p "data: 1" || true
  else
    echo "No enable_streaming topic found, skipping."
  fi
fi

echo "Starting ros_gz_bridge with config: ${BRIDGE_FILE}"
ros2 run ros_gz_bridge parameter_bridge --ros-args -p config_file:="${BRIDGE_FILE}" &
BRIDGE_PID=$!

if [[ "${CAMERA_PROFILE}" == "fixed-down" ]]; then
  echo "Applying runtime downward camera preset (MAVProxy RC7)."
  (
    sleep 12
    mavproxy.py --master=tcp:127.0.0.1:5760 --cmd="rc 7 1100" --daemon
  ) || true
fi

trap 'kill ${BRIDGE_PID} ${SITL_PID} ${GZ_PID} 2>/dev/null || true' INT TERM EXIT
wait -n "${BRIDGE_PID}" "${SITL_PID}" "${GZ_PID}"
