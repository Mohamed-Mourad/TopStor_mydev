#!/usr/bin/sh
echo "Applying new UI Updates offline..."

# 1. Load the compressed offline image
docker load -i /TopStor/quickstor-ui.tar.gz

# 2. Kill the old container if it exists
docker rm -f react-dev-ui 2>/dev/null

# 3. Spin up the new container WITH live-edit mounts
docker run -d \
  --name react-dev-ui \
  --restart unless-stopped \
  --net bridge0 \
  -p 5173:5173 \
  -v /topstorweb:/app \
  -v /app/node_modules \
  quickstor-ui:latest

echo "UI Update Applied Successfully!"
