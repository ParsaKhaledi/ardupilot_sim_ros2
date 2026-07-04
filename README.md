# ardupilot_sim_ros2

Dockerized ArduPilot + Gazebo Harmonic simulation with:
- Iris quadrotor and fixed down-facing camera (default) or optional 3-axis gimbal
- ROS 2 bridging via `ros_gz_bridge` (camera, IMU, odometry, TF, sensors)
- optional MAVProxy GCS + rqt camera viewer (`gcs` profile)
- selectable model, world, and camera runtime profiles

The `sim` service runs [`scripts/sim.sh`](scripts/sim.sh), which starts:
1. Gazebo (`gz sim`) with the selected world
2. ArduPilot SITL (`arducopter`)
3. ROS 2 `ros_gz_bridge` (Gazebo topics → ROS 2 transport)

## Repository layout

| Path | Purpose |
|------|---------|
| [`models/`](models/) | Gazebo models (Iris variants, runway, gimbals, ArUco pad, …) |
| [`worlds/`](worlds/) | Gazebo world SDF files |
| [`config/`](config/) | Bridge template, gimbal nadir params |
| [`scripts/`](scripts/) | Container entrypoints (`sim.sh`, `mavproxy.sh`, `rqt_image_view.sh`) |
| [`docker-compose.yaml`](docker-compose.yaml) | `sim` service + optional `gcs` profile (`mavproxy`, `rqt`) |

Compose bind-mounts `models/` and `worlds/` into `/workspace/` so you can edit SDF files on the host and restart sim without rebuilding the image.

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
DOCKER_IMAGE_TAG=42
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
- **rqt** — live `/camera/rgb/image_raw` viewer

## Runtime profiles

Set these in [`.env`](.env.example):

| Variable | Values | Effect |
|----------|--------|--------|
| `DOCKER_IMAGE` | `alienkh/ardupilot_sim_ros2` | Docker Hub repository |
| `DOCKER_IMAGE_TAG` | e.g. `latest`, `42` (GitHub run number) | Image tag to pull/run |
| `CAMERA_PROFILE` | `gimbal`, `fixed-down` | Gimbal-only: nadir preset and RC control (`iris_with_gimbal` only) |
| `WORLD_PROFILE` | `world-default`, `world-runway`, `world-alt`, `world-aruco` | World selection in `sim.sh` |
| `MODEL_PROFILE` | `iris_with_down_camera`, `iris_with_gimbal` | Drone model (default: fixed belly camera) |
| `GZ_HEADLESS` | `true`, `false` | Offscreen rendering (no GUI window, camera still works) |
| `GZ_SERVER_ONLY` | `true`, `false` | Gazebo server only (`-s`), best RTF |
| `ENABLE_GST_STREAM` | `true`, `false` | Enable GStreamer UDP H.264 on port 5600 |
| `SIM_SPEEDUP` | e.g. `1` | SITL speed multiplier |
| `PHYSICS_STEP_SIZE` | `0.002` (default), `0.001`, `0.003` | Gazebo physics step (seconds) |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | Required for ROS 2 across Docker containers (FastDDS SHM fails between containers) |
| `CAMERA_TOPIC` | `/camera/rgb/image_raw` | ROS 2 image topic for rqt viewer |
| `RQT_WAIT_SEC` | e.g. `120` | Seconds to wait for camera topic before rqt exits |

### World profiles (`WORLD_PROFILE`)

| Profile | World file | Description |
|---------|------------|-------------|
| `world-default` | `worlds/iris_simple.sdf` | Ground plane + iris, minimal |
| `world-runway` | `worlds/iris_runway.sdf` | Runway mesh (`models/runway`) |
| `world-alt` | upstream `iris_warehouse.sdf` | Warehouse scene (from `ardupilot_gazebo` clone in the image) |
| `world-aruco` | `worlds/iris_aruco_4tags.sdf` | Ground + 3×3 ArUco pad (DICT_5X5_1000, IDs 0–8) |

`sim.sh` patches the spawned model URI in the world file to match `MODEL_PROFILE`, so `world-aruco` works with either `iris_with_down_camera` or `iris_with_gimbal`.

### Camera model

Default model `iris_with_down_camera` lives at [`models/iris_with_down_camera/model.sdf`](models/iris_with_down_camera/model.sdf). Edit the **`CAMERA CONFIG`** block to change resolution, FOV, update rate, or mount pose — then restart sim (no image rebuild needed when using the compose volume mount).

```bash
docker compose up -d --force-recreate sim
```

For the legacy 3-axis gimbal:

```bash
MODEL_PROFILE=iris_with_gimbal
CAMERA_PROFILE=gimbal   # or fixed-down to lock nadir
docker compose up -d
```

Example — ArUco world with default down camera:

```bash
WORLD_PROFILE=world-aruco
docker compose up -d
```

With live camera viewer:

```bash
WORLD_PROFILE=world-aruco docker compose --profile gcs up -d
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
- Shadows are disabled in `iris_simple.sdf` and `iris_aruco_4tags.sdf`

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
| `/camera/rgb/image_raw` | `sensor_msgs/msg/Image` |
| `/camera/rgb/camera_info` | `sensor_msgs/msg/CameraInfo` |
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
ros2 topic hz /camera/rgb/image_raw
ros2 topic echo /imu --once
```

Bridge config is rendered at container start from [`config/bridge_template.yaml`](config/bridge_template.yaml) → `/tmp/ros_gz_bridge.yaml`. Verify the bridge in the sim container:

```bash
docker compose logs sim | grep ros_gz_bridge
docker exec ardupilot-sim bash -lc 'source /opt/ros/humble/setup.bash && ros2 topic hz /camera/rgb/image_raw'
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

## ArUco landing pad

The `aruco_pad` model (`models/aruco_pad/`) is a 1.85 m × 1.85 m board with a 3×3 grid of **DICT_5X5_1000** markers (IDs 0–8).

Marker textures:
- Place SVG files from [chev.me/arucogen](https://chev.me/arucogen/) in `models/aruco_pad/materials/textures/` as `5x5_1000-{id}.svg`
- Gazebo uses PNG textures (`5x5_1000-{id}.png`); regenerate PNGs after changing SVGs

## Notes

- `network_mode: host` is required for Gazebo ↔ SITL FDM and MAVLink.
- Gazebo models and worlds were consolidated from the former `gz_ardupilot/` tree into top-level `models/` and `worlds/`.
- `world-alt` (`iris_warehouse`) is still loaded from the `ardupilot_gazebo` clone baked into the Docker image.
- CI publishes `latest` and `<run_number>` (GitHub Actions build count) to Docker Hub when `Dockerfile` or the workflow changes on `main`.
