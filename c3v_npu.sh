#!/bin/bash

# Default image tag if not provided
TAG="latest"
MODEL_PATH=""
FORCE=false
IP_ADDR=""

# Function to get network configuration
get_network_config() {
    # If IP_ADDR is provided, use it to derive network configuration
    if [ -n "$IP_ADDR" ]; then
        # Use the provided IP to determine network
        SUBNET_MASK="24"  # Default to /24 subnet
        NETWORK_ADDR=$(ipcalc -n "$IP_ADDR/$SUBNET_MASK" | grep Network | awk '{print $2}')
        GATEWAY=$(echo "$IP_ADDR" | awk -F. '{print $1"."$2"."$3".1"}')
        DEFAULT_IFACE=$(ip route | grep "$NETWORK_ADDR" | awk '{print $3}' | head -n1)
    else
        # Original method to get default route interface
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
    fi

    # Export variables for use by other functions
    export DEFAULT_IFACE
    export NETWORK_ADDR
    export GATEWAY
    export IP_ADDR
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

        # Determine subnet and IP range based on provided or detected IP
        SUBNET="${NETWORK_ADDR%.*}.0/24"
        IP_RANGE="${NETWORK_ADDR%.*}.0/24"

        docker network create -d ipvlan \
            --subnet=$SUBNET \
            --ip-range=$IP_RANGE \
            --gateway=$GATEWAY \
            -o ipvlan_mode=l2 \
            -o parent=$DEFAULT_IFACE \
            c3v_network
    else
        echo "c3v_network already exists"
    fi
}

# Dynamic NFS export management
DYNAMIC_NFS_EXPORTS_FILE="/etc/exports.d/dynamic_model_path.exports"

# Function to manage NFS exports for model path
manage_nfs_export() {
    local model_path="$1"
    
    # Ensure the directory exists
    if [ ! -d "$model_path" ]; then
        echo "Error: Model path '$model_path' does not exist"
        return 1
    fi
    
    # Create the exports.d directory if it doesn't exist
    mkdir -p /etc/exports.d
    
    # Create a new dynamic exports file
    echo "# Dynamic NFS export for model path" > "$DYNAMIC_NFS_EXPORTS_FILE"
    
    # Get network configuration (use the function defined earlier)
    get_network_config
    
    # Add export entry with read-write access to the network
    if [ -n "$NETWORK_ADDR" ]; then
        # Open read-write access to entire network
        echo "$model_path $NETWORK_ADDR(rw,sync,no_subtree_check,no_root_squash)" >> "$DYNAMIC_NFS_EXPORTS_FILE"
        
        # Ensure broad write permissions
        chmod 777 "$model_path"
        
        # Reload NFS exports (use -a flag to reload all exports)
        if command -v exportfs &> /dev/null; then
            exportfs -ra
            echo "NFS export created for $model_path on network $NETWORK_ADDR with full read-write access"
        else
            echo "Warning: exportfs command not found. NFS exports may not be updated." >&2
            return 1
        fi
    else
        echo "Warning: Could not determine network for NFS export" >&2
        return 1
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
    # Attempt to set up NFS export
    if ! manage_nfs_export "$MODEL_PATH"; then
        echo "Warning: Failed to set up NFS export for model path" >&2
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
