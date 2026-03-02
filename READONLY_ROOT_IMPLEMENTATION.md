# Read-Only Root Filesystem Implementation for Orange Pi 5

## Overview

This implementation modifies the Orange Pi 5 image build process to create a read-only root filesystem with a writable overlay mount for PhotonVision data storage.

## Changes Made

### 1. configure_readonly_root.sh (New File)

This script configures the system for read-only root operation:

- **Modifies /etc/fstab** to set the root filesystem as read-only (adds `ro` option)
- **Adds storage partition mount** at `/mnt/photon-storage` (partition 3)
- **Configures overlay mount** for `/opt/photonvision` using:
  - Lower layer: `/opt/photonvision` (read-only)
  - Upper layer: `/mnt/photon-storage/photonvision-upper` (writable)
  - Work directory: `/mnt/photon-storage/photonvision-work` (for overlay operations)
- **Creates systemd service** (`photonvision-overlay-init.service`) to initialize overlay directories on first boot

### 2. install_opi5.sh (Modified)

Added configuration steps for Orange Pi 5 builds:

- Calls `configure_readonly_root.sh` to set up fstab and systemd service

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
│  │   /opt/photonvision (lower)    │     │
│  │   - photonvision.jar           │     │
│  │   - image-version.json         │     │
│  └────────────────────────────────┘     │
└─────────────────────────────────────────┘
                   │
                   │ (overlay mount)
                   ▼
┌─────────────────────────────────────────┐
│    Storage Partition (RW, Partition 3)  │
│    Mounted at: /mnt/photon-storage      │
│                                          │
│  ┌────────────────────────────────┐     │
│  │   photonvision-upper/          │     │
│  │   - Configuration files        │     │
│  │   - Database                   │     │
│  │   - Logs                       │     │
│  └────────────────────────────────┘     │
│                                          │
│  ┌────────────────────────────────┐     │
│  │   photonvision-work/           │     │
│  │   (overlay working directory)  │     │
│  └────────────────────────────────┘     │
└─────────────────────────────────────────┘
                   │
                   ▼
           /opt/photonvision
         (unified overlay view)
```

## Benefits

1. **System Integrity**: Read-only root prevents accidental or malicious system modifications
2. **Crash Resilience**: Improper shutdowns won't corrupt the system partition
3. **Data Separation**: User data and configuration are isolated on a separate partition
4. **Easy Recovery**: System can be reset by reformatting the storage partition
5. **Longevity**: Reduces wear on flash storage by minimizing writes to the system partition

## Storage Partition Details

- **Size**: 512MB (configurable)
- **Partition Number**: 3 (after boot and root partitions)
- **Filesystem**: ext4
- **Label**: photon-storage
- **Mount Point**: /mnt/photon-storage

## Build Process

1. **photonvision/photon-image-runner** action downloads base image and runs chroot commands
2. **install_opi5.sh** runs in chroot, calls **configure_readonly_root.sh** to set up fstab
3. **photonvision/photon-image-runner** shrinks root partition and creates base image
4. **create_storage_partition.sh** runs as workflow step to add partition 3
5. Image is compressed and uploaded as artifact

## Testing

Test scripts to verify the implementation:

1. **test_readonly_config.sh**: Tests fstab modification and systemd service creation
2. **test_partition_creation.sh**: Tests partition creation and formatting logic (now deprecated)
3. **create_storage_partition.sh**: Actual production script (tested successfully)

## Compatibility

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
