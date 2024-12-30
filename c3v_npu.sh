#!/bin/bash

# Default image tag if not provided
TAG="latest"
MODEL_PATH=""
FORCE=false
IP_ADDR=""

# Function to get network configuration
get_network_config() {
    # Get default route interface
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$DEFAULT_IFACE" ]; then
        echo "Error: Could not determine default network interface" >&2
        exit 1
    fi

    # Get IP and subnet
    IP_INFO=$(ip -f inet addr show $DEFAULT_IFACE | grep inet)
    if [ -z "$IP_INFO" ]; then
        echo "Error: Could not get IP information for interface $DEFAULT_IFACE" >&2
        exit 1
    fi

    # Extract network information
    IP_ADDR=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f1)
    SUBNET_MASK=$(echo "$IP_INFO" | awk '{print $2}' | cut -d/ -f2)
    NETWORK_ADDR=$(ipcalc -n "$IP_ADDR/$SUBNET_MASK" | grep Network | awk '{print $2}')
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

    # Export variables for use by other functions
    export DEFAULT_IFACE
    export NETWORK_ADDR
    export GATEWAY
}

# Function to check and create IPvlan network
check_create_network() {
    if ! docker network ls | grep -q "c3v_network"; then
        echo "Creating c3v_network (IPvlan)..."
        # Get network configuration
        get_network_config
        if [ -z "$NETWORK_ADDR" ] || [ -z "$GATEWAY" ] || [ -z "$DEFAULT_IFACE" ]; then
            echo "Error: Could not determine network configuration" >&2
            exit 1
        fi

        docker network create -d ipvlan \
            --subnet=$NETWORK_ADDR \
            --gateway=$GATEWAY \
            -o ipvlan_mode=l2 \
            -o parent=$DEFAULT_IFACE \
            c3v_network
    else
        echo "c3v_network already exists"
    fi
}

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
        --ip)
            IP_ADDR="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [-t|--tag <tag>] [-m|--model-path <path>] [-f|--force] [--ip <ip-address>]"
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

# Check and create network if needed
check_create_network

# Run docker container
echo "Starting new container..."
docker run -it \
    --name c3v_npu \
    --privileged \
    --network c3v_network \
    ${IP_ADDR:+--ip $IP_ADDR} \
    $VOLUME_MOUNT \
    c3v_npu:${TAG}
