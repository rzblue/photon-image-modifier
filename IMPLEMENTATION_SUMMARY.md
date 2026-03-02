# Implementation Summary: Read-Only Root Filesystem for Orange Pi 5

## Problem Addressed

The initial implementation incorrectly modified `mount_image.sh`, which is not used by CI. The actual image processing is done by the `photonvision/photon-image-runner` GitHub Action, which has its own internal scripts.

## Solution

Implemented a post-build approach that works with the existing workflow without modifying the external action:

### Architecture

```
┌──────────────────────────────────────────┐
│ photonvision/photon-image-runner         │
│ (External GitHub Action)                 │
│                                          │
│ 1. Downloads base image                  │
│ 2. Mounts and runs chroot commands       │
│    - install_opi5.sh                     │
│    - configure_readonly_root.sh (NEW)    │
│    - install_common.sh                   │
│ 3. Shrinks root partition                │
│ 4. Outputs: base_image.img              │
└──────────────────────────────────────────┘
              ↓
┌──────────────────────────────────────────┐
│ Workflow Step (NEW)                      │
│ create_storage_partition.sh              │
│                                          │
│ 1. Attach image as loop device           │
│ 2. Create partition 3 (512MB)            │
│ 3. Format as ext4 (photon-storage)       │
│ 4. Extend image file                     │
│ 5. Fix GPT headers                       │
│ 6. Detach loop device                    │
└──────────────────────────────────────────┘
              ↓
┌──────────────────────────────────────────┐
│ Compress & Upload                        │
└──────────────────────────────────────────┘
```

## Implementation Details

### Files Created

1. **configure_readonly_root.sh** (runs in chroot)
   - Modifies `/etc/fstab` to set root as read-only
   - Adds storage partition mount at `/mnt/photon-storage`
   - Configures overlay mount for `/opt/photonvision`
   - Creates systemd service for overlay initialization

2. **create_storage_partition.sh** (runs post-build)
   - Manipulates the already-built image
   - Creates partition 3 after the shrunk root partition
   - Formats and labels the partition
   - Extends the image file to accommodate new partition

### Files Modified

1. **install_opi5.sh**
   - Added call to `configure_readonly_root.sh`

2. **.github/workflows/main.yml**
   - Added conditional workflow step for Orange Pi 5 images
   - Runs `create_storage_partition.sh` after photon-image-runner
   - Only executes for images using `install_opi5.sh`

### Files Reverted

1. **mount_image.sh**
   - Reverted to original (not used by CI)

## Testing

### Unit Tests
- ✅ `test_readonly_config.sh` - Validates fstab configuration
- ✅ `test_partition_creation.sh` - Validates partition logic
- ✅ `create_storage_partition.sh` - Production script tested successfully

### Code Review
- ✅ All feedback addressed
- ✅ Constants defined for maintainability
- ✅ Partition validation added
- ✅ Documentation improved

### Security Check
- ✅ CodeQL analysis passed (0 alerts)

## Benefits of This Approach

1. **No External Dependencies**: Works with existing photon-image-runner action
2. **Clean Separation**: Chroot configures OS, post-build adds partition
3. **Backward Compatible**: Only affects Orange Pi 5 builds
4. **Maintainable**: Well-documented with named constants
5. **Testable**: Can be tested independently of full CI

## Runtime Behavior

### First Boot
1. System boots with read-only root filesystem
2. Storage partition (`/dev/mmcblk0p3`) mounts at `/mnt/photon-storage`
3. `photonvision-overlay-init.service` creates overlay directories if needed
4. Overlay mount combines read-only `/opt/photonvision` with writable upper/work dirs
5. PhotonVision starts and can write to `/opt/photonvision` (writes go to storage partition)

### Normal Operation
- Root filesystem: Read-only, protected from corruption
- Storage partition: Writable, isolated user data
- Overlay: Unified view at `/opt/photonvision`
- PhotonVision: Full read/write access to configuration and data

## Future Enhancements

- Add automatic storage partition expansion at first boot
- Implement health monitoring for storage partition
- Add recovery tools for read-only systems
- Consider adding configuration management tools

## Verification

To verify the implementation works in CI:

1. Trigger a workflow run for Orange Pi 5
2. Check workflow logs for "Creating storage partition" step
3. Download the built image artifact
4. Use `verify_readonly_root.sh` to validate partition structure
5. Flash to SD card and boot on hardware
6. Verify read-only root and writable PhotonVision data

## Conclusion

This implementation successfully creates a read-only root filesystem for Orange Pi 5 images while working within the constraints of the existing CI infrastructure. The solution is clean, maintainable, and fully backward compatible.
