#!/bin/bash

# Default image tag if not provided
TAG="0.0.1"
MODEL_PATH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -m|--model-path)
            MODEL_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [-t|--tag <tag>] [-m|--model-path <path>]"
            exit 1
            ;;
    esac
done

# Prepare volume mount option
VOLUME_MOUNT=""
if [ ! -z "$MODEL_PATH" ]; then
    if [ ! -d "$MODEL_PATH" ]; then
        echo "Error: Model path '$MODEL_PATH' does not exist or is not a directory"
        exit 1
    fi
    VOLUME_MOUNT="-v $MODEL_PATH:/npu/model_convert"
fi

# Run docker container
docker run -it \
    --name c3v_npu_mini_test \
    --mac-address="22:F8:DF:09:99:B1" \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /dev/shm:/dev/shm \
    --device /dev/dri \
    --privileged \
    $VOLUME_MOUNT \
    c3v_npu_mini:${TAG}

