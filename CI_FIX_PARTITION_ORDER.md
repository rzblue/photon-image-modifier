# CI Fix: Partition Creation Order

## Problem

The CI workflow was failing with error:
```
Error: The location 5879743 is outside of the device /dev/loop0.
```

## Root Cause

The `create_storage_partition.sh` script was attempting to create a partition **before** extending the image file. Since the upstream `photonvision/photon-image-runner` action shrinks the image to save space, there was no room for the new partition.

## Solution

Reordered operations in `create_storage_partition.sh` to:
1. **First**: Extend the image file to accommodate the new partition
2. **Then**: Create the partition in the newly available space

## Changes

### Before (Broken)
```bash
1. Calculate partition location (sectors 5879743-6928319)
2. Try to create partition ❌ FAILS - outside device boundary
3. (Never reached) Format partition
4. (Never reached) Extend image file
5. (Never reached) Fix GPT header
```

### After (Fixed)
```bash
1. Calculate partition location (sectors 5879743-6928319)
2. Extend image file to ~3.5GB ✅
3. Re-attach loop device ✅
4. Fix GPT secondary header ✅
5. Create partition ✅ (now has space!)
6. Format partition ✅
```

## Technical Details

### Image Size Calculation
```bash
# Add 1MB padding after partition end
NEW_SIZE_SECTORS = STORAGE_PARTEND + SECTORS_PER_MB

# For GPT, add 33 sectors for secondary header
if GPT:
    NEW_SIZE_BYTES += 33 * SECTOR_SIZE
```

### Key Operations Moved

**Lines 111-140 moved to 77-113:**
- Detach loop device
- Extend image with `truncate -s`
- Re-attach loop device  
- Fix GPT with `sgdisk -e`

**Lines 83 moved to 118:**
- Create partition with `parted mkpart`

## Testing

Created `test_partition_logic.sh` to validate operation order:
```bash
✓ Image extension happens BEFORE partition creation
✓ GPT fix happens BEFORE partition creation
✓ Partition creation happens BEFORE formatting
```

## Impact

- ✅ Fixes CI failure
- ✅ No functional changes to end result
- ✅ Same partition layout, just created in correct order
- ✅ All validation preserved

## GPT Warnings

The GPT corruption warnings seen in CI are pre-existing from upstream:
```
Warning! One or more CRCs don't match. You should repair the disk!
```

These are expected after image shrinking and are properly fixed by `sgdisk -e`.
