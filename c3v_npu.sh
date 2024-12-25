#!/bin/bash

# Default image tag if not provided
TAG="latest"
MODEL_PATH=""
FORCE=false

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
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [-t|--tag <tag>] [-m|--model-path <path>] [-f|--force]"
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
    VOLUME_MOUNT="-v $MODEL_PATH:/home/c3v/model_converter/models/${MODEL_PATH##*/}"
    echo "VOLUME_MOUNT=$VOLUME_MOUNT"
fi

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^c3v_npu$"; then
    if [ "$FORCE" = true ]; then
        echo "Force flag set. Removing existing container..."
        docker rm -f c3v_npu
    else
        if docker ps --format '{{.Names}}' | grep -q "^c3v_npu$"; then
            echo "Container c3v_npu is already running. Executing bash in the container..."
            exec docker exec -it c3v_npu bash
        else
            echo "Container c3v_npu exists but is not running. Starting and attaching..."
            exec docker start -i c3v_npu
        fi
        exit 0
    fi
fi

# Run docker container
echo "Starting new container..."
docker run -it \
    --name c3v_npu \
    --privileged \
    $VOLUME_MOUNT \
    zengping2024/c3v_npu:${TAG}
