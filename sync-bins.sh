#!/bin/bash

IMG="builds/pristella.img"
ROOTFS="rootfs"
MOUNT_DIR="/mnt/pristella-sync"
TMP_IMG="/tmp/pristella-sync.img"
LOOP=""

if [ ! -f "$IMG" ]; then
    echo "error: $IMG not found. Run from the Pristella folder."
    exit 1
fi

if losetup -a | grep -q "$IMG"; then
    echo "error: image is in use by QEMU. Creating temporary copy..."
    cp "$IMG" "$TMP_IMG"
    IMG="$TMP_IMG"
fi

echo "error: mounting $IMG..."
LOOP=$(sudo losetup -fP --show "$IMG")
if [ -z "$LOOP" ]; then
    echo "error: failed to create loop device"
    exit 1
fi

PART="${LOOP}p2"
if [ ! -b "$PART" ]; then
    PART="${LOOP}p1"
fi

if [ ! -b "$PART" ]; then
    echo "error: partition $PART not found"
    sudo losetup -d "$LOOP"
    exit 1
fi

sudo mkdir -p "$MOUNT_DIR"
sudo mount "$PART" "$MOUNT_DIR"
if [ $? -ne 0 ]; then
    echo "error: failed to mount $PART"
    sudo losetup -d "$LOOP"
    exit 1
fi

echo "coping binaries from $MOUNT_DIR to $ROOTFS..."
for dir in bin sbin usr/bin usr/sbin; do
    if [ -d "$MOUNT_DIR/$dir" ]; then
        echo "  → $dir"
        sudo rm -rf "$ROOTFS/$dir"
        sudo cp -a "$MOUNT_DIR/$dir" "$ROOTFS/$dir"
    fi
done

echo "umounting..."
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP"
[ -f "$TMP_IMG" ] && rm -f "$TMP_IMG"
sudo chown -R $USER:$USER /home/$USER/Pristella/rootfs

echo "Done. Binaries synced to $ROOTFS."