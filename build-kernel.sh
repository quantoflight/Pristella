#!/bin/bash

KERNEL_DIR="$HOME/Pristella/kernel/linux-6.12"
ROOTFS_DIR="$HOME/Pristella/rootfs"
CLEAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=true
            shift
            ;;
        --kernel_path=*)
            ROOTFS_DIR="${1#*=}"
            shift
            ;;
        --kernel_mod_path=*)
            ROOTFS_DIR="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown arg: $1"
            exit 1
            ;;
    esac
done

cd "$KERNEL_DIR" || { echo "Error: kernel folder not found at $KERNEL_DIR"; exit 1; }

if [ "$CLEAN" = true ]; then
    echo "[info] Cleaning kernel source tree..."
    make clean
    make mrproper
fi

echo "[info] Configuring kernel..."
./scripts/config --disable WERROR
./scripts/config --enable DRM_I915
./scripts/config --enable DRM_I915_GVT
./scripts/config --enable DRM_AMDGPU
./scripts/config --enable DRM_NOUVEAU
./scripts/config --enable DRM_SIMPLEDRM
./scripts/config --enable DRM_FBDEV_EMULATION
./scripts/config --enable EFI
./scripts/config --enable EFI_STUB
./scripts/config --disable LOCALVERSION_AUTO
./scripts/config --set-str LOCALVERSION "-Pristella"
./scripts/config --enable SATA_AHCI
./scripts/config --enable BLK_DEV_NVME
./scripts/config --enable EXT4_FS
./scripts/config --enable USB_SUPPORT
./scripts/config --enable USB_XHCI_HCD
./scripts/config --enable USB_HID
./scripts/config --enable HID_GENERIC
./scripts/config --enable NET_VENDOR_REALTEK
./scripts/config --enable R8169
./scripts/config --enable NET_VENDOR_INTEL
./scripts/config --enable E1000
./scripts/config --enable E1000E
./scripts/config --enable VFAT_FS
./scripts/config --enable FAT_FS
./scripts/config --enable DEVTMPFS
./scripts/config --enable DEVTMPFS_MOUNT

if ! grep -q "std=gnu11" drivers/firmware/efi/libstub/Makefile; then
    sed -i 's/cflags-$(CONFIG_X86)\t\t+= -m$(BITS) -D__KERNEL__/cflags-$(CONFIG_X86)\t\t+= -m$(BITS) -D__KERNEL__ -std=gnu11/' drivers/firmware/efi/libstub/Makefile
fi

make olddefconfig

# Сборка
echo "[info] Building kernel..."
make -j$(nproc) \
    KCFLAGS="-std=gnu11" \
    CC='gcc -std=gnu11'

if [ ! -f "arch/x86/boot/bzImage" ]; then
    echo "Error: bzImage not found after build!"
    exit 1
fi

echo "[info] Installing modules to $ROOTFS_DIR/lib/modules/..."
make modules_install INSTALL_MOD_PATH="$ROOTFS_DIR"

echo "[info] Generating depmod for target system..."
depmod -b "$ROOTFS_DIR" $(make kernelrelease)

echo "[info] Copying bzImage to $ROOTFS_DIR/boot/..."
mkdir -p "$ROOTFS_DIR/boot"
cp arch/x86/boot/bzImage "$ROOTFS_DIR/boot/bzImage"

echo "[info] Done!"
echo "Kernel version: $(make kernelrelease)"
echo "Kernel image:   $ROOTFS_DIR/boot/bzImage"
echo "Modules:        $ROOTFS_DIR/lib/modules/$(make kernelrelease)"