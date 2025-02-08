#!/bin/bash
# create_branch_diff.sh
# Creates a zip file containing the differences between two Git branches


SOURCE_DIR='/TopStor'
BRANCH1='QSD3.64'
BRANCH2='QSD3.65'
OUTPUT_ZIP=/root/gitzip.zip

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)

# Navigate to source directory
cd "$SOURCE_DIR" || exit 1

# Get list of changed files between branches
git diff --name-only "$BRANCH1" "$BRANCH2" > "$TEMP_DIR/changed_files.txt"

# Copy changed files to temporary directory maintaining directory structure
while IFS= read -r file; do
    if [ -f "$file" ]; then
        mkdir -p "$TEMP_DIR/$(dirname "$file")"
        cp "$file" "$TEMP_DIR/$file"
    fi
done < "$TEMP_DIR/changed_files.txt"

# Create zip file
cd "$TEMP_DIR" || exit 1
zip -r "$OUTPUT_ZIP" .

# Cleanup
rm -rf "$TEMP_DIR"

echo "Created diff zip file: $OUTPUT_ZIP"
