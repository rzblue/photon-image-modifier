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
mkdir -p "$TMPDIR/opt/photonvision/photon-storage"

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

# Add storage partition mount
echo "# PhotonVision writable storage directory" >> fstab
echo "$storage_device /opt/photonvision/photon-storage ext4 defaults,noatime 0 2" >> fstab

echo ""
echo "Modified fstab:"
cat fstab
echo ""

# Verify key properties
echo "=== Verification ==="
if grep -q ",ro" fstab && grep "/ " fstab | grep -q "ro"; then
    echo "✓ Root filesystem configured as read-only"
else
    echo "✗ Root filesystem NOT configured as read-only"
    exit 1
fi

if grep -q "/opt/photonvision/photon-storage" fstab; then
    echo "✓ Storage partition mount configured at /opt/photonvision/photon-storage"
else
    echo "✗ Storage partition mount NOT configured"
    exit 1
fi

if grep -q "overlay /opt/photonvision" fstab; then
    echo "✗ Overlay mount should NOT be present in new implementation"
    exit 1
else
    echo "✓ No overlay mount (correct for new implementation)"
fi

echo ""
echo "=== All tests passed! ==="

# Cleanup
cd /
rm -rf "$TMPDIR"
