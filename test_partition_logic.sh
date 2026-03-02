#!/bin/bash

# Test script to validate the partition creation logic
# This verifies the order of operations is correct

set -e

echo "=== Testing Partition Creation Logic ==="
echo ""

# Read the create_storage_partition.sh script
SCRIPT="/home/runner/work/photon-image-modifier/photon-image-modifier/create_storage_partition.sh"

# Check that image extension happens before partition creation
echo "Checking operation order in create_storage_partition.sh..."

# Get line numbers of key operations
EXTEND_LINE=$(grep -n "truncate -s" "$SCRIPT" | cut -d: -f1)
MKPART_LINE=$(grep -n "parted --script.*mkpart" "$SCRIPT" | cut -d: -f1)
MKFS_LINE=$(grep -n "mkfs.ext4" "$SCRIPT" | cut -d: -f1)
SGDISK_LINE=$(grep -n "sgdisk -e" "$SCRIPT" | cut -d: -f1)

echo "  truncate (extend image): line $EXTEND_LINE"
echo "  sgdisk (fix GPT): line $SGDISK_LINE"
echo "  parted mkpart (create partition): line $MKPART_LINE"
echo "  mkfs.ext4 (format partition): line $MKFS_LINE"
echo ""

# Verify order is correct
ERRORS=0

if [ "$EXTEND_LINE" -lt "$MKPART_LINE" ]; then
    echo "✓ Image extension happens BEFORE partition creation"
else
    echo "✗ ERROR: Image extension happens AFTER partition creation"
    ERRORS=$((ERRORS + 1))
fi

if [ "$SGDISK_LINE" -lt "$MKPART_LINE" ]; then
    echo "✓ GPT fix happens BEFORE partition creation"
else
    echo "✗ ERROR: GPT fix happens AFTER partition creation"
    ERRORS=$((ERRORS + 1))
fi

if [ "$MKPART_LINE" -lt "$MKFS_LINE" ]; then
    echo "✓ Partition creation happens BEFORE formatting"
else
    echo "✗ ERROR: Partition creation happens AFTER formatting"
    ERRORS=$((ERRORS + 1))
fi

echo ""

if [ $ERRORS -eq 0 ]; then
    echo "=== All operation order checks passed! ==="
    exit 0
else
    echo "=== $ERRORS operation order check(s) failed ==="
    exit 1
fi
