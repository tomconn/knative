#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CLUSTER_PROFILE="knative-demo" # A unique name for your minikube profile
TUNNEL_PID_FILE="/tmp/minikube_${CLUSTER_PROFILE}_tunnel.pid"

# --- Helper Functions ---
function check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "Error: Command '$1' not found. Please install it."
        exit 1
    fi
}

# --- Main Logic ---
ACTION=$1

if [ -z "$ACTION" ]; then
    echo "Usage: $0 <start|destroy>"
    exit 1
fi

case "$ACTION" in
    start)
        echo "--- Checking prerequisites ---"
        check_command minikube
        check_command kn
        check_command docker

        echo "--- Starting Minikube Cluster (${CLUSTER_PROFILE}) ---"
        minikube start \
          --profile "${CLUSTER_PROFILE}" \
          --driver=docker \
          --cpus=4 \
          --memory=7g \
          --kubernetes-version=v1.32.6

        echo "--- Starting Minikube Tunnel in the background (BEFORE Knative install) ---"
        # The tunnel must be running *before* installing Kourier so it can get an IP.
        if [ -f "$TUNNEL_PID_FILE" ]; then
            echo "Tunnel PID file found. Killing existing tunnel..."
            kill $(cat $TUNNEL_PID_FILE) || true
            rm -f "$TUNNEL_PID_FILE"
        fi
        minikube tunnel --profile "${CLUSTER_PROFILE}" &
        echo $! > "$TUNNEL_PID_FILE"
        echo "Tunnel started with PID $(cat $TUNNEL_PID_FILE). Giving it a moment to establish..."
        sleep 20 # Give tunnel a generous amount of time to be ready, in X seconds

        echo "--- Setting docker-env for minikube ---"
        eval $(minikube -p "${CLUSTER_PROFILE}" docker-env)

        echo "--- Installing Knative Serving and Eventing using Quickstart ---"
        echo "--- IMPORTANT: A prompt will appear to start the tunnel. It is already running. ---"
        echo "---           Please just press the ENTER key to continue.                   ---"
        
        kn quickstart minikube --name "${CLUSTER_PROFILE}" --install-serving --install-eventing

        echo "--- Cluster is READY! ---"
        echo "Minikube Profile: ${CLUSTER_PROFILE}"
        echo "Knative is installed."
        echo "Tunnel is running."
        echo "You can now deploy your applications."
        ;;

    destroy)
        echo "--- Stopping Minikube Tunnel ---"
        if [ -f "$TUNNEL_PID_FILE" ]; then
            echo "Killing tunnel process with PID $(cat $TUNNEL_PID_FILE)..."
            kill $(cat $TUNNEL_PID_FILE) || echo "Tunnel process not found."
            rm -f "$TUNNEL_PID_FILE"
        else
            echo "Tunnel PID file not found. Nothing to stop."
        fi

        echo "--- Deleting Minikube Cluster (${CLUSTER_PROFILE}) ---"
        minikube delete --profile "${CLUSTER_PROFILE}"

        echo "--- Cleanup Complete ---"
        ;;

    *)
        echo "Invalid action: ${ACTION}"
        echo "Usage: $0 <start|destroy>"
        exit 1
        ;;
esac