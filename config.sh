#!/bin/bash

# Project Configuration
export PROJECT_ID="eigenvalue-dev"
export REGION="us-central1"
export ZONE="us-central1-a"

# Cluster Configuration
export CLUSTER_NAME="eigenvalue-cluster"
export CPU_MACHINE_TYPE="e2-standard-8"
export CPU_NODE_POOL_NAME="cpu-pool"
export GPU_MACHINE_TYPE="g2-standard-16"
export GPU_NODE_POOL_NAME="gpu-pool"

export CPU_NUM_NODES=1
export CPU_MIN_NODES=1
export CPU_MAX_NODES=5
export CPU_MAX_CPU=32
export CPU_MAX_MEMORY=128

export GPU_NUM_NODES=1
export GPU_MIN_NODES=1
export GPU_MAX_NODES=1
export GPU_ACCELERATOR_TYPE="nvidia-l4"
export GPU_ACCELERATOR_COUNT=1
export GPU_ACCELERATOR_GPU_DRIVER_VERSION="latest"
export GPU_MAX_CPU=16
export GPU_MAX_MEMORY=64
export GPU_MIN_ACCELERATOR=0
export GPU_MAX_ACCELERATOR=1

# DEV Cluster Configuration
export DEV_CLUSTER_NAME="eigenvalue-dev-cluster"
export DEV_CPU_MACHINE_TYPE="e2-standard-8"
export DEV_CPU_NODE_POOL_NAME="cpu-pool"
export DEV_GPU_MACHINE_TYPE="g2-standard-16"
export DEV_GPU_NODE_POOL_NAME="gpu-pool"

export DEV_CPU_NUM_NODES=1
export DEV_CPU_MIN_NODES=1
export DEV_CPU_MAX_NODES=5
export DEV_CPU_MAX_CPU=32
export DEV_CPU_MAX_MEMORY=128

export DEV_GPU_NUM_NODES=1
export DEV_GPU_MIN_NODES=1
export DEV_GPU_MAX_NODES=1
export DEV_GPU_ACCELERATOR_TYPE="nvidia-l4"
export DEV_GPU_ACCELERATOR_COUNT=1
export DEV_GPU_ACCELERATOR_GPU_DRIVER_VERSION="latest"
export DEV_GPU_MAX_CPU=16
export DEV_GPU_MAX_MEMORY=64
export DEV_GPU_MIN_ACCELERATOR=0
export DEV_GPU_MAX_ACCELERATOR=1

# Kubernetes Configuration
export K8S_NAMESPACE="default"
export SERVICE_ACCOUNT_NAME="gke-backend-sa"
export KSA_NAME="gke-backend-ksa"

# Output Colors
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# Shared logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S%z')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%dT%H:%M:%S%z')] WARNING: $1${NC}"
} 