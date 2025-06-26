#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Your GitHub username.
export GHCR_USER="tomconn"
# The tag of the images you want to delete.
export IMAGE_TAG="v1"

APPS=("event-publisher" "event-consumer")

echo "This script will delete tag '${IMAGE_TAG}' for all apps."
echo "Authenticating with gh to ensure permissions..."
gh auth status

for app in "${APPS[@]}"; do
    PACKAGE_NAME="${app}"
    echo "--------------------------------------------------"
    echo "Checking for package: ${PACKAGE_NAME} with tag: ${IMAGE_TAG}"

    # Use gh api and jq to find the version ID for the specific tag
    VERSION_ID=$(gh api \
      --header "Accept: application/vnd.github+json" \
      /users/${GHCR_USER}/packages/container/${PACKAGE_NAME}/versions \
      | jq --arg TAG "$IMAGE_TAG" '.[] | select(.metadata.container.tags[]? == $TAG) | .id')

    if [ -z "$VERSION_ID" ]; then
        echo "No version found for tag '${IMAGE_TAG}'. Skipping."
    else
        echo "Found version ID: ${VERSION_ID}. Deleting..."
        gh api \
          --method DELETE \
          --header "Accept: application/vnd.github+json" \
          /users/${GHCR_USER}/packages/container/${PACKAGE_NAME}/versions/${VERSION_ID}
        echo "Successfully deleted ${PACKAGE_NAME}:${IMAGE_TAG} (Version ID: ${VERSION_ID})"
    fi
done

echo "--------------------------------------------------"
echo "Cleanup complete."