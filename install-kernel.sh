#!/bin/bash
KERNEL_NAME="linux-6.12.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x"
KERNEL_DIR="kernel/linux-6.12"

if [ "$1" = "del" ]; then
    rm -rf kernel
    echo "Cleaned."
    exit 0
fi

if [ ! -f "$KERNEL_NAME" ]; then
    echo "Downloading $KERNEL_NAME..."
    wget "$KERNEL_URL/$KERNEL_NAME" || { echo "Download failed"; exit 1; }
else
    echo "Archive already exists."
fi

# 2. Распаковываем, если папки с исходниками ещё нет
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Extracting..."
    mkdir -p kernel
    tar -xJf "$KERNEL_NAME" -C kernel || { echo "Extraction failed"; exit 1; }
    echo "Installed!"
else
    echo "Sources already extracted."
fi

if [ "$1" = "compile" ]; then
    echo "Compiling kernel..."
    cd "$KERNEL_DIR" || exit 1
    make defconfig
    make -j$(nproc)
    
    if [ -f "arch/x86/boot/bzImage" ]; then
        echo "====================================="
        echo "KERNEL BUILT SUCCESSFULLY!"
        echo "Path: $(pwd)/arch/x86/boot/bzImage"
        echo "====================================="
    else
        echo "Compilation finished, but bzImage not found."
    fi
fi