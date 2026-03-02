#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

echo "Configuring read-only root filesystem with overlay mount for PhotonVision storage"

# Create the mount point for the storage partition
mkdir -p /mnt/photon-storage

# Modify fstab to configure read-only root and overlay mount
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

# Add the storage partition mount
echo "# PhotonVision writable storage partition" >> /etc/fstab
echo "${storage_device} /mnt/photon-storage ext4 defaults,noatime 0 2" >> /etc/fstab

# Add overlay mount for /opt/photonvision
echo "# Overlay mount for PhotonVision data directory" >> /etc/fstab
echo "overlay /opt/photonvision overlay lowerdir=/opt/photonvision,upperdir=/mnt/photon-storage/photonvision-upper,workdir=/mnt/photon-storage/photonvision-work,x-systemd.requires=/mnt/photon-storage 0 0" >> /etc/fstab

# Create a systemd service to initialize the overlay directories on first boot
cat > /etc/systemd/system/photonvision-overlay-init.service << 'EOF'
[Unit]
Description=Initialize PhotonVision overlay directories
After=mnt-photon\x2dstorage.mount
Before=opt-photonvision.mount
ConditionPathExists=!/mnt/photon-storage/photonvision-upper

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /mnt/photon-storage/photonvision-upper
ExecStart=/bin/mkdir -p /mnt/photon-storage/photonvision-work
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/photonvision-overlay-init.service
systemctl enable photonvision-overlay-init.service

echo "Read-only root filesystem configuration complete"
echo "fstab contents:"
cat /etc/fstab
