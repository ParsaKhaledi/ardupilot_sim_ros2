# ardupilot_sim_gz
## Init:
```
# Allow docker to show gui of apps
xhost +local:docker 

```
### Using Compose file: 
```
cd ardupilot_sim_ros2
docker compose -f docker-compose.yaml up -d
```
### Using Manuall CMDs:
Simulation:
```
gz sim -v 4 -r ~/ardupilot_gazebo/worlds/iris_runway.sdf
```
-r: auto start
-s: run without gui 

Run Ardupilote:
```
~/ardupilot/build/sitl/bin/arducopter -S --model JSON --speedup 1 --defaults Tools/autotest/default_params/copter.parm,Tools/autotest/default_params/gazebo-iris.parm --sim-address=127.0.0.1 -I0
```
MavPROXY:
```
mavproxy.py --master=tcp:127.0.0.1:5760 --out=udp:127.0.0.1:14550 --map --console
```