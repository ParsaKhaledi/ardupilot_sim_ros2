# ardupilot_sim_gz
Simulation:
```
gz sim -v 4 -r ~/ardupilot_gazebo/worlds/iris_runway.sdf
```
Run Ardupilote:
```
~/ardupilot/build/sitl/bin/arducopter -S --model JSON --speedup 1 --defaults Tools/autotest/default_params/copter.parm,Tools/autotest/default_params/gazebo-iris.parm --sim-address=127.0.0.1 -I0
```
MavPROXY:
```
mavproxy.py --master=tcp:127.0.0.1:5760 --out=udp:127.0.0.1:14550 --map --console
```