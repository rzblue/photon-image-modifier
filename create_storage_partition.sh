#!/bin/bash

# Script to create a storage partition on an Orange Pi 5 image
# This runs AFTER the image is built by photon-image-runner
# Usage: create_storage_partition.sh <image_file> <size_mb>

set -euo pipefail

# Constants
SECTOR_SIZE=512                    # Sector size in bytes
SECTORS_PER_MB=2048                # Number of sectors per MB (for 512-byte sectors)
DEFAULT_STORAGE_SIZE_MB=512        # Default storage partition size (must match workflow)
ROOTPARTITION=2                    # Root partition number (standard for OPi5 images)
STORAGE_PARTITION=3                # Storage partition number

IMAGE_FILE="$1"
STORAGE_SIZE_MB="${2:-$DEFAULT_STORAGE_SIZE_MB}"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image file not found: $IMAGE_FILE"
    exit 1
fi

echo "=== Creating Storage Partition ==="
echo "Image: $IMAGE_FILE"
echo "Storage partition size: ${STORAGE_SIZE_MB}MB"
echo "Root partition: $ROOTPARTITION (assumed for Orange Pi 5 images)"
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

# Verify root partition exists
if ! sudo parted -m --script "$LOOPDEV" unit s print | grep -q "^${ROOTPARTITION}:"; then
    echo "ERROR: Root partition ${ROOTPARTITION} not found in image"
    echo "This script assumes partition ${ROOTPARTITION} is the root partition"
    exit 1
fi

# Get the end of the root partition in sectors
ROOTFS_PARTEND_SECTOR=$(sudo parted -m --script "$LOOPDEV" unit s print | grep "^${ROOTPARTITION}:" | awk -F ":" '{print $3}' | tr -d 's')

if [ -z "$ROOTFS_PARTEND_SECTOR" ]; then
    echo "ERROR: Could not find root partition end sector"
    exit 1
fi

echo "Root partition ${ROOTPARTITION} ends at sector: $ROOTFS_PARTEND_SECTOR"

# Calculate start of storage partition (1MB after root partition for alignment)
STORAGE_PARTSTART=$((ROOTFS_PARTEND_SECTOR + SECTORS_PER_MB))

# Calculate size in sectors
STORAGE_SIZE_SECTORS=$((STORAGE_SIZE_MB * SECTORS_PER_MB))
STORAGE_PARTEND=$((STORAGE_PARTSTART + STORAGE_SIZE_SECTORS))

echo ""
echo "Planned storage partition ${STORAGE_PARTITION}"
echo "  Start: sector ${STORAGE_PARTSTART}"
echo "  End: sector ${STORAGE_PARTEND}"
echo "  Size: ${STORAGE_SIZE_MB}MB (${STORAGE_SIZE_SECTORS} sectors)"

# Extend the image file to accommodate the new partition BEFORE creating it
# The image was shrunk by pack_image.sh, so we need to extend it first
echo ""
echo "Extending image file to accommodate new partition..."

# Calculate new image size (add padding for alignment and GPT if needed)
NEW_SIZE_SECTORS=$((STORAGE_PARTEND + SECTORS_PER_MB))
NEW_SIZE_BYTES=$((NEW_SIZE_SECTORS * SECTOR_SIZE))

if [ "$PART_TYPE" = "gpt" ]; then
    # Add space for secondary GPT (33 sectors)
    GPT_SECTORS=33
    NEW_SIZE_BYTES=$((NEW_SIZE_BYTES + (GPT_SECTORS * SECTOR_SIZE)))
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

# Now create the storage partition
echo ""
echo "Creating storage partition ${STORAGE_PARTITION}"
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

# Display final partition layout
echo ""
echo "Final partition layout:"
sudo parted -m --script "$LOOPDEV" unit MB print

echo ""
echo "=== Storage Partition Created Successfully ==="

# Detach loop device
sudo losetup -d "$LOOPDEV"
LOOPDEV=""  # Clear variable so cleanup doesn't try again
