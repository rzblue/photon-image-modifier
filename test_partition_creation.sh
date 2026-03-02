#!/bin/bash

# Test script to verify partition creation logic

set -e

echo "=== Testing mount_image.sh partition creation logic ==="
echo ""

# Create a test disk image (50MB)
TEST_IMG="/tmp/test_image.img"
dd if=/dev/zero of="$TEST_IMG" bs=1M count=50 status=none

echo "Created test image: $TEST_IMG (50MB)"

# Create partition table
echo "Creating GPT partition table..."
sgdisk -og "$TEST_IMG" >/dev/null 2>&1

# Create partition 1 (boot, 10MB)
echo "Creating partition 1 (boot, 10MB)..."
sgdisk -n 1:2048:+10M -t 1:0700 "$TEST_IMG" >/dev/null 2>&1

# Create partition 2 (root, 30MB)
echo "Creating partition 2 (root, 30MB)..."
sgdisk -n 2:0:+30M -t 2:8300 "$TEST_IMG" >/dev/null 2>&1

# Setup loop device
loopdev=$(losetup --find --show --partscan "$TEST_IMG")
echo "Loop device: $loopdev"

# Show current partitions
echo ""
echo "Initial partition layout:"
parted -m --script "$loopdev" unit s print

# Simulate partition creation logic from mount_image.sh
# Note: Using 5MB for testing instead of production 512MB for speed
storage_partition_mb=5
rootpartition=2

echo ""
echo "=== Simulating storage partition creation (${storage_partition_mb}MB) ==="

storage_partition=$((rootpartition + 1))

# Get the end of the root partition
rootfs_partend_sector=$(parted -m --script "${loopdev}" unit s print | grep "^${rootpartition}:" | awk -F ":" '{print $3}' | tr -d 's')

echo "Root partition ends at sector: $rootfs_partend_sector"

# Calculate start of storage partition (1MB = 2048 sectors after root partition)
storage_partstart=$((rootfs_partend_sector + 2048))

# Calculate size in sectors (assuming 512 byte sectors)
storage_size_sectors=$((storage_partition_mb * 2048))
storage_partend=$((storage_partstart + storage_size_sectors))

echo "Creating partition ${storage_partition} from sector ${storage_partstart} to ${storage_partend}"

# Create the partition
parted --script "${loopdev}" unit s mkpart primary ext4 ${storage_partstart} ${storage_partend}

# Refresh partition table
partprobe "${loopdev}"
sync
sleep 1

echo ""
echo "Final partition layout:"
parted -m --script "$loopdev" unit s print

# Format the new partition
echo ""
echo "Formatting storage partition as ext4..."
mkfs.ext4 -F "${loopdev}p${storage_partition}" -L photon-storage >/dev/null 2>&1

# Verify the partition
echo ""
echo "=== Verification ==="

# Check if partition exists
if [ -b "${loopdev}p${storage_partition}" ]; then
    echo "✓ Partition ${storage_partition} created successfully"
else
    echo "✗ Partition ${storage_partition} NOT created"
    losetup -d "$loopdev"
    rm -f "$TEST_IMG"
    exit 1
fi

# Check filesystem
fs_type=$(blkid -o value -s TYPE "${loopdev}p${storage_partition}")
if [ "$fs_type" = "ext4" ]; then
    echo "✓ Partition formatted as ext4"
else
    echo "✗ Partition NOT formatted as ext4 (got: $fs_type)"
    losetup -d "$loopdev"
    rm -f "$TEST_IMG"
    exit 1
fi

# Check label
fs_label=$(blkid -o value -s LABEL "${loopdev}p${storage_partition}")
if [ "$fs_label" = "photon-storage" ]; then
    echo "✓ Partition labeled correctly"
else
    echo "✗ Partition label incorrect (got: $fs_label)"
    losetup -d "$loopdev"
    rm -f "$TEST_IMG"
    exit 1
fi

# Show partition info
echo ""
echo "Storage partition info:"
echo "  Device: ${loopdev}p${storage_partition}"
echo "  Type: $fs_type"
echo "  Label: $fs_label"
echo "  Size: ${storage_partition_mb}MB"

echo ""
echo "=== All tests passed! ==="

# Cleanup
losetup -d "$loopdev"
rm -f "$TEST_IMG"
