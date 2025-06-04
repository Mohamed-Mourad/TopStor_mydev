#!/usr/bin/sh

# Check if a version argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version_name>  # the version should be the current running version"
    exit 1
fi


### Compress and encrypt all repos

# Define directory paths
repo1="/TopStor"
repo2="/pace"
repo3="/topstorweb"
output_dir="/TopStordata"
zip_filename="software_update_$1.zip"
encrypted_filename="$zip_filename.enc"
encryption_password="your_password"  # Replace with your own password

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"

# Compress the repositories into a zip file
zip -r "$zip_filename" "$repo1" "$repo2" "$repo3"

# Encrypt the zip file with OpenSSL (AES-256 encryption) using PBKDF2
openssl enc -aes-256-cbc -salt -pbkdf2 -in "$zip_filename" -out "$encrypted_filename" -pass pass:"$encryption_password"

# Move the encrypted file to /TopstorData
mv "$encrypted_filename" "$output_dir"

# Clean up the unencrypted zip file
rm "$zip_filename"

### TODO: myrepopush

# Output result
echo "The repositories have been packaged, encrypted, and saved to $output_dir/$encrypted_filename"
