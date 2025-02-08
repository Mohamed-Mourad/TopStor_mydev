#!/bin/bash
# apply_branch_diff.sh
# Applies the zipped branch differences to target directory

TARGET_DIR='/TopStor_temp'
DIFF_ZIP='/root/gitzip.zip'
branch='QSD3.65'
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

# Create new branch $branch if it doesn't exist and switch to it
git checkout -b $branch 2>/dev/null || git checkout $branch 

# Commit changes
git commit -m "Applied changes from diff zip"

echo "Successfully applied changes and switched to branch $branch"
