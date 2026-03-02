#!/bin/bash

set -e

IMAGE_FILE="$1"

if [ -z "$IMAGE_FILE" ]; then
    echo "Usage: $0 <path-to-image.img>"
    exit 1
fi

echo "=== Verifying Read-Only Root Filesystem Implementation ==="
echo "Image: $IMAGE_FILE"
echo ""

# Setup loop device
LOOPDEV=$(sudo losetup -fP --show "$IMAGE_FILE")
echo "Loop device: $LOOPDEV"

# Cleanup function
cleanup() {
    if [ -n "$MOUNT_POINT" ] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT"
    fi
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        rmdir "$MOUNT_POINT"
    fi
    if [ -n "$LOOPDEV" ] && [ -b "$LOOPDEV" ]; then
        sudo losetup -d "$LOOPDEV"
    fi
}

trap cleanup EXIT

# Check partitions
echo ""
echo "=== Partition Table ==="
sudo parted -m --script "$LOOPDEV" unit MB print

# Check for partition 3
if [ ! -b "${LOOPDEV}p3" ]; then
    echo "ERROR: Partition 3 (storage) not found!"
    exit 1
fi
echo "✓ Partition 3 exists"

# Check partition 3 filesystem
FS_TYPE=$(sudo blkid -o value -s TYPE "${LOOPDEV}p3")
FS_LABEL=$(sudo blkid -o value -s LABEL "${LOOPDEV}p3")

if [ "$FS_TYPE" != "ext4" ]; then
    echo "ERROR: Partition 3 is not ext4 (found: $FS_TYPE)"
    exit 1
fi
echo "✓ Partition 3 is ext4"

if [ "$FS_LABEL" != "photon-storage" ]; then
    echo "ERROR: Partition 3 label is not 'photon-storage' (found: $FS_LABEL)"
    exit 1
fi
echo "✓ Partition 3 has correct label (photon-storage)"

# Get partition 3 size
PART3_SIZE=$(sudo parted -m --script "$LOOPDEV" unit MB print | grep "^3:" | awk -F: '{print $4}')
echo "  Storage partition size: $PART3_SIZE"

# Mount root partition
MOUNT_POINT=$(mktemp -d)
sudo mount "${LOOPDEV}p2" "$MOUNT_POINT"

# Check fstab
echo ""
echo "=== fstab Configuration ==="
if ! grep -E '[[:space:]]/[[:space:]].*ro' "$MOUNT_POINT/etc/fstab" | grep -v '^#' >/dev/null; then
    echo "ERROR: 'ro' option not found in fstab for root filesystem"
    exit 1
fi
echo "✓ Root filesystem configured as read-only"

if ! grep -q "/mnt/photon-storage" "$MOUNT_POINT/etc/fstab"; then
    echo "ERROR: Storage partition mount not found in fstab"
    exit 1
fi
echo "✓ Storage partition mount configured"

if ! grep -q "overlay /opt/photonvision" "$MOUNT_POINT/etc/fstab"; then
    echo "ERROR: Overlay mount not found in fstab"
    exit 1
fi
echo "✓ Overlay mount configured"

echo ""
echo "fstab entries:"
grep -v '^#' "$MOUNT_POINT/etc/fstab" | grep -v '^$'

# Check systemd service
echo ""
echo "=== Systemd Service ==="
if [ ! -f "$MOUNT_POINT/etc/systemd/system/photonvision-overlay-init.service" ]; then
    echo "ERROR: photonvision-overlay-init.service not found"
    exit 1
fi
echo "✓ Systemd overlay init service exists"

# Check if service is enabled
if [ -L "$MOUNT_POINT/etc/systemd/system/multi-user.target.wants/photonvision-overlay-init.service" ]; then
    echo "✓ Overlay init service is enabled"
else
    echo "WARNING: Overlay init service may not be enabled"
fi

# Check directories
echo ""
echo "=== Directory Structure ==="
if [ ! -d "$MOUNT_POINT/opt/photonvision" ]; then
    echo "ERROR: /opt/photonvision directory not found"
    exit 1
fi
echo "✓ PhotonVision directory exists"

if [ ! -d "$MOUNT_POINT/mnt/photon-storage" ]; then
    echo "ERROR: /mnt/photon-storage directory not found"
    exit 1
fi
echo "✓ Storage mount point exists"

# Check PhotonVision installation
echo ""
echo "=== PhotonVision Installation ==="
if [ -f "$MOUNT_POINT/opt/photonvision/photonvision.jar" ]; then
    echo "✓ PhotonVision JAR file exists"
else
    echo "WARNING: PhotonVision JAR file not found"
fi

if [ -f "$MOUNT_POINT/lib/systemd/system/photonvision.service" ] || \
   [ -f "$MOUNT_POINT/etc/systemd/system/photonvision.service" ]; then
    echo "✓ PhotonVision systemd service exists"
else
    echo "WARNING: PhotonVision systemd service not found"
fi

echo ""
echo "=== All Verifications Passed! ==="
echo ""
echo "Summary:"
echo "  ✓ Storage partition created and formatted"
echo "  ✓ Root filesystem configured as read-only"
echo "  ✓ Overlay mount configured for /opt/photonvision"
echo "  ✓ Systemd service configured for overlay initialization"
echo "  ✓ Directory structure correct"
echo ""
echo "The image is ready for deployment!"
