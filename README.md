# ardupilot_sim_ros2

Dockerized ArduPilot + Gazebo Harmonic simulation with:
- iris quadrotor and downward camera support
- ROS 2 camera bridging via `ros_gz_bridge`
- optional MAVProxy GCS container
- selectable world/model/camera runtime profiles

## Prerequisites

```bash
xhost +local:docker
cp .env.example .env
```

## Launch

```bash
docker compose up --build -d
```

Add MAVProxy:

```bash
docker compose --profile gcs up --build -d
```

## Runtime profiles

Configure in `.env`:

- `CAMERA_PROFILE=gimbal|fixed-down`
- `MODEL_PROFILE=iris_with_gimbal`
- `WORLD_PROFILE=world-default|world-alt|world-aruco`
- `GZ_HEADLESS=true|false`
- `ENABLE_GST_STREAM=true|false`

World meanings:
- `world-default`: upstream `iris_runway.sdf`
- `world-alt`: upstream `iris_warehouse.sdf`
- `world-aruco`: local `worlds/iris_aruco_4tags.sdf`

## ROS 2 camera topics

Inside the container or sourced host:

```bash
ros2 topic list | rg camera
ros2 topic echo /camera/camera_info
```

## MAVProxy

If `gcs` profile is enabled:

```bash
mavproxy.py --master=tcp:127.0.0.1:5760 --out=udp:127.0.0.1:14550 --map --console
```

## Notes

- The ArUco world currently includes marker placeholders for precision-landing CV workflows.
- Replace placeholders with dictionary-accurate ArUco textures if strict detector matching is required.