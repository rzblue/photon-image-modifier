#!/bin/bash

# Exit on errors, print commands
# Note: +u allows unset variables for compatibility with the chroot environment
set -ex +u

echo "Configuring read-only root filesystem with direct mount for PhotonVision storage"

# Create the mount point for the storage partition
mkdir -p /opt/photonvision/photon-storage

# Modify fstab to configure read-only root and storage mount
# First, backup the original fstab
cp /etc/fstab /etc/fstab.backup

# Find the root device in fstab
root_device=$(grep -E '[[:space:]]/[[:space:]]' /etc/fstab | grep -v '^#' | head -1 | awk '{print $1}')
echo "Root device from fstab: ${root_device}"

# Get the base device name (without partition number)
if [[ $root_device =~ (.+)[0-9]+$ ]]; then
    base_device="${BASH_REMATCH[1]}"
elif [[ $root_device =~ (.+)p[0-9]+$ ]]; then
    base_device="${BASH_REMATCH[1]}"
else
    base_device="${root_device}"
fi

# Determine the storage partition device (partition 3)
if [[ $root_device =~ p[0-9]+$ ]]; then
    # Device names like /dev/mmcblk0p2 -> /dev/mmcblk0p3
    storage_device="${base_device}p3"
else
    # Device names like /dev/sda2 -> /dev/sda3
    storage_device="${base_device}3"
fi

echo "Storage partition will be: ${storage_device}"

# Add ro option to root partition
# Find the root partition line and add ro option if not already present
sed -i 's|\([[:space:]]/[[:space:]].*[[:space:]]defaults\)|\1,ro|' /etc/fstab
# Also handle case where there might be other options already
sed -i 's|\([[:space:]]/[[:space:]].*[[:space:]]errors=remount-ro\)|\1,ro|' /etc/fstab

# Verify that ro option was added
if ! grep -E '[[:space:]]/[[:space:]].*ro' /etc/fstab | grep -v '^#' >/dev/null; then
    echo "Warning: Could not verify 'ro' option was added to root filesystem"
    echo "Current fstab root entry:"
    grep -E '[[:space:]]/[[:space:]]' /etc/fstab | grep -v '^#'
fi

# Add the storage partition mount directly at /opt/photonvision/photon-storage
echo "# PhotonVision writable storage directory" >> /etc/fstab
echo "${storage_device} /opt/photonvision/photon-storage ext4 defaults,noatime 0 2" >> /etc/fstab

echo "Read-only root filesystem configuration complete"
echo "fstab contents:"
cat /etc/fstab
