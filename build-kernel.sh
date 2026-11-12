#!/bin/bash

cd ~/Pristella/kernel/linux-6.12 || { echo "folder not found"; exit 1; }

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
make -j$(nproc)

if [ -f "arch/x86/boot/bzImage" ]; then
    echo "path: $(pwd)/arch/x86/boot/bzImage"
    echo "name: $(make kernelrelease)"
else
    echo "error: linux dont foud"
fi