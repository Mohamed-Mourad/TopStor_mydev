#!/usr/bin/sh
echo "Applying new UI Updates offline..."

# 1. Load the compressed offline image and trap failures
echo "Loading image archive..."
if ! docker load -i /TopStor/quickstor-ui.tar.gz; then
  echo "ERROR: Failed to load the Docker image archive. Is the file corrupted or missing?" >&2
  exit 1
fi

# 2. Kill the old container 
# (We leave this without an error trap because it's perfectly fine if it fails—e.g., if the container didn't exist in the first place).
docker rm -f react-dev-ui 2>/dev/null

# 3. Spin up the new container and trap runtime failures
echo "Starting UI container..."
if ! docker run -itd \
  --name react-dev-ui \
  --restart unless-stopped \
  --net bridge0 \
  -p 5173:5173 \
  -v /topstorweb:/app \
  -v /app/node_modules \
  quickstor-ui:latest; then
  
  echo "ERROR: The UI container failed to start. Run 'docker logs react-dev-ui' for more details." >&2
  exit 1
fi

# Only prints if the script makes it past all the error traps
echo "UI Update Applied Successfully!"
