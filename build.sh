#!/bin/bash

# Default image tag if not provided
TAG="latest"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: $0 [-t|--tag <tag>]"
            exit 1
            ;;
    esac
done

echo "Building c3v_npu:${TAG} from Dockerfile.no_ide..."
docker build -t c3v_npu:${TAG} -f Dockerfile.no_ide .
