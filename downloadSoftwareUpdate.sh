#!/bin/bash

UPDATE_DEST="/opt/software_update"
LOGFILE="/var/log/update_script.log"

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

download_http() {
    URL=$1
    DEST=$2
    log "Downloading update from $URL..."
    wget -O "$DEST/update.tar.gz" "$URL" || curl -o "$DEST/update.tar.gz" "$URL" || error_exit "Failed to download from HTTP."
}

download_nfs() {
    SERVER=$1
    MOUNT_POINT="/mnt/nfs_update"
    
    log "Mounting NFS share from $SERVER..."
    mkdir -p $MOUNT_POINT
    mount -t nfs $SERVER $MOUNT_POINT || error_exit "Failed to mount NFS."
    
    log "Copying update..."
    cp -r $MOUNT_POINT/* "$UPDATE_DEST" || error_exit "Failed to copy from NFS."
    
    log "Unmounting..."
    umount $MOUNT_POINT
    rm -rf $MOUNT_POINT
}

download_cifs() {
    SERVER=$1
    USERNAME="user"  # Replace with actual username
    PASSWORD="password"  # Replace with actual password
    MOUNT_POINT="/mnt/cifs_update"
    
    log "Mounting CIFS share from $SERVER..."
    mkdir -p $MOUNT_POINT
    mount -t cifs $SERVER $MOUNT_POINT -o username=$USERNAME,password=$PASSWORD || error_exit "Failed to mount CIFS."
    
    log "Copying update..."
    cp -r $MOUNT_POINT/* "$UPDATE_DEST" || error_exit "Failed to copy from CIFS."
    
    log "Unmounting..."
    umount $MOUNT_POINT
    rm -rf $MOUNT_POINT
}

download_local() {
    SOURCE=$1
    log "Copying update from local source $SOURCE..."
    cp -r "$SOURCE"/* "$UPDATE_DEST" || error_exit "Failed to copy from local path."
}

# Main script execution
if [[ "$1" == "--source" && -n "$2" ]]; then
    SOURCE=$2
    mkdir -p "$UPDATE_DEST"
    
    if [[ $SOURCE == http* ]]; then
        download_http "$SOURCE" "$UPDATE_DEST"
    elif [[ $SOURCE == nfs* ]]; then
        download_nfs "$SOURCE"
    elif [[ $SOURCE == cifs* ]]; then
        download_cifs "$SOURCE"
    elif [[ -d $SOURCE || -f $SOURCE ]]; then
        download_local "$SOURCE"
    else
        error_exit "Unsupported source type."
    fi
    
    log "Update process completed successfully."
else
    echo "Usage: $0 --source <http|nfs|cifs|local_path>"
    exit 1
fi

