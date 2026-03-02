#!/bin/bash

# Script to create a storage partition on an Orange Pi 5 image
# This runs AFTER the image is built by photon-image-runner
# Usage: create_storage_partition.sh <image_file> <size_mb>

set -euo pipefail

IMAGE_FILE="$1"
STORAGE_SIZE_MB="${2:-512}"  # Default 512MB

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image file not found: $IMAGE_FILE"
    exit 1
fi

echo "=== Creating Storage Partition ==="
echo "Image: $IMAGE_FILE"
echo "Storage partition size: ${STORAGE_SIZE_MB}MB"
echo ""

# Attach the image as a loop device
LOOPDEV=$(sudo losetup --find --show --partscan "$IMAGE_FILE")
echo "Loop device: $LOOPDEV"

# Cleanup function
cleanup() {
    if [ -n "${LOOPDEV:-}" ]; then
        echo "Detaching loop device: $LOOPDEV"
        sudo losetup -d "$LOOPDEV" || true
    fi
}
trap cleanup EXIT

# Get partition table type
PART_TYPE=$(sudo blkid -o value -s PTTYPE "$LOOPDEV")
echo "Partition table type: $PART_TYPE"

# Display current partition layout
echo ""
echo "Current partition layout:"
sudo parted -m --script "$LOOPDEV" unit MB print

# Find the root partition (assume partition 2)
ROOTPARTITION=2
STORAGE_PARTITION=$((ROOTPARTITION + 1))

# Get the end of the root partition in sectors
ROOTFS_PARTEND_SECTOR=$(sudo parted -m --script "$LOOPDEV" unit s print | grep "^${ROOTPARTITION}:" | awk -F ":" '{print $3}' | tr -d 's')

if [ -z "$ROOTFS_PARTEND_SECTOR" ]; then
    echo "ERROR: Could not find root partition end sector"
    exit 1
fi

echo "Root partition ends at sector: $ROOTFS_PARTEND_SECTOR"

# Calculate start of storage partition (1MB = 2048 sectors after root partition for alignment)
STORAGE_PARTSTART=$((ROOTFS_PARTEND_SECTOR + 2048))

# Calculate size in sectors (2048 sectors per MB, assuming 512-byte sectors)
STORAGE_SIZE_SECTORS=$((STORAGE_SIZE_MB * 2048))
STORAGE_PARTEND=$((STORAGE_PARTSTART + STORAGE_SIZE_SECTORS))

# Create the storage partition
echo ""
echo "Creating storage partition ${STORAGE_PARTITION}"
echo "  Start: sector ${STORAGE_PARTSTART}"
echo "  End: sector ${STORAGE_PARTEND}"
echo "  Size: ${STORAGE_SIZE_MB}MB (${STORAGE_SIZE_SECTORS} sectors)"

sudo parted --script "$LOOPDEV" unit s mkpart primary ext4 ${STORAGE_PARTSTART} ${STORAGE_PARTEND}

# Refresh partition table
sudo partprobe "$LOOPDEV"
sync
sleep 2

# Verify partition was created
if [ ! -b "${LOOPDEV}p${STORAGE_PARTITION}" ]; then
    echo "ERROR: Storage partition ${LOOPDEV}p${STORAGE_PARTITION} was not created"
    exit 1
fi

echo "✓ Partition created successfully"

# Format the partition as ext4
echo ""
echo "Formatting storage partition as ext4..."
sudo mkfs.ext4 -F "${LOOPDEV}p${STORAGE_PARTITION}" -L photon-storage

# Verify formatting
FS_TYPE=$(sudo blkid -o value -s TYPE "${LOOPDEV}p${STORAGE_PARTITION}")
FS_LABEL=$(sudo blkid -o value -s LABEL "${LOOPDEV}p${STORAGE_PARTITION}")

echo "✓ Partition formatted"
echo "  Filesystem: $FS_TYPE"
echo "  Label: $FS_LABEL"

# Extend the image file to accommodate the new partition
# The image was shrunk by pack_image.sh, so we need to extend it
echo ""
echo "Extending image file..."

# Calculate new image size (add some padding for GPT secondary header if needed)
NEW_SIZE_SECTORS=$((STORAGE_PARTEND + 2048))
NEW_SIZE_BYTES=$((NEW_SIZE_SECTORS * 512))

if [ "$PART_TYPE" = "gpt" ]; then
    # Add space for secondary GPT (33 sectors = 16896 bytes)
    NEW_SIZE_BYTES=$((NEW_SIZE_BYTES + 16896))
fi

# Detach loop device before extending file
echo "Detaching loop device temporarily to extend file..."
sudo losetup -d "$LOOPDEV"

# Extend the image file
sudo truncate -s "$NEW_SIZE_BYTES" "$IMAGE_FILE"

# Re-attach loop device
LOOPDEV=$(sudo losetup --find --show --partscan "$IMAGE_FILE")
echo "Re-attached as: $LOOPDEV"

if [ "$PART_TYPE" = "gpt" ]; then
    echo "Fixing GPT secondary header..."
    sudo sgdisk -e "$LOOPDEV"
fi

echo "✓ Image extended to $NEW_SIZE_BYTES bytes"

# Display final partition layout
echo ""
echo "Final partition layout:"
sudo parted -m --script "$LOOPDEV" unit MB print

echo ""
echo "=== Storage Partition Created Successfully ==="

# Detach loop device
sudo losetup -d "$LOOPDEV"
LOOPDEV=""  # Clear variable so cleanup doesn't try again
