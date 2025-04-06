#!/bin/bash

UPDATE_DEST="TopStordata/"
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
    VERSION=$2
    MOUNT_POINT="/mnt/nfs_update"

    log "Mounting NFS share from $SERVER..."
    mkdir -p $MOUNT_POINT
    mount -t nfs "$SERVER" "$MOUNT_POINT" || error_exit "Failed to mount NFS."

    log "Searching for update file with version $VERSION..."
    FILE=$(find "$MOUNT_POINT" -type f -name "*${VERSION}*" | head -n 1)
    [[ -z "$FILE" ]] && error_exit "No update file found for version $VERSION on NFS."

    log "Copying update file $FILE..."
    cp "$FILE" "$UPDATE_DEST" || error_exit "Failed to copy file from NFS."

    log "Unmounting NFS..."
    umount "$MOUNT_POINT"
    rm -rf "$MOUNT_POINT"
}

download_cifs() {
    SERVER=$1
    VERSION=$2
    USERNAME="user"  # Replace with actual username
    PASSWORD="password"  # Replace with actual password
    MOUNT_POINT="/mnt/cifs_update"

    log "Mounting CIFS share from //$SERVER..."
    mkdir -p "$MOUNT_POINT"
    mount -t cifs "//$SERVER" "$MOUNT_POINT" -o username=$USERNAME,password=$PASSWORD || error_exit "Failed to mount CIFS."

    log "Searching for update file with version $VERSION..."
    FILE=$(find "$MOUNT_POINT" -type f -name "*${VERSION}*" | head -n 1)
    [[ -z "$FILE" ]] && error_exit "No update file found for version $VERSION on CIFS."

    log "Copying update file $FILE..."
    cp "$FILE" "$UPDATE_DEST" || error_exit "Failed to copy file from CIFS."

    log "Unmounting CIFS..."
    umount "$MOUNT_POINT"
    rm -rf "$MOUNT_POINT"
}

download_local() {
    SOURCE=$1
    log "Copying update from local source $SOURCE..."
    cp -r "$SOURCE"/* "$UPDATE_DEST" || error_exit "Failed to copy from local path."
}

# Main script execution
if [[ "$1" == "--source-type" && -n "$2" && "$3" == "--source" && -n "$4" && "$5" == "--version" && -n "$6" ]]; then
    TYPE=$2
    SOURCE=$4
    VERSION=$6

    mkdir -p "$UPDATE_DEST"

    case $TYPE in
        http)
            download_http "$SOURCE" "$UPDATE_DEST"
            ;;
        nfs)
            download_nfs "$SOURCE" "$VERSION"
            ;;
        cifs)
            download_cifs "$SOURCE" "$VERSION"
            ;;
        local)
            download_local "$SOURCE"
            ;;
        *)
            error_exit "Unsupported source type: $TYPE"
            ;;
    esac

    log "Update process completed successfully."
else
    echo "Usage: $0 --source-type <http|nfs|cifs|local> --source <source_path_or_url> --version <version_identifier>"
    exit 1
fi

