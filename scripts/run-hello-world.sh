#!/bin/bash

# ==============================================================================
# Knative "Hello World" Test Script
#
# This script deploys a known-good, multi-arch "hello world" service
# to the currently configured Knative cluster. It then waits for the service
# to become ready and verifies that it is reachable via its URL.
#
# It is designed to be idempotent, meaning you can run it multiple times.
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# We use a verified multi-arch image to avoid architecture conflicts on Apple Silicon.
SERVICE_NAME="hello-nginx"
IMAGE_NAME="nginxdemos/hello"
CONTAINER_PORT="80" # This specific demo image listens on port 80.

# --- Main Logic ---

echo "--- 1. Checking for and cleaning up existing service: ${SERVICE_NAME} ---"
# The '|| true' prevents the script from exiting if the service doesn't exist.
# The 'grep -q' checks quietly for the service name at the beginning of a line.
if kn service list | grep -q "^${SERVICE_NAME} "; then
    echo "   Service found. Deleting it for a fresh start..."
    kn service delete "${SERVICE_NAME}"
    echo "   Waiting for resources to be fully deleted..."
    sleep 5 # Give Kubernetes a moment to finalize deletion.
else
    echo "   No existing service found. Ready to deploy."
fi

echo ""
echo "--- 2. Deploying new Knative service: ${SERVICE_NAME} ---"
kn service create "${SERVICE_NAME}" \
  --image "${IMAGE_NAME}" \
  --port "${CONTAINER_PORT}"

echo ""
echo "--- 3. Waiting for the service to become ready ---"
echo "   (This may take a minute as the container image is pulled...)"
# We use `kubectl wait` on the Knative service resource (ksvc) for reliability.
# This is the most robust way to wait for a service to be fully operational.
kubectl wait --for=condition=Ready=True ksvc/${SERVICE_NAME} --timeout=180s
echo "✅ Service is ready!"

echo ""
echo "--- 4. Retrieving service URL ---"
SERVICE_URL=$(kn service describe "${SERVICE_NAME}" -o url)
if [ -z "${SERVICE_URL}" ]; then
    echo "❌ ERROR: Could not retrieve the service URL."
    exit 1
fi
echo "   Service URL is: ${SERVICE_URL}"

echo ""
echo "--- 5. Verifying service endpoint with curl ---"
# We use --fail to make curl return an error code on HTTP failures (like 404/503).
# We capture the output to a temp file to display only on success.
CURL_OUTPUT_FILE=$(mktemp)
if curl --silent --fail --show-error --connect-timeout 10 -o "${CURL_OUTPUT_FILE}" "${SERVICE_URL}"; then
    echo "✅ SUCCESS! The service is reachable and responding correctly."
    echo
    echo "--- Service Response ---"
    cat "${CURL_OUTPUT_FILE}"
    echo "------------------------"
    rm "${CURL_OUTPUT_FILE}"
else
    echo "❌ FAILED: The service endpoint is not responding correctly."
    echo "   Please check the pod logs for more details:"
    echo "   kubectl get pods -l serving.knative.dev/service=${SERVICE_NAME}"
    echo "   kubectl logs -l serving.knative.dev/service=${SERVICE_NAME} -c user-container"
    rm "${CURL_OUTPUT_FILE}"
    exit 1
fi
