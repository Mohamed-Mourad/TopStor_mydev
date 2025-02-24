#!/bin/bash

# List of directories to process
directories="/TopStor /pace /topstorweb"

# Output file for the compressed and encrypted data
output_file="/TopStordata/output.tar.gz.enc"

# Encryption password (you can change this or prompt for it)
password="QuickStor!@#2"

# Temporary tar file
temp_tar="/TopStordata/temp.tar.gz"

# Clear the output file if it exists
> "$output_file"

tar -czf $temp_tar $directories
        
        # Encrypt the compressed file and append to the output file
openssl enc -aes-256-cbc -salt -in "$temp_tar" -out "$output_file" -k "$password" -a
# Remove the temporary tar file
rm "$temp_tar"
echo "All directories have been processed and saved to $output_file." 
