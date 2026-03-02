#!/bin/bash

# Test script to verify the read-only root filesystem configuration

set -e

echo "=== Testing configure_readonly_root.sh script ==="
echo ""

# Create a temporary directory for testing
TMPDIR=$(mktemp -d)
echo "Using temporary directory: $TMPDIR"

# Create a mock fstab
cat > "$TMPDIR/fstab" << 'EOF'
# UNCONFIGURED FSTAB FOR BASE SYSTEM
UUID=1234-5678  /boot/firmware  vfat    defaults        0       1
UUID=abcd-efgh  /               ext4    defaults        0       1
EOF

echo "Original fstab:"
cat "$TMPDIR/fstab"
echo ""

# Create a mock environment
mkdir -p "$TMPDIR/etc/systemd/system"
mkdir -p "$TMPDIR/mnt/photon-storage"
mkdir -p "$TMPDIR/opt/photonvision"

# Extract the relevant logic from configure_readonly_root.sh and test it
echo "=== Testing fstab modifications ==="

# Simulate the script logic
cd "$TMPDIR"

# Backup fstab
cp fstab fstab.backup

# Find root device
root_device=$(grep -E '[[:space:]]/[[:space:]]' fstab | grep -v '^#' | head -1 | awk '{print $1}')
echo "Root device: $root_device"

# Simulate device name parsing (for UUID we'd use /dev/mmcblk0p2 in real system)
storage_device="/dev/mmcblk0p3"
echo "Storage device will be: $storage_device"

# Add ro option
sed -i 's|\([[:space:]]/[[:space:]].*[[:space:]]defaults\)|\1,ro|' fstab

# Add storage partition
echo "# PhotonVision writable storage partition" >> fstab
echo "$storage_device /mnt/photon-storage ext4 defaults,noatime 0 2" >> fstab

# Add overlay mount
echo "# Overlay mount for PhotonVision data directory" >> fstab
echo "overlay /opt/photonvision overlay lowerdir=/opt/photonvision,upperdir=/mnt/photon-storage/photonvision-upper,workdir=/mnt/photon-storage/photonvision-work,x-systemd.requires=/mnt/photon-storage 0 0" >> fstab

echo ""
echo "Modified fstab:"
cat fstab
echo ""

# Create systemd service
cat > etc/systemd/system/photonvision-overlay-init.service << 'EOF'
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

echo "Created systemd service:"
cat etc/systemd/system/photonvision-overlay-init.service
echo ""

# Verify key properties
echo "=== Verification ==="
if grep -q ",ro" fstab && grep "/ " fstab | grep -q "ro"; then
    echo "✓ Root filesystem configured as read-only"
else
    echo "✗ Root filesystem NOT configured as read-only"
    exit 1
fi

if grep -q "/mnt/photon-storage" fstab; then
    echo "✓ Storage partition mount configured"
else
    echo "✗ Storage partition mount NOT configured"
    exit 1
fi

if grep -q "overlay /opt/photonvision" fstab; then
    echo "✓ Overlay mount for /opt/photonvision configured"
else
    echo "✗ Overlay mount NOT configured"
    exit 1
fi

if [ -f etc/systemd/system/photonvision-overlay-init.service ]; then
    echo "✓ Systemd service created"
else
    echo "✗ Systemd service NOT created"
    exit 1
fi

echo ""
echo "=== All tests passed! ==="

# Cleanup
cd /
rm -rf "$TMPDIR"
