# ardupilot_sim_ros2

Dockerized ArduPilot + Gazebo Harmonic simulation with:
- Iris quadrotor and camera (gimbal or downward preset)
- ROS 2 bridging via `ros_gz_bridge` (camera, IMU, odometry, TF, sensors)
- optional MAVProxy GCS + rqt camera viewer (`gcs` profile)
- selectable world/camera runtime profiles

The `sim` service runs [`scripts/sim.sh`](scripts/sim.sh), which starts:
1. Gazebo (`gz sim`) with the selected world
2. ArduPilot SITL (`arducopter`)
3. ROS 2 `ros_gz_bridge` (Gazebo topics → ROS 2 transport)

## Prerequisites

Allow Docker GUI apps and create X11 auth file:

```bash
xhost +local:docker
touch /tmp/.docker.xauth
xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f /tmp/.docker.xauth nmerge -
cp .env.example .env
```

## Startup (published image from CI)

Use the image from [Docker Hub](https://hub.docker.com/r/alienkh/ardupilot_sim_ros2):

```bash
cp .env.example .env
docker compose pull
docker compose up -d
```

Pin a specific tag in `.env`:

```bash
DOCKER_IMAGE=alienkh/ardupilot_sim_ros2
DOCKER_IMAGE_TAG=legacy_79
```

Then:

```bash
docker compose pull
docker compose up -d
```

## Startup (build locally)

```bash
docker compose up --build -d
```

## Startup with MAVProxy GCS and camera viewer

MAVProxy and `rqt_image_view` run together under the `gcs` profile:

```bash
docker compose --profile gcs up -d
```

This starts:
- **mavproxy** — flight control console/map
- **rqt** — live `/camera/image` viewer

## Runtime profiles

Set these in [`.env`](.env.example):

| Variable | Values | Effect |
|----------|--------|--------|
| `DOCKER_IMAGE` | `alienkh/ardupilot_sim_ros2` | Docker Hub repository |
| `DOCKER_IMAGE_TAG` | e.g. `latest`, `legacy_79` | Image tag to pull/run |
| `CAMERA_PROFILE` | `gimbal`, `fixed-down` | Gimbal camera vs nadir preset (RC7 via MAVProxy) |
| `WORLD_PROFILE` | `world-default`, `world-runway`, `world-alt`, `world-aruco` | World selection in `sim.sh` |
| `MODEL_PROFILE` | `iris_with_gimbal` | Reserved (model comes from upstream world SDF) |
| `GZ_HEADLESS` | `true`, `false` | Offscreen rendering (no GUI window, camera still works) |
| `GZ_SERVER_ONLY` | `true`, `false` | Gazebo server only (`-s`), best RTF |
| `ENABLE_GST_STREAM` | `true`, `false` | Enable GStreamer UDP H.264 on port 5600 |
| `SIM_SPEEDUP` | e.g. `1` | SITL speed multiplier |
| `PHYSICS_STEP_SIZE` | `0.002` (default), `0.001`, `0.003` | Gazebo physics step (seconds) |
| `CAMERA_TOPIC` | `/camera/image` | ROS 2 image topic for rqt viewer |
| `RQT_WAIT_SEC` | e.g. `120` | Seconds to wait for camera topic before rqt exits |

World profiles (`WORLD_PROFILE`):
- `world-default` → local `worlds/iris_simple.sdf` (ground plane + iris, minimal)
- `world-runway` → upstream `iris_runway.sdf` (runway mesh)
- `world-alt` → upstream `iris_warehouse.sdf`
- `world-aruco` → local `worlds/iris_aruco_4tags.sdf` (4 ground markers for CV/landing tests)

Example — downward camera on ArUco world:

```bash
CAMERA_PROFILE=fixed-down
WORLD_PROFILE=world-aruco
docker compose up -d
```

## Performance / real-time factor (RTF)

RTF is how fast simulation runs vs wall clock (`1.0` = real-time). At `PHYSICS_STEP_SIZE=0.001` you need **1000 physics steps per simulated second**, which is heavy with GUI + camera + Iris plugins — ~50% RTF is common.

| Setting | Effect on RTF | Stability |
|---------|---------------|-----------|
| `PHYSICS_STEP_SIZE=0.001` | Slowest (~50% typical) | Most stable |
| `PHYSICS_STEP_SIZE=0.002` | **Default** — ~2× faster physics | Usually stable for Iris |
| `PHYSICS_STEP_SIZE=0.003` | Faster | May need testing |
| `PHYSICS_STEP_SIZE=0.01` | Fast but **ODE crash risk** | Unstable |

To push RTF toward 100% without going to `0.01`:

```bash
# Best RTF while keeping camera (no Gazebo GUI window)
PHYSICS_STEP_SIZE=0.002
GZ_SERVER_ONLY=true
docker compose up -d
```

Other tips:
- Ensure GPU/OpenGL acceleration (not software rendering)
- Use `world-default` (`iris_simple`) instead of `world-runway` / `world-alt`
- Disable shadows already done in `iris_simple.sdf`

## Useful commands

```bash
docker compose ps
docker compose logs -f sim
docker compose logs -f mavproxy
docker compose down
```

## ROS 2 topics (Gazebo → ROS 2)

Bridged by [`config/bridge_template.yaml`](config/bridge_template.yaml) (rendered at runtime by `sim.sh`):

| ROS 2 topic | Message type |
|-------------|--------------|
| `/clock` | `rosgraph_msgs/msg/Clock` |
| `/joint_states` | `sensor_msgs/msg/JointState` |
| `/odometry` | `nav_msgs/msg/Odometry` |
| `/gz/tf` | `tf2_msgs/msg/TFMessage` |
| `/gz/tf_static` | `tf2_msgs/msg/TFMessage` |
| `/camera/image` | `sensor_msgs/msg/Image` |
| `/camera/camera_info` | `sensor_msgs/msg/CameraInfo` |
| `/imu` | `sensor_msgs/msg/Imu` |
| `/magnetometer` | `sensor_msgs/msg/MagneticField` |
| `/navsat` | `sensor_msgs/msg/NavSatFix` |
| `/air_pressure` | `sensor_msgs/msg/FluidPressure` |
| `/battery` | `sensor_msgs/msg/BatteryState` |

Exec into the running sim container:

```bash
docker exec -it ardupilot-sim bash
source /opt/ros/humble/setup.bash
ros2 topic list
ros2 topic hz /camera/image
ros2 topic echo /imu --once
```

On the host (with `network_mode: host`), topics are also visible if ROS 2 is sourced locally.

## MAVProxy

When `--profile gcs` is used, MAVProxy and rqt start automatically via [`scripts/mavproxy.sh`](scripts/mavproxy.sh) and [`scripts/rqt_image_view.sh`](scripts/rqt_image_view.sh).

```text
tcp:127.0.0.1:5760  →  udp:127.0.0.1:14550
```

Manual example inside container:

```bash
mavproxy.py --master=tcp:127.0.0.1:5760 --out=udp:127.0.0.1:14550 --map --console
```

Typical flight test:

```text
mode guided
arm throttle
takeoff 5
```

## Notes

- `network_mode: host` is required for Gazebo ↔ SITL FDM and MAVLink.
- The ArUco world uses high-contrast ground marker placeholders; replace with dictionary-accurate ArUco textures for strict OpenCV detection.
- CI publishes tags like `latest`, `<branch>_<run>`, and `legacy_<run>` to Docker Hub.
