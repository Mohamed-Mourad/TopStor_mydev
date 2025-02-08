#!/bin/bash
# create_branch_diff.sh
# Creates a zip file containing the differences between two Git branches

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <source_dir> <branch1> <branch2> <output_zip>"
    exit 1
fi

SOURCE_DIR=$1
BRANCH1=$2
BRANCH2=$3
OUTPUT_ZIP=$4

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

#!/bin/bash
# apply_branch_diff.sh
# Applies the zipped branch differences to target directory

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <target_dir> <diff_zip>"
    exit 1
fi

TARGET_DIR=$1
DIFF_ZIP=$2

# Check if target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory does not exist"
    exit 1
fi

# Check if zip file exists
if [ ! -f "$DIFF_ZIP" ]; then
    echo "Error: Diff zip file does not exist"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)

# Unzip the diff file
unzip "$DIFF_ZIP" -d "$TEMP_DIR"

# Copy files to target directory
cd "$TEMP_DIR" || exit 1
cp -r . "$TARGET_DIR/"

# Cleanup
rm -rf "$TEMP_DIR"

# Switch to target directory
cd "$TARGET_DIR" || exit 1

# Add all changes to git
git add .

# Create new branch x2 if it doesn't exist and switch to it
git checkout -b x2 2>/dev/null || git checkout x2

# Commit changes
git commit -m "Applied changes from diff zip"

echo "Successfully applied changes and switched to branch x2"
