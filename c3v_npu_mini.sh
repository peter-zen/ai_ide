#!/bin/bash

# Default image tag if not provided
TAG="0.0.1"

# Check if tag parameter is provided
if [ $# -eq 1 ]; then
    TAG=$1
fi

# Run docker container
docker run -it \
    --name c3v_npu_mini \
    --mac-address="22:F8:DF:09:99:B1" \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /dev/shm:/dev/shm \
    --device /dev/dri \
    --privileged \
    c3v_npu_mini:${TAG}
