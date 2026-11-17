#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

ROOT_PART=NONE
BOOT_PART=NONE
SWAP_PART=NONE
SWAP_ENABLE=false
SWAP_FLAG_SET=false
VERSION="0.14"
MOD_DATE="11.16.26"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set_root=*) ROOT_PART="${1#*=}" ;;
        --set_boot=*) BOOT_PART="${1#*=}" ;;
        --set_swap=*) SWAP_PART="${1#*=}" ;;
        --swap=*)     SWAP_ENABLE="${1#*=}"; SWAP_FLAG_SET=true ;;
        --help)
                echo "Pristella Installer Help:"
                echo "  --set_root=<part>   for specifying the root partition"
                echo "  --set_boot=<part>   for specifying the boot partition"
                echo "  --set_swap=<part>   for specifying the swap partition"
                echo "  --swap=true|false   for enabling/disabling swap (default = false)"
                exit 0 ;;
        --version)
            echo "Pristella GNU/Linux Installer:"
            echo "  version                     $VERSION"
            echo "  date of last modification   $MOD_DATE"
            exit 0 ;;
        *)
            echo "Unknown args"
            exit 1
            ;;
    esac
    shift
done

if [ "$ROOT_PART" = "NONE" ]; then
    echo "ERROR: You didn't specify the root"
    exit 1
fi

if [ -b "$ROOT_PART" ]; then
    echo "[info] Root partition found!"
else
    echo "ERROR: The specified root partition does not exist."
    exit 1
fi

if [ "$BOOT_PART" = "NONE" ]; then
    echo "ERROR: You didn't specify the boot"
    exit 1
fi

if [ -b "$BOOT_PART" ]; then
    echo "[info] Boot partition found!"
else
    echo "ERROR: The specified boot partition does not exist."
    exit 1
fi

if [[ "$SWAP_ENABLE" != "true" && "$SWAP_ENABLE" != "false" ]]; then
    echo "swap toggle error: unknown args"
    exit 1
fi

if [ "$SWAP_FLAG_SET" = false ] && [ "$SWAP_PART" != "NONE" ]; then
    SWAP_ENABLE=true
fi

if [ "$SWAP_ENABLE" = "true" ]; then
    if [ "$SWAP_PART" = "NONE" ]; then
        exit 1
    fi
    if [ -b "$SWAP_PART" ]; then
        echo "[info] Swap partition found!"
    else
        echo "ERROR: The specified swap partition does not exist."
        exit 1
    fi
fi

echo "finish configurate: "
    echo "  root part       $ROOT_PART"
    echo "  boot part       $BOOT_PART"
    echo "  swap enable     $SWAP_ENABLE"

if [ "$SWAP_ENABLE" = "true" ]; then
    echo "  swap part       $SWAP_PART"
fi

echo "WARNING: This will FORMAT $ROOT_PART and $BOOT_PART."
echo "All data on these partitions will be LOST."
read -p "Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo "[info] Formatting boot partition ($BOOT_PART)..."
mkfs.vfat -F 32 "$BOOT_PART" || { echo "ERROR: mkfs.vfat failed"; exit 1; }

echo "[info] Formatting root partition ($ROOT_PART)..."
mkfs.ext4 -q "$ROOT_PART" || { echo "ERROR: mkfs.ext4 failed"; exit 1; }

if [ "$SWAP_ENABLE" = "true" ]; then
    echo "[info] Setting up swap on $SWAP_PART..."
    mkswap "$SWAP_PART" || { echo "ERROR: mkswap failed"; exit 1; }
    swapon "$SWAP_PART" || { echo "ERROR: swapon failed"; exit 1; }
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
MOUNT_DIR="/mnt/pristella"
ROOTFS_ARCHIVE="$SCRIPT_DIR/pristella-rootfs.tar.xz"
KERNEL_SCRIPT="/root/build-kernel.sh"    

# MOUNT
echo "[info] Mounting partitions..."
mkdir -p "$MOUNT_DIR"
mount "$ROOT_PART" "$MOUNT_DIR" || { echo "ERROR: Failed to mount root"; exit 1; }
mkdir -p "$MOUNT_DIR/boot"
mount "$BOOT_PART" "$MOUNT_DIR/boot" || { echo "ERROR: Failed to mount boot"; exit 1; }

# ROOTFS
echo "[info] Extracting rootfs..."
if [ -f "$ROOTFS_ARCHIVE" ]; then
    tar -xJf "$ROOTFS_ARCHIVE" -C "$MOUNT_DIR" --numeric-owner || { echo "ERROR: Extract failed"; umount -R "$MOUNT_DIR"; exit 1; }
else
    echo "ERROR: $ROOTFS_ARCHIVE not found!"
    umount -R "$MOUNT_DIR"
    exit 1
fi

if [ ! -f "$MOUNT_DIR/etc/passwd" ]; then
    echo "ERROR: rootfs extraction failed or archive is invalid."
    umount -R "$MOUNT_DIR"
    exit 1
fi

# PRE-CHROOT
echo "[info] Preparing chroot environment..."
mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"

# CHECK SCRIPTS
if [ ! -f "$MOUNT_DIR$KERNEL_SCRIPT" ]; then
    echo "ERROR: $KERNEL_SCRIPT not found in rootfs!"
    umount -R "$MOUNT_DIR"
    exit 1
fi

# CHROOT && BUILD KERNEL
echo "[info] Compiling kernel inside chroot (this may take a while)..."
chroot "$MOUNT_DIR" /bin/bash -c "
    cd /root || exit 1
    chmod +x build-kernel.sh
    ./build-kernel.sh
" || { echo "ERROR: Kernel compilation failed"; umount -R "$MOUNT_DIR"; exit 1; }

# COPING KERNEL
if [ -f "$MOUNT_DIR/usr/src/linux-6.12/arch/x86/boot/bzImage" ]; then
    cp "$MOUNT_DIR/usr/src/linux-6.12/arch/x86/boot/bzImage" "$MOUNT_DIR/boot/bzImage"
fi

# INSTALLING GRUB BOOTLOADER
echo "[info] Installing GRUB..."
chroot "$MOUNT_DIR" /bin/bash -c "
    # Устанавливаем GRUB в EFI
    grub-install --target=x86_64-efi \
                 --efi-directory=/boot \
                 --boot-directory=/boot \
                 --removable \
                 --no-nvram || exit 1
                 
    grub-mkconfig -o /boot/grub/grub.cfg || exit 1
" || { echo "ERROR: GRUB installation failed"; umount -R "$MOUNT_DIR"; exit 1; }

# FSTAB
echo "[info] Generating fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_PART")
cat > "$MOUNT_DIR/etc/fstab" <<EOF
UUID=$ROOT_UUID  /      ext4  rw,noatime  0 1
UUID=$BOOT_UUID  /boot  vfat  rw,noatime  0 2
EOF

# ADDING SWAP
if [ "$SWAP_ENABLE" = "true" ]; then
    SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")
    echo "UUID=$SWAP_UUID  none   swap  defaults    0 0" >> "$MOUNT_DIR/etc/fstab"
fi

# UMOUNT...
echo "[info] Unmounting..."
umount -R "$MOUNT_DIR"

# OFF SWAP
if [ "$SWAP_ENABLE" = "true" ]; then
    swapoff "$SWAP_PART"
fi

echo "[info] Installation complete!"

# REBOOT
read -p "Do you want to reboot now? (y/n): " REBOOT_CHOICE
if [ "$REBOOT_CHOICE" = "y" ] || [ "$REBOOT_CHOICE" = "Y" ]; then
    echo "[info] Rebooting..."
    reboot
else
    echo "[info] You can reboot manually later."
fi