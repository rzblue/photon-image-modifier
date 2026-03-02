# Verification Guide for Read-Only Root Filesystem Implementation

## Overview

This guide explains how to verify that the read-only root filesystem implementation works correctly when the Orange Pi 5 images are built in CI.

## Pre-requisites

- Access to the built image artifact (photonvision_opi5.img.xz)
- A Linux system with the following tools:
  - xz (for decompression)
  - parted (for partition inspection)
  - losetup (for mounting images)
  - mount (for filesystem operations)
  - fdisk or gdisk (for partition table viewing)

## Verification Steps

### 1. Download the Image

Download the built image artifact from the CI workflow:

```bash
# After CI completes, download the artifact
# Example: photonvision_opi5.img.xz
```

### 2. Decompress the Image

```bash
xz -d photonvision_opi5.img.xz
```

### 3. Inspect Partition Table

```bash
# View partition layout
parted photonvision_opi5.img unit MB print

# OR use fdisk
fdisk -l photonvision_opi5.img
```

**Expected Output:**
- Partition 1: Boot partition (~16-512MB)
- Partition 2: Root partition (variable size, shrunk to fit)
- Partition 3: Storage partition (512MB, ext4, labeled "photon-storage")

### 4. Mount and Verify Filesystems

```bash
# Setup loop device
sudo losetup -fP photonvision_opi5.img
LOOPDEV=$(losetup -j photonvision_opi5.img | cut -d: -f1)

# View all partitions
lsblk $LOOPDEV

# Check partition 3 details
sudo blkid ${LOOPDEV}p3

# Expected:
# - TYPE="ext4"
# - LABEL="photon-storage"
```

### 5. Verify fstab Configuration

```bash
# Mount root partition
sudo mkdir -p /tmp/opi5_root
sudo mount ${LOOPDEV}p2 /tmp/opi5_root

# Check fstab
cat /tmp/opi5_root/etc/fstab
```

**Expected fstab entries:**

```bash
# Root partition should have 'ro' option
# Example: UUID=xxx / ext4 defaults,ro 0 1

# Storage partition mount at /opt/photonvision/photon-storage
# Example: /dev/mmcblk0p3 /opt/photonvision/photon-storage ext4 defaults,noatime 0 2
```

### 6. Verify Directory Structure

```bash
# Check that PhotonVision directory exists
ls -la /tmp/opi5_root/opt/photonvision/

# Check that storage mount point exists
ls -ld /tmp/opi5_root/opt/photonvision/photon-storage/

# Expected: Both directories should exist
```

### 7. Cleanup

```bash
# Unmount and detach
sudo umount /tmp/opi5_root
sudo losetup -d $LOOPDEV
```

## Automated Verification Script

Here's a script that automates the verification:

```bash
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

# Check partitions
echo ""
echo "=== Partition Table ==="
sudo parted -m --script "$LOOPDEV" unit MB print

# Check for partition 3
if [ ! -b "${LOOPDEV}p3" ]; then
    echo "ERROR: Partition 3 (storage) not found!"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Partition 3 exists"

# Check partition 3 filesystem
FS_TYPE=$(sudo blkid -o value -s TYPE "${LOOPDEV}p3")
FS_LABEL=$(sudo blkid -o value -s LABEL "${LOOPDEV}p3")

if [ "$FS_TYPE" != "ext4" ]; then
    echo "ERROR: Partition 3 is not ext4 (found: $FS_TYPE)"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Partition 3 is ext4"

if [ "$FS_LABEL" != "photon-storage" ]; then
    echo "ERROR: Partition 3 label is not 'photon-storage' (found: $FS_LABEL)"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Partition 3 has correct label"

# Mount root partition
MOUNT_POINT=$(mktemp -d)
sudo mount "${LOOPDEV}p2" "$MOUNT_POINT"

# Check fstab
echo ""
echo "=== fstab Configuration ==="
if ! grep -q "ro" "$MOUNT_POINT/etc/fstab"; then
    echo "ERROR: 'ro' option not found in fstab"
    sudo umount "$MOUNT_POINT"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Root filesystem configured as read-only"

if ! grep -q "/opt/photonvision/photon-storage" "$MOUNT_POINT/etc/fstab"; then
    echo "ERROR: Storage partition mount not found in fstab"
    sudo umount "$MOUNT_POINT"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Storage partition mount configured at /opt/photonvision/photon-storage"

if grep -q "overlay /opt/photonvision" "$MOUNT_POINT/etc/fstab"; then
    echo "ERROR: Overlay mount found (should not be present)"
    sudo umount "$MOUNT_POINT"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ No overlay mount (direct mount implementation)"

# Check directories
if [ ! -d "$MOUNT_POINT/opt/photonvision" ]; then
    echo "ERROR: /opt/photonvision directory not found"
    sudo umount "$MOUNT_POINT"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ PhotonVision directory exists"

if [ ! -d "$MOUNT_POINT/opt/photonvision/photon-storage" ]; then
    echo "ERROR: /opt/photonvision/photon-storage mount point not found"
    sudo umount "$MOUNT_POINT"
    sudo losetup -d "$LOOPDEV"
    exit 1
fi
echo "✓ Storage mount point exists"

# Cleanup
sudo umount "$MOUNT_POINT"
sudo losetup -d "$LOOPDEV"
rmdir "$MOUNT_POINT"

echo ""
echo "=== All Verifications Passed! ==="
```

Save this as `verify_readonly_root.sh` and run:

```bash
chmod +x verify_readonly_root.sh
./verify_readonly_root.sh photonvision_opi5.img
```

## Testing on Physical Hardware

To test on actual Orange Pi 5 hardware:

1. Flash the image to an SD card or eMMC
2. Boot the Orange Pi 5
3. Log in (user: pi, password: raspberry OR user: photon, password: vision)
4. Verify read-only root:
   ```bash
   mount | grep "on / "
   # Should show: ... (ro,...)
   
   touch /test_write
   # Should fail with: touch: cannot touch '/test_write': Read-only file system
   ```

5. Verify storage partition:
   ```bash
   df -h | grep photon-storage
   # Should show partition mounted at /opt/photonvision/photon-storage
   
   ls -la /opt/photonvision/photon-storage/
   # Should be empty on first boot
   ```

6. Test writable storage:
   ```bash
   # Create a test file in storage
   touch /opt/photonvision/photon-storage/test_file
   # Should succeed
   
   # Verify it's actually on the storage partition
   ls -la /opt/photonvision/photon-storage/
   # Should show test_file
   ```

7. Test PhotonVision:
   ```bash
   sudo systemctl status photonvision
   # Should show running
   
   # Access web UI at http://<ip>:5800
   # Make configuration changes and verify they persist across reboots
   # All writable data should go to /opt/photonvision/photon-storage/
   ```

## Expected Behavior

✓ System boots successfully  
✓ Root filesystem is read-only  
✓ Storage partition is mounted at /opt/photonvision/photon-storage  
✓ PhotonVision can read/write to photon-storage subdirectory  
✓ System can reboot without filesystem corruption  
✓ Configuration persists across reboots  

## Troubleshooting

If verification fails:

1. **Partition 3 doesn't exist**: Check create_storage_partition.sh ran correctly in workflow
2. **Wrong filesystem type**: Check mkfs.ext4 command in create_storage_partition.sh
3. **fstab missing entries**: Check configure_readonly_root.sh ran in chroot
4. **Boot failures**: Check fstab syntax, verify mount point directory exists
5. **Storage not writable**: Verify partition is mounted, check mount options

## CI Integration

To integrate this verification into CI:

```yaml
- name: Verify read-only root configuration
  run: |
    xz -d photonvision_opi5.img.xz
    chmod +x verify_readonly_root.sh
    sudo ./verify_readonly_root.sh photonvision_opi5.img
```
