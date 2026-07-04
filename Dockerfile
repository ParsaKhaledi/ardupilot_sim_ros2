ARG ROS_DISTRO=humble
FROM ros:${ROS_DISTRO}-perception

SHELL ["/bin/bash", "-c"]

ARG USER_NAME=ardupilot
ARG USER_UID=1000
ARG USER_GID=1000
ARG ARDUPILOT_VERSION=Copter-4.6.3
ARG ARDUPILOT_GAZEBO_BRANCH=ros2
ARG GZ_VERSION=harmonic

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV QT_X11_NO_MITSHM=1
ENV ROS_DISTRO=${ROS_DISTRO}
ENV GZ_VERSION=${GZ_VERSION}
ENV WORKDIR=/home/${USER_NAME}

WORKDIR /home

RUN apt update && apt upgrade -y && apt install -y --no-install-recommends \
    bash-completion \
    build-essential \
    cmake \
    curl \
    gettext-base \
    git \
    gnupg2 \
    gstreamer1.0-gl \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-bad \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer1.0-dev \
    libopencv-dev \
    lsb-release \
    python3 \
    python3-argcomplete \
    python3-colcon-common-extensions \
    python3-pip \
    python3-rosdep \
    python3-vcstool \
    rapidjson-dev \
    ros-dev-tools \
    software-properties-common \
    sudo \
    tmux \
    udev \
    unzip \
    wget \
    xauth \
    xorg && \
    wget https://packages.osrfoundation.org/gazebo.gpg -O /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null && \
    apt update && apt install -y --no-install-recommends \
    gz-harmonic \
    libgz-sim8-dev \
    ros-${ROS_DISTRO}-desktop \
    ros-${ROS_DISTRO}-geographic-msgs \
    ros-${ROS_DISTRO}-ros-gzharmonic \
    ros-${ROS_DISTRO}-rqt-image-view \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd ${USER_NAME} --gid ${USER_GID} && \
    useradd -l -m ${USER_NAME} -u ${USER_UID} -g ${USER_GID} -s /bin/bash && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME} && \
    chmod 0440 /etc/sudoers.d/${USER_NAME} && \
    usermod -a -G dialout ${USER_NAME}

USER ${USER_NAME}
WORKDIR ${WORKDIR}

RUN python3 -m pip install --upgrade pip setuptools && \
    python3 -m pip install --upgrade pymavlink MAVProxy

RUN sudo wget https://raw.githubusercontent.com/osrf/osrf-rosdep/master/gz/00-gazebo.list -O /etc/ros/rosdep/sources.list.d/00-gazebo.list && \
    rosdep init || true && \
    rosdep update

RUN git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git -b ${ARDUPILOT_VERSION} && \
    cd ardupilot && \
    sed -i '/sudo usermod -a -G dialout $USER/d' Tools/environment_install/install-prereqs-ubuntu.sh && \
    Tools/environment_install/install-prereqs-ubuntu.sh -y && \
    . ~/.profile && \
    ./waf configure --board sitl && \
    ./waf copter

RUN git clone https://github.com/ArduPilot/ardupilot_gazebo.git -b ${ARDUPILOT_GAZEBO_BRANCH} && \
    cd ardupilot_gazebo && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo && \
    make -j"$(nproc)" && \
    sudo make install

RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc && \
    echo "export GZ_VERSION=${GZ_VERSION}" >> ~/.bashrc && \
    echo "export GZ_SIM_SYSTEM_PLUGIN_PATH=/home/${USER_NAME}/ardupilot_gazebo/build:\${GZ_SIM_SYSTEM_PLUGIN_PATH}" >> ~/.bashrc && \
    echo "export GZ_SIM_RESOURCE_PATH=/workspace/models:/workspace/worlds:/home/${USER_NAME}/ardupilot_gazebo/models:/home/${USER_NAME}/ardupilot_gazebo/worlds:\${GZ_SIM_RESOURCE_PATH}" >> ~/.bashrc

USER root
RUN mkdir -p /workspace/models /workspace/worlds
COPY models/ /workspace/models/
COPY worlds/ /workspace/worlds/
RUN chown -R ${USER_NAME}:${USER_NAME} /workspace

USER ${USER_NAME}

ENV GZ_SIM_SYSTEM_PLUGIN_PATH=/home/${USER_NAME}/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH}
ENV GZ_SIM_RESOURCE_PATH=/workspace/models:/workspace/worlds:/home/${USER_NAME}/ardupilot_gazebo/models:/home/${USER_NAME}/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH}

ENTRYPOINT ["/bin/bash", "-lc"]
