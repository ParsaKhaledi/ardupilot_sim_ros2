#!/usr/bin/env bash
set -eo pipefail

export AMENT_TRACE_SETUP_FILES="${AMENT_TRACE_SETUP_FILES:-}"
source "/opt/ros/${ROS_DISTRO}/setup.bash"

# CycloneDDS works across Docker containers; FastDDS shared-memory does not.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

export GZ_VERSION="${GZ_VERSION:-harmonic}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="/home/ardupilot/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
export GZ_SIM_RESOURCE_PATH="/workspace/models:/workspace/worlds:/home/ardupilot/ardupilot_gazebo/models:/home/ardupilot/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH:-}"

CAMERA_PROFILE="${CAMERA_PROFILE:-gimbal}"
WORLD_PROFILE="${WORLD_PROFILE:-world-default}"
MODEL_PROFILE="${MODEL_PROFILE:-iris_with_down_camera}"
SIM_SPEEDUP="${SIM_SPEEDUP:-1}"
PHYSICS_STEP_SIZE="${PHYSICS_STEP_SIZE:-0.001}"
GZ_HEADLESS="${GZ_HEADLESS:-false}"
GZ_SERVER_ONLY="${GZ_SERVER_ONLY:-false}"
ENABLE_GST_STREAM="${ENABLE_GST_STREAM:-false}"

DEFAULTS_FILE="Tools/autotest/default_params/copter.parm"
ROBOT_NAME="${MODEL_PROFILE}"
CAMERA_LINK="down_camera_link"
USE_GIMBAL_NADIR=false
HAS_CAMERA=true
BRIDGE_FILE="/tmp/ros_gz_bridge.yaml"

case "${MODEL_PROFILE}" in
  iris_with_ardupilot)
    CAMERA_LINK=""
    HAS_CAMERA=false
    ;;
  iris_with_down_camera)
    CAMERA_LINK="down_camera_link"
    ;;
  iris_with_gimbal)
    DEFAULTS_FILE="Tools/autotest/default_params/copter.parm,/home/ardupilot/ardupilot_gazebo/config/gazebo-iris-gimbal.parm,/workspace/config/gazebo-camera-nadir.parm"
    CAMERA_LINK="pitch_link"
    USE_GIMBAL_NADIR=true
    ;;
  *)
    echo "Unsupported MODEL_PROFILE: ${MODEL_PROFILE}"
    exit 1
    ;;
esac

CAMERA_GZ_IMAGE_TOPIC="/camera/rgb/image_raw"
CAMERA_GZ_INFO_TOPIC="/camera/rgb/camera_info"

case "${WORLD_PROFILE}" in
  world-default)
    WORLD_FILE="/workspace/worlds/iris_simple.sdf"
    WORLD_NAME="iris_simple"
    ;;
  world-runway)
    WORLD_FILE="/workspace/worlds/iris_runway.sdf"
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

# Gimbal-only: RC7 1300 => mount pitch -90 deg (nadir).
GIMBAL_PITCH_NADIR_PWM=1300
GIMBAL_PITCH_NADIR_RAD=0.0

export WORLD_NAME ROBOT_NAME CAMERA_LINK CAMERA_GZ_IMAGE_TOPIC CAMERA_GZ_INFO_TOPIC
sed -e "s/\${WORLD_NAME}/${WORLD_NAME}/g" \
    -e "s/\${ROBOT_NAME}/${ROBOT_NAME}/g" \
    -e "s/\${CAMERA_LINK}/${CAMERA_LINK}/g" \
    -e "s|\${CAMERA_GZ_IMAGE_TOPIC}|${CAMERA_GZ_IMAGE_TOPIC}|g" \
    -e "s|\${CAMERA_GZ_INFO_TOPIC}|${CAMERA_GZ_INFO_TOPIC}|g" \
  /workspace/config/bridge_template.yaml > "${BRIDGE_FILE}"

WORLD_RUNTIME="/tmp/world_runtime.sdf"
cp "${WORLD_FILE}" "${WORLD_RUNTIME}"
PHYSICS_UPDATE_RATE="$(python3 -c "print(int(round(1 / float('${PHYSICS_STEP_SIZE}'))))")"
sed -i "s|<max_step_size>.*</max_step_size>|<max_step_size>${PHYSICS_STEP_SIZE}</max_step_size>|" "${WORLD_RUNTIME}"
if grep -q '<real_time_update_rate>' "${WORLD_RUNTIME}"; then
  sed -i "s|<real_time_update_rate>.*</real_time_update_rate>|<real_time_update_rate>${PHYSICS_UPDATE_RATE}</real_time_update_rate>|" "${WORLD_RUNTIME}"
else
  sed -i "s|</real_time_factor>|</real_time_factor>\n      <real_time_update_rate>${PHYSICS_UPDATE_RATE}</real_time_update_rate>|" "${WORLD_RUNTIME}"
fi
sed -i "s|model://iris_with_ardupilot|model://${MODEL_PROFILE}|g" "${WORLD_RUNTIME}"
sed -i "s|model://iris_with_gimbal|model://${MODEL_PROFILE}|g" "${WORLD_RUNTIME}"
sed -i "s|model://iris_with_down_camera|model://${MODEL_PROFILE}|g" "${WORLD_RUNTIME}"

GZ_ARGS=(-v4 -r "${WORLD_RUNTIME}")
if [[ "${GZ_SERVER_ONLY}" == "true" ]]; then
  GZ_ARGS=(-v4 -s -r "${WORLD_RUNTIME}")
elif [[ "${GZ_HEADLESS}" == "true" ]]; then
  GZ_ARGS=(-v4 -r --headless-rendering "${WORLD_RUNTIME}")
fi

echo "Launching Gazebo (model=${MODEL_PROFILE}, server_only=${GZ_SERVER_ONLY}, headless=${GZ_HEADLESS}): ${WORLD_RUNTIME}"
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

echo "Waiting for Gazebo camera topic: ${CAMERA_GZ_IMAGE_TOPIC}"
if [[ "${HAS_CAMERA}" == "true" ]]; then
  camera_deadline=$((SECONDS + 60))
  while (( SECONDS < camera_deadline )); do
    if gz topic -l 2>/dev/null | grep -Fxq "${CAMERA_GZ_IMAGE_TOPIC}"; then
      echo "Gazebo camera topic is available."
      break
    fi
    sleep 2
  done
  if ! gz topic -l 2>/dev/null | grep -Fxq "${CAMERA_GZ_IMAGE_TOPIC}"; then
    echo "WARNING: Gazebo camera topic ${CAMERA_GZ_IMAGE_TOPIC} not found; starting bridge anyway."
  fi
else
  echo "Model ${MODEL_PROFILE} has no camera; skipping camera topic wait."
fi

echo "Starting ros_gz_bridge (RMW=${RMW_IMPLEMENTATION}) with config: ${BRIDGE_FILE}"
ros2 run ros_gz_bridge parameter_bridge --ros-args -p config_file:="${BRIDGE_FILE}" &
BRIDGE_PID=$!

sleep 3
if [[ "${HAS_CAMERA}" == "true" ]]; then
  if timeout 5 ros2 topic hz "/camera/rgb/image_raw" 2>/dev/null | grep -q "average rate"; then
    echo "ROS camera bridge OK: /camera/rgb/image_raw is publishing."
  else
    echo "WARNING: /camera/rgb/image_raw not publishing yet; check bridge config and Gazebo rendering."
  fi
fi

if [[ "${USE_GIMBAL_NADIR}" == "true" ]]; then
  apply_gimbal_nadir() {
    echo "Setting gimbal pitch to nadir (RC7=${GIMBAL_PITCH_NADIR_PWM}, ${GIMBAL_PITCH_NADIR_RAD} rad)."
    gz topic -t /gimbal/cmd_pitch -m gz.msgs.Double -p "data: ${GIMBAL_PITCH_NADIR_RAD}" || true
  }

  (
    sleep 10
    apply_gimbal_nadir
    if [[ "${CAMERA_PROFILE}" == "fixed-down" ]]; then
      exec python3 /workspace/scripts/set_gimbal_nadir.py tcp:127.0.0.1:5760 "${GIMBAL_PITCH_NADIR_PWM}" 0.5 0
    else
      python3 /workspace/scripts/set_gimbal_nadir.py tcp:127.0.0.1:5760 "${GIMBAL_PITCH_NADIR_PWM}" 0.5 15 &
    fi
  ) &
fi

trap 'kill ${BRIDGE_PID} ${SITL_PID} ${GZ_PID} 2>/dev/null || true' INT TERM EXIT
wait -n "${BRIDGE_PID}" "${SITL_PID}" "${GZ_PID}"
