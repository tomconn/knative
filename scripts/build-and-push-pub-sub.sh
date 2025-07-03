#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Your GitHub username. This is where the images will be pushed.
export GHCR_USER="tomconn"
# A tag for your images.
export IMAGE_TAG="v1"
# The target architecture. For Apple Silicon, this should be arm64.
export TARGET_ARCH="arm64"

# --- Main Logic ---
echo "Logging into GitHub Container Registry (ghcr.io)..."
# You will be prompted for your username (use your GitHub username)
# and password (use your Personal Access Token).
echo $GITHUB_TOKEN | docker login ghcr.io -u ${GHCR_USER} --password-stdin


echo "Building and pushing images for architecture: ${TARGET_ARCH}"

# Get the absolute path of the script's directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT="$SCRIPT_DIR/.."

APPS=("event-publisher" "event-consumer")

for app in "${APPS[@]}"; do
    IMAGE_NAME="${app}"
    IMAGE_FULL_NAME="ghcr.io/${GHCR_USER}/${IMAGE_NAME}:${IMAGE_TAG}"
    APP_DIR="${PROJECT_ROOT}/apps/${app}"

    echo "--------------------------------------------------"
    echo "Processing app: ${app}"
    echo "Image will be tagged as: ${IMAGE_FULL_NAME}"
    echo "--------------------------------------------------"

    # Build the Docker image
    # The --platform flag ensures we build for the correct architecture.
    docker build \
      --platform "linux/${TARGET_ARCH}" \
      -t "${IMAGE_NAME}:${IMAGE_TAG}" \
      --build-arg TARGETARCH=${TARGET_ARCH} \
      "${APP_DIR}"

    # Tag the image for GHCR
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_FULL_NAME}"

    # Push the image to GHCR
    docker push "${IMAGE_FULL_NAME}"

    echo "Successfully pushed ${IMAGE_FULL_NAME}"
done

echo "--------------------------------------------------"
echo "All images built and pushed successfully."
echo "You can now deploy them to your cluster."
echo "--------------------------------------------------"