#!/bin/bash

# ==============================================================================
# Knative Event Display Deployment Script
#
# This script automates the deployment of the event-display application and its
# corresponding PingSource. It handles cleanup, deployment, and verification,
# providing clear instructions for the final manual check.
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
SERVICE_NAME="event-display"

# --- Path and Context Setup ---
# This makes the script runnable from any directory within the project.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd)
DEPLOY_FILE_PATH="${PROJECT_ROOT}/apps/event-display/deploy.yaml"

# --- Pre-flight Check ---
if [ ! -f "$DEPLOY_FILE_PATH" ]; then
    echo "❌ ERROR: Deployment file not found at '${DEPLOY_FILE_PATH}'"
    exit 1
fi

echo "--- 1. Cleaning up existing resources from ${DEPLOY_FILE_PATH} ---"
# Use --ignore-not-found to prevent errors if the resources don't exist.
kubectl delete -f "${DEPLOY_FILE_PATH}" --ignore-not-found=true
echo "   (Waiting a moment for resources to terminate...)"
sleep 5 # A small sleep helps prevent race conditions on busy clusters.

echo ""
echo "--- 2. Applying new deployment from ${DEPLOY_FILE_PATH} ---"
echo "   (Ensure your username is correct in the deploy.yaml image path!)"
kubectl apply -f "${DEPLOY_FILE_PATH}"

echo ""
echo "--- 3. Waiting for service '${SERVICE_NAME}' to become ready ---"
echo "   (This may take a minute while the container image is pulled...)"
# We use `kubectl wait` on the Knative service resource (ksvc) for reliability.
# This is the most robust way to wait for a service to be fully operational.
kubectl wait --for=condition=Ready=True ksvc/${SERVICE_NAME} --timeout=180s
echo "✅ Service '${SERVICE_NAME}' is ready!"

echo ""
echo "--- 4. Displaying running pods for the service ---"
# Show the user the pod that was successfully created.
kubectl get pods -l serving.knative.dev/service=${SERVICE_NAME}

echo ""
echo "✅✅✅ --- Deployment successful! --- ✅✅✅"
echo ""
echo "The PingSource has been created and will send an event every minute."
echo "To verify that your application is receiving events, run the following"
echo "command in your terminal and wait for log messages to appear:"
echo ""
echo "   kubectl logs -l serving.knative.dev/service=${SERVICE_NAME} -c user-container --follow"
echo ""