#!/usr/bin/sh
echo "Applying new UI Updates offline..."

# Retrieve the version number (Modify this assignment if version is read from a file)
VERSION=$1 

# Check if the version starts with QSD5
echo "$VERSION" | grep -q "^QSD5"
if [ $? -eq 0 ]; then
    echo "Version is 5.x series ($VERSION). Skipping offline image load..."
else
    # 1. Load the compressed offline image and trap failures
    echo "Loading image archive..."
    if ! docker load -i /TopStor/quickstor-ui.tar.gz; then
      echo "ERROR: Failed to load the Docker image archive. Is the file corrupted or missing?" >&2
      exit 1
    fi
fi

# We rely on docker_setup.sh to handle all container destruction and creation.
echo "UI Update Pre-Application Completed!"
