#!/bin/bash

# ==============================================================================
# Knative/Minikube Cluster Management Script for macOS (Functional Version)
#
# This script provides a reliable, structured way to start and destroy a
# Knative development environment using Minikube with the Docker driver.
#
# Usage:
#   ./manage-knative-cluster.sh start      - Creates the cluster and installs Knative.
#   ./manage-knative-cluster.sh destroy    - Stops the tunnel and deletes the cluster.
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CLUSTER_PROFILE="knative-demo"
TUNNEL_PID_FILE="/tmp/minikube_${CLUSTER_PROFILE}_tunnel.pid"

# Pin versions for a stable, repeatable environment.
KNATIVE_VERSION="v1.18.0"
KUBERNETES_VERSION="v1.32.6"

# ==============================================================================
# --- Helper Functions ---
# ==============================================================================

function check_prerequisites() {
    echo "--- 1. Checking prerequisites ---"
    local has_error=0
    for cmd in minikube kubectl docker; do
        if ! command -v $cmd &> /dev/null; then
            echo "❌ Error: Command '$cmd' not found. Please install it."
            has_error=1
        fi
    done
    if [ "$has_error" -eq 1 ]; then
        exit 1
    fi
    echo "✅ All prerequisites are installed."
}

function start_cluster() {
    echo "--- 2. Starting Minikube Cluster (${CLUSTER_PROFILE}) ---"
    minikube start \
      --profile "${CLUSTER_PROFILE}" \
      --driver=docker \
      --cpus=4 \
      --memory=7g \
      --kubernetes-version=${KUBERNETES_VERSION}

    minikube profile "${CLUSTER_PROFILE}"
    echo "--- 3. Waiting for Kubernetes API server to be ready ---"
    kubectl wait --for=condition=Available=True deployment/coredns -n kube-system --timeout=300s
}

function start_tunnel() {
    echo "--- 4. Starting Minikube Tunnel in the background ---"
    stop_tunnel # Ensure no old tunnels are running before starting a new one.

    echo "🔑 You may be prompted for your sudo password to start the network tunnel."
    minikube tunnel --profile "${CLUSTER_PROFILE}" > /tmp/minikube_tunnel.log 2>&1 &

    echo "   Waiting for the tunnel daemon to initialize..."
    sleep 5

    local TUNNEL_PID=$(pgrep -f "minikube tunnel --profile ${CLUSTER_PROFILE}")

    if [ -z "$TUNNEL_PID" ]; then
        echo "❌ ERROR: Failed to start or find the minikube tunnel process!"
        echo "   Check logs for errors: cat /tmp/minikube_tunnel.log"
        exit 1
    fi

    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"
    echo "🚀 Tunnel daemon is running with PID $(cat $TUNNEL_PID_FILE)."
    sleep 5 # Give tunnel a moment to establish routes.
}

function install_knative() {
    echo "--- 5. Installing Knative components ---"
    echo "   - Installing Knative Serving (v${KNATIVE_VERSION})..."
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml

    echo "   - Installing Kourier networking layer..."
    kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml

    echo "   - Configuring Knative Serving to use Kourier..."
    kubectl patch configmap/config-network \
      --namespace knative-serving \
      --type merge \
      --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

    echo "   - Installing Knative Eventing (v${KNATIVE_VERSION})..."
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml
    kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml
}

function verify_installation() {
    echo "--- 6. Waiting for all Knative deployments to be ready ---"
    kubectl wait --for=condition=Available=True deployment --all -n knative-serving --timeout=300s
    kubectl wait --for=condition=Available=True deployment --all -n knative-eventing --timeout=300s
    kubectl wait --for=condition=Available=True deployment --all -n kourier-system --timeout=300s

    echo "--- 7. Verifying network setup ---"
    local EXTERNAL_IP=$(kubectl get svc/kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo "not-found")
    if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" == "not-found" ]; then
       echo "❌ ERROR: Kourier service did not get an External IP from the tunnel."
       exit 1
    fi

    configure_domain

    echo ""
    echo "✅✅✅ --- Cluster is READY! --- ✅✅✅"
    echo ""
    echo "   Minikube Profile:   ${CLUSTER_PROFILE}"
    echo "   Knative Version:    ${KNATIVE_VERSION}"
    echo "   Kubernetes Version: ${KUBERNETES_VERSION}"
    echo "   Kourier IP Address: ${EXTERNAL_IP}"
    echo "   Tunnel PID:         $(cat $TUNNEL_PID_FILE) (running in background)"
    echo ""
    echo "Tip: To enable easy browser access, configure a domain like sslip.io."
}

function configure_domain() {
    echo "--- 8. Configuring sslip.io domain for easy access ---"
    local EXTERNAL_IP=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

    if [ -z "$EXTERNAL_IP" ]; then
        echo "   Could not determine Kourier IP. Skipping domain configuration."
        return
    fi

    echo "   Patching Knative domain to use: $EXTERNAL_IP.sslip.io"
    kubectl patch configmap/config-domain \
      --namespace knative-serving \
      --type merge \
      --patch "{\"data\":{\"$EXTERNAL_IP.sslip.io\":\"\"}}"
    
    echo "   Domain configured. Services will now use sslip.io URLs."
}

function stop_tunnel() {
    echo "--- Stopping Minikube Tunnel ---"
    if [ -f "$TUNNEL_PID_FILE" ]; then
        echo "   Killing tunnel process with PID $(cat $TUNNEL_PID_FILE)..."
        kill $(cat $TUNNEL_PID_FILE) || true
        rm -f "$TUNNEL_PID_FILE"
    else
        # Fallback in case the PID file is missing but the process is running
        pkill -f "minikube tunnel --profile ${CLUSTER_PROFILE}" || echo "   No running tunnel process found to kill."
    fi
}

function destroy_cluster() {
    echo "--- Deleting Minikube Cluster (${CLUSTER_PROFILE}) ---"
    minikube delete --profile "${CLUSTER_PROFILE}"
}

# ==============================================================================
# --- Main Logic ---
# ==============================================================================

ACTION=$1

if [ -z "$ACTION" ]; then
    echo "Usage: $0 <start|destroy>"
    exit 1
fi

case "$ACTION" in
    start)
        check_prerequisites
        start_cluster
        start_tunnel
        install_knative
        verify_installation
        ;;
    destroy)
        stop_tunnel
        destroy_cluster
        echo "--- Cleanup Complete ---"
        ;;
    *)
        echo "Invalid action: ${ACTION}"
        echo "Usage: $0 <start|destroy>"
        exit 1
        ;;
esac