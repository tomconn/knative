#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CLUSTER_PROFILE="knative-demo" # A unique name for your minikube profile
TUNNEL_PID_FILE="/tmp/minikube_${CLUSTER_PROFILE}_tunnel.pid"
KNATIVE_VERSION="v1.18.0"
KUBERNETES_VERSION="v1.32.6"

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
          --kubernetes-version=${KUBERNETES_VERSION}

        minikube profile "${CLUSTER_PROFILE}"

        echo "--- Waiting for Kubernetes API server to be ready ---"
        kubectl wait --for=condition=Available=True deployment/coredns -n kube-system --timeout=300s

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
        sleep 10 # Give tunnel a generous amount of time to be ready, in X seconds


        # ===================================================================
        # STEP 3: Install Knative APPLICATIONS onto the cluster
        # This is where Kourier is actually installed.
        # ===================================================================
        echo "--- Installing Knative Serving ---"
        kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml
        kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml

        echo "--- Installing Kourier networking layer ---"
        # THIS LINE INSTALLS KOURIER
        kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-${KNATIVE_VERSION}/kourier.yaml

        echo "--- Configuring Knative Serving to use Kourier ---"
        # THIS LINE TELLS KNATIVE TO USE THE KOURIER WE JUST INSTALLED
        kubectl patch configmap/config-network \
          --namespace knative-serving \
          --type merge \
          --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

        echo "--- Installing Knative Eventing ---"
        kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml
        kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml

        # ===================================================================
        # STEP 4: Wait for all installed applications to become ready
        # ===================================================================
        echo "--- Waiting for all Knative components to be ready ---"
        kubectl wait --for=condition=Available=True deployment --all -n knative-serving --timeout=300s
        kubectl wait --for=condition=Available=True deployment --all -n knative-eventing --timeout=300s
        kubectl wait --for=condition=Available=True deployment --all -n kourier-system --timeout=300s

        echo "--- Setting docker-env for minikube ---"
        #eval $(minikube -p "${CLUSTER_PROFILE}" docker-env)

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