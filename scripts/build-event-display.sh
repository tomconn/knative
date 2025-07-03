#!/bin/bash

# ==============================================================================
# Multi-Arch Docker Image Build & Push Script
#
# This script automates the process of building a multi-platform Docker image
# for the event-display application and pushing it to the GitHub Container
# Registry (ghcr.io).
#
# It handles:
#   - Detecting the correct Docker environment (Rancher Desktop on macOS).
#   - Checking for required user inputs (GitHub username and token).
#   - Setting up and activating the necessary 'docker buildx' builder.
#   - Logging into ghcr.io.
#   - Executing the multi-arch build and push.
#
# Usage:
#   1. As an argument:
#      GITHUB_TOKEN="your_pat" ./scripts/build-image.sh <your_github_username>
#
#   2. Using environment variables:
#      export GITHUB_USER="<your_github_username>"
#      export GITHUB_TOKEN="<your_pat>"
#      ./scripts/build-image.sh
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
IMAGE_NAME_BASE="event-display"
IMAGE_TAG="latest"

# --- Helper Functions ---
function setup_docker_environment() {
    echo "--- 1. Setting up Docker Environment ---"
    # On macOS, Rancher Desktop uses a specific socket path.
    # This ensures we are talking to the correct Docker daemon.
    if [[ "$(uname)" == "Darwin" ]]; then
        RANCHER_DESKTOP_SOCKET="/Users/$(whoami)/.rd/docker.sock"
        if [ -S "$RANCHER_DESKTOP_SOCKET" ]; then
            if [ -z "$DOCKER_HOST" ]; then
                echo "   - Detected Rancher Desktop socket and DOCKER_HOST is not set."
                echo "   - Exporting DOCKER_HOST=unix://${RANCHER_DESKTOP_SOCKET}"
                export DOCKER_HOST="unix://${RANCHER_DESKTOP_SOCKET}"
            else
                echo "   - DOCKER_HOST is already set to: ${DOCKER_HOST}"
            fi
        else
            echo "   - Rancher Desktop socket not found at ${RANCHER_DESKTOP_SOCKET}. Assuming default Docker socket."
        fi
    else
        echo "   - Not on macOS, assuming default Docker environment."
    fi
}

# --- Input Validation & Setup ---

# 1. Get GitHub Username from argument or environment variable
GITHUB_USER=${1:-$GITHUB_USER}

if [ -z "$GITHUB_USER" ]; then
    echo "❌ ERROR: GitHub username not provided."
    echo "Usage: $0 <your_github_username>"
    echo "Or set the GITHUB_USER environment variable."
    exit 1
fi

# 2. Check for GitHub Personal Access Token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ ERROR: GITHUB_TOKEN environment variable not set."
    echo "Please set your GitHub Personal Access Token with 'write:packages' scope."
    exit 1
fi

# --- Main Logic ---

setup_docker_environment

echo "--- 2. Preparing Build ---"
echo "   - User: ${GITHUB_USER}"
echo "   - Image: ${IMAGE_NAME_BASE}:${IMAGE_TAG}"

# --- Path and Context Setup ---
# This makes the script runnable from any directory within the project.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd)
BUILD_CONTEXT="${PROJECT_ROOT}/apps/event-display"

if [ ! -d "$BUILD_CONTEXT" ]; then
    echo "❌ ERROR: Build context directory not found at '${BUILD_CONTEXT}'"
    exit 1
fi

echo "   - Build Context: ${BUILD_CONTEXT}"

# --- Docker Buildx Setup ---
BUILDER_NAME="multiarch-builder"
echo "--- 3. Verifying and Activating Docker Buildx Builder: '${BUILDER_NAME}' ---"

if ! docker buildx ls | grep -q "${BUILDER_NAME}"; then
    echo "   Builder '${BUILDER_NAME}' not found. Creating it now..."
    docker buildx create --name "${BUILDER_NAME}"
fi

# Ensure the correct builder is active
if ! docker buildx ls | grep -q "${BUILDER_NAME}.*running"; then
    echo "   Activating builder '${BUILDER_NAME}'..."
    docker buildx use "${BUILDER_NAME}"
else
    echo "   Builder '${BUILDER_NAME}' is already active and running."
fi

# --- Login to GitHub Container Registry ---
echo "--- 4. Logging in to GitHub Container Registry (ghcr.io) ---"
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_USER}" --password-stdin
echo "✅ Login successful."

# --- Build and Push ---
IMAGE_NAME="ghcr.io/${GITHUB_USER}/${IMAGE_NAME_BASE}:${IMAGE_TAG}"
echo "--- 5. Building and Pushing Multi-Arch Image: ${IMAGE_NAME} ---"
echo "   (This may take several minutes, especially on the first run...)"

docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag "${IMAGE_NAME}" \
  --push \
  "${BUILD_CONTEXT}"

echo ""
echo "✅✅✅ --- Build and Push Complete! --- ✅✅✅"
echo "Image is now available at: ${IMAGE_NAME}"