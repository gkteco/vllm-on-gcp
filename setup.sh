#!/bin/bash

# Exit on any error
set -e

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        error "gcloud is not installed. Please install the Google Cloud SDK."
    fi
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
}

# Enable required Google Cloud APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    apis=(
        "container.googleapis.com"
        "containerregistry.googleapis.com"
        "cloudbuild.googleapis.com"
        "secretmanager.googleapis.com"
        "sqladmin.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "firebase.googleapis.com"
        "identitytoolkit.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log "Enabling $api..."
        gcloud services enable $api
    done
}
# Create GKE cluster
create_cluster() {
    log "Creating GKE cluster: ${CLUSTER_NAME}..."
    
    if gcloud container clusters list --filter="name=${CLUSTER_NAME}" --format="get(name)" | grep -q "^${CLUSTER_NAME}$"; then
        warning "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
    else
        gcloud container clusters create ${CLUSTER_NAME} \
            --zone ${ZONE} \
            --num-nodes ${CPU_NUM_NODES} \
            --min-nodes ${CPU_MIN_NODES} \
            --max-nodes ${CPU_MAX_NODES} \
            --enable-autoscaling \
            --machine-type ${CPU_MACHINE_TYPE} \
            --enable-ip-alias \
            --workload-pool=${PROJECT_ID}.svc.id.goog \
            --enable-master-authorized-networks \
            --master-authorized-networks=0.0.0.0/0 \
            --enable-vertical-pod-autoscaling \
            --enable-autoprovisioning \
            --max-cpu ${CPU_MAX_CPU} \
            --max-memory ${CPU_MAX_MEMORY}
    fi
}

# Create GPU node pool
create_gpu_node_pool() {
    log "Setting up GPU node pool..."
        if gcloud container node-pools list \
        --cluster ${CLUSTER_NAME} \
        --filter="name=${GPU_NODE_POOL_NAME}" \
        --format="get(name)" | grep -q "^${GPU_NODE_POOL_NAME}$"; then
        warning "GPU node pool ${GPU_NODE_POOL_NAME} already exists. Skipping creation."
    else
        log "Creating GPU node pool..."
        gcloud container node-pools create ${GPU_NODE_POOL_NAME} \
            --cluster ${CLUSTER_NAME} \
            --zone ${ZONE} \
            --machine-type ${GPU_MACHINE_TYPE} \
            --num-nodes ${GPU_NUM_NODES} \
            --min-nodes ${GPU_MIN_NODES} \
            --max-nodes ${GPU_MAX_NODES} \
            --enable-autoscaling \
            --accelerator type=${GPU_ACCELERATOR_TYPE},count=${GPU_ACCELERATOR_COUNT},gpu-driver-version=${GPU_ACCELERATOR_GPU_DRIVER_VERSION} \
            --node-taints="nvidia.com/gpu=present:NoSchedule"

        gcloud container clusters update ${CLUSTER_NAME} \
            --enable-autoprovisioning \
            --max-cpu ${GPU_MAX_CPU} \
            --max-memory ${GPU_MAX_MEMORY} \
            --min-accelerator type=${GPU_ACCELERATOR_TYPE},count=${GPU_MIN_ACCELERATOR} \
            --max-accelerator type=${GPU_ACCELERATOR_TYPE},count=${GPU_MAX_ACCELERATOR}
    fi

}

# Setup network policies and firewall rules
setup_network() {
    log "Setting up network policies and firewall rules..."
    
    # Create firewall rules
    gcloud compute firewall-rules create gke-${CLUSTER_NAME}-allow-internal \
        --network default \
        --allow tcp,udp,icmp \
        --source-ranges 10.0.0.0/8 \
        --description="Allow internal communication for GKE cluster ${CLUSTER_NAME}" \
        --direction INGRESS \
        --priority 1000 \
        --target-tags gke-${CLUSTER_NAME}

    gcloud compute firewall-rules create gke-${CLUSTER_NAME}-allow-health-checks \
        --network default \
        --allow tcp:8080 \
        --source-ranges 35.191.0.0/16,130.211.0.0/22 \
        --description="Allow health checks for GKE cluster ${CLUSTER_NAME}" \
        --direction INGRESS \
        --priority 1000 \
        --target-tags gke-${CLUSTER_NAME}
}

# Get cluster credentials
get_credentials() {
    log "Getting cluster credentials..."
    gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}

}

create_secrets() {
    log "Creating secrets..."
    kubectl create secret generic hf-token \
        --from-env-file=.env.secrets \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Setup service accounts and IAM roles
setup_service_accounts() {
    log "Setting up service accounts and IAM roles..."
    
    # Create GCP service account if it doesn't exist
    if ! gcloud iam service-accounts list --filter="email=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --format="get(email)" | grep -q "^${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com$"; then
        gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
            --display-name="GKE Backend Service Account"
    fi

    # Grant necessary roles
    roles=(
        "roles/secretmanager.secretAccessor"
        "roles/cloudsql.client"
        "roles/cloudsql.instanceUser"
        "roles/firebase.admin"
    )

    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}"
    done

    # Create Kubernetes service account
    kubectl create serviceaccount ${KSA_NAME} -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Setup workload identity
    gcloud iam service-accounts add-iam-policy-binding \
        ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role roles/iam.workloadIdentityUser \
        --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]"

    # Annotate the Kubernetes service account
    kubectl annotate serviceaccount \
        ${KSA_NAME} \
        iam.gke.io/gcp-service-account=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
        --overwrite \
        -n ${K8S_NAMESPACE}
}

setup_cloud_build_permissions() {
    log "Setting up Cloud Build permissions..."
    
    # Get the Cloud Build service account
    CLOUDBUILD_SA="$(gcloud projects describe $PROJECT_ID --format 'value(projectNumber)')@cloudbuild.gserviceaccount.com"
    
    # Grant necessary roles to Cloud Build service account
    roles=(
        "roles/container.developer"
        "roles/iam.serviceAccountUser"
        "roles/container.admin"
        "roles/secretmanager.secretAccessor"
    )

    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${CLOUDBUILD_SA}" \
            --role="${role}"
    done
}

apply_k8s_manifests() {
    log "Applying Kubernetes manifests..."
    kubectl apply -f k8s/
}

print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --all       Run all commands"
    echo "  -c, --create    Create GCP resources"
    echo "  -k, --k8s       Apply Kubernetes resources"
    echo "  -s, --secrets   Create secrets"
    echo "  -h, --help      Print usage"
}

# Main execution
main() {

    if [ $# -eq 0 ]; then
        echo "No command provided. Need at least one command to run. -a, --all to run all commands."
        print_usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                check_prerequisites
                configure_gcloud
                enable_apis
                create_cluster
                create_gpu_node_pool
                setup_network
                get_credentials
                create_secrets
                setup_service_accounts
                setup_cloud_build_permissions
                apply_k8s_manifests

                log "GCP setup completed successfully!"
                shift
                ;;
            -c|--create)
                check_prerequisites
                configure_gcloud
                enable_apis
                create_cluster
                create_gpu_node_pool
                setup_network
                get_credentials

                log "GCP resources created successfully!"
                shift
                ;;
            -k|--k8s)
                apply_k8s_manifests

                log "Kubernetes resources applied successfully!"
                shift
                ;;
            -s|--secrets)
                create_secrets

                log "Secrets created successfully!"
                shift
                ;;
            -h|--help)
                print_usage
                shift
                ;;
            *)
                error "Invalid option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# Run main function
main "$@"
