#!/bin/bash

echo "++++++++INIT++++++++++"

source /simulation/inputs/parameters/swarm.sh
source /opt/ros/kinetic/setup.bash
source ~/catkin_ws/devel/setup.bash

## world setup #
cp /simulation/inputs/models/empty.world /root/src/Firmware/Tools/sitl_gazebo/worlds/empty.world
cp /simulation/inputs/models/f450-1/f450-1.sdf /root/src/Firmware/Tools/sitl_gazebo/models/f450-1/f450-1.sdf
cp /simulation/inputs/utils/posix_sitl_openuav_swarm_base.launch /root/src/Firmware/launch/posix_sitl_openuav_swarm_base.launch

rm -r /simulation/outputs
mkdir -p /simulation/outputs 
echo "Setup..." >> /tmp/debug

python /simulation/inputs/utils/gen_gazebo_ros_spawn.py $num_uavs
python /simulation/inputs/utils/gen_px4_sitl.py $num_uavs
python /simulation/inputs/utils/gen_mavros.py $num_uavs

# PAR LIBRARY
echo "PAR Library" >> /tmp/debug
P=`pwd`
mkdir -p ~/catkin_ws/src
cd ~/catkin_ws/src
git clone https://github.com/pennaerial/pennair2.git
cd ~/catkin_ws
catkin build pennair2
source ~/catkin_ws/devel/setup.bash
cd "$P"
echo "END PAR LIBRARY" >> /tmp/debug
# END PAR LIBRARY

# Prep the quads
for((i=1;i<=$num_uavs;i+=1))
do
echo "px4 posix_sitl_multi_gazebo_ros$num_uavs.launch"
    echo "launching uav$i ..." >> /tmp/debug
    roslaunch px4 posix_sitl_multi_gazebo_ros$i.launch &> /dev/null &
    until rostopic echo /gazebo/model_states | grep -m1 f450-tmp-$i ; do : ; done
    roslaunch px4 posix_sitl_multi_px4_sitl$i.launch &> /dev/null &
    sleep 2
    roslaunch px4 posix_sitl_multi_mavros$i.launch &> /dev/null &
    until rostopic echo /mavros$i/state | grep -m1 "connected: True" ; do : ; done
    echo "launched uav$i ..." >> /tmp/debug

done

# Start server viewers
rosrun web_video_server web_video_server _port:=80 _server_threads:=100 &> /dev/null &
roslaunch rosbridge_server rosbridge_websocket.launch ssl:=false &> /dev/null &

python /simulation/inputs/utils/testArmAll.py $num_uavs &> /dev/null &

sleep 3

for((i=1;i<$num_uavs;i+=1))
do
    one=1
    python /simulation/takeoff.py &> /tmp/debug &
    sleep 1
done

echo "Measures..."
python /simulation/inputs/utils/measureInterRobotDistance.py $num_uavs 1 &> /dev/null &
roslaunch opencv_apps general_contours.launch  image:=/uav_2_camera_front/image_raw debug_view:=false &> /dev/null &

for((i=1;i<=$num_uavs;i+=1))
do
        /usr/bin/python -u /opt/ros/kinetic/bin/rostopic echo -p /mavros$i/local_position/odom > /simulation/outputs/uav$i.csv &
    done
    /usr/bin/python -u /opt/ros/kinetic/bin/rostopic echo -p /measure > /simulation/outputs/measure.csv &

    # Wait until end of session before closing the container
    sleep $duration_seconds
    cat /simulation/outputs/measure.csv | awk -F',' '{sum+=$2; ++n} END { print sum/n }' > /simulation/outputs/average_measure.txt

