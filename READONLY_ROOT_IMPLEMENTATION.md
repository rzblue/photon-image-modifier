# Read-Only Root Filesystem Implementation for Orange Pi 5

## Overview

This implementation modifies the Orange Pi 5 image build process to create a read-only root filesystem with a writable storage directory for PhotonVision data.

## Changes Made

### 1. configure_readonly_root.sh (New File)

This script configures the system for read-only root operation:

- **Modifies /etc/fstab** to set the root filesystem as read-only (adds `ro` option)
- **Creates mount point** at `/opt/photonvision/photon-storage`
- **Adds storage partition mount** directly at `/opt/photonvision/photon-storage` (partition 3)
- **Simple and straightforward**: No overlay complexity, just a direct mount of the writable partition

### 2. install_opi5.sh (Modified)

Added configuration steps for Orange Pi 5 builds:

- Calls `configure_readonly_root.sh` to set up fstab

### 3. create_storage_partition.sh (New File)

Post-build script that creates the storage partition:

- Runs AFTER `photonvision/photon-image-runner` action completes
- Attaches the built image as a loop device
- Creates partition 3 at the end of the image
- Formats as ext4 with label `photon-storage`
- Extends the image file to accommodate the new partition
- Fixes GPT secondary header if needed

### 4. .github/workflows/main.yml (Modified)

Added workflow step for Orange Pi 5 images:

- Runs AFTER `photonvision/photon-image-runner` completes
- Calls `create_storage_partition.sh` to add partition 3
- Only runs for images built with `install_opi5.sh`
- Executes BEFORE image compression

## Architecture

```
┌─────────────────────────────────────────┐
│         Root Filesystem (RO)             │
│                                          │
│  ┌────────────────────────────────┐     │
│  │   /opt/photonvision            │     │
│  │   - photonvision.jar           │     │
│  │   - image-version.json         │     │
│  │   - other read-only files      │     │
│  │                                │     │
│  │   ┌──────────────────────┐     │     │
│  │   │  photon-storage/     │◄────┼─────┼─── Mount Point (writable)
│  │   │  (mount point)       │     │     │
│  │   └──────────────────────┘     │     │
│  └────────────────────────────────┘     │
└─────────────────────────────────────────┘
                   │
                   │ (direct mount)
                   ▼
┌─────────────────────────────────────────┐
│    Storage Partition (RW, partition 3)   │
│                                          │
│  - PhotonVision configuration            │
│  - Logs                                  │
│  - User data                             │
│  - Calibration data                      │
└─────────────────────────────────────────┘
```

## Benefits

1. **System Integrity**: Root filesystem is mounted read-only, preventing accidental corruption
2. **Crash Resilience**: Power loss won't corrupt the system partition
3. **Data Separation**: User data and configuration are isolated on a separate partition
4. **Easy Recovery**: System can be reset by reformatting the storage partition
5. **Longevity**: Reduces wear on flash storage by minimizing writes to the system partition
6. **Simplicity**: Direct mount is easier to understand and maintain than overlayfs
7. **PhotonVision Integration**: PhotonVision can write directly to `/opt/photonvision/photon-storage/`

## Storage Partition Details

- **Size**: 512MB (configurable)
- **Partition Number**: 3 (after boot and root partitions)
- **Filesystem**: ext4
- **Label**: photon-storage
- **Mount Point**: /opt/photonvision/photon-storage

## Build Process

1. **photonvision/photon-image-runner** action downloads base image and runs chroot commands
2. **install_opi5.sh** runs in chroot, calls **configure_readonly_root.sh** to set up fstab
3. **photonvision/photon-image-runner** shrinks root partition and creates base image
4. **create_storage_partition.sh** runs as workflow step to add partition 3
5. Image is compressed and uploaded as artifact

## Testing

Test scripts to verify the implementation:

1. **test_readonly_config.sh**: Tests fstab modification and mount configuration
2. **create_storage_partition.sh**: Actual production script (tested successfully)

## Compatibility

- Only affects Orange Pi 5 variants (opi5, opi5b, opi5plus, opi5pro, opi5max, rock5c)
- Other image builds remain unchanged
- Conditional workflow step ensures backward compatibility

## First Boot Sequence

1. System boots with read-only root filesystem
2. Storage partition (`/dev/mmcblk0p3`) automatically mounts at `/opt/photonvision/photon-storage`
3. PhotonVision starts and can write directly to `/opt/photonvision/photon-storage/`

## PhotonVision Integration

PhotonVision should be configured to store all writable data in `/opt/photonvision/photon-storage/`:
- Configuration files
- Logs
- User settings
- Camera calibration data
- Pipeline configurations

The rest of `/opt/photonvision/` remains read-only on the system partition.

- Only affects Orange Pi 5 variants (opi5, opi5b, opi5plus, opi5pro, opi5max, rock5c)
- Other image builds remain unchanged
- Conditional workflow step ensures backward compatibility

## First Boot Sequence

1. System boots with read-only root filesystem
2. Storage partition is mounted at `/mnt/photon-storage`
3. `photonvision-overlay-init.service` runs and creates overlay directories if they don't exist
4. Overlay mount for `/opt/photonvision` is established
5. PhotonVision starts and can read/write to `/opt/photonvision` (writes go to storage partition)

## Future Improvements

- Add automatic expansion of storage partition to fill available space
- Implement configuration management tools for read-only systems
- Add monitoring for storage partition capacity
