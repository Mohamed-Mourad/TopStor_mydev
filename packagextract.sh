#!/bin/bash

# Input file containing the compressed and encrypted data
input_file="/TopStordata/output.tar.gz.enc"

# Encryption password (must match the one used for encryption)
password="QuickStor!@#2"
directories=("TopStor" "pace" "topstorweb")
# Temporary tar file
temp_tar="/TopStordata/temp.tar.gz"

openssl enc -d -aes-256-cbc -in "$input_file" -out "$temp_tar" -k "$password" -a 2>/dev/null
# Loop to extract each directory
for dir in "${directories[@]}"; do
	rm -rf '/'${dir}.bak 2>/dev/null
	mkdir '/'${dir}.bak
	tar -xzf "$temp_tar" -C '/'${dir}.bak $dir

done
rm -rf $temp_tar

echo "All directories have been processed."
/TopStor/indevicepull.sh
