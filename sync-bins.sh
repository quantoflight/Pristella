#!/bin/bash

# Настройки
IMG="builds/pristella.img"
ROOTFS="rootfs"
MOUNT_DIR="/mnt/pristella-sync"
TMP_IMG="/tmp/pristella-sync.img"
LOOP=""

# Проверка, что мы в папке проекта
if [ ! -f "$IMG" ]; then
    echo "Ошибка: $IMG не найден. Запускай из папки Pristella."
    exit 1
fi

# Проверка, занят ли образ (QEMU)
if losetup -a | grep -q "$IMG"; then
    echo "Образ занят QEMU. Создаю временную копию..."
    cp "$IMG" "$TMP_IMG"
    IMG="$TMP_IMG"
fi

# Создаем loop-устройство
echo "Монтирую $IMG..."
LOOP=$(sudo losetup -fP --show "$IMG")
if [ -z "$LOOP" ]; then
    echo "Ошибка: не удалось создать loop-устройство."
    exit 1
fi

# Ищем корневой раздел (обычно p2, но может быть p1)
PART="${LOOP}p2"
if [ ! -b "$PART" ]; then
    PART="${LOOP}p1"
fi

if [ ! -b "$PART" ]; then
    echo "Ошибка: не найден раздел $PART"
    sudo losetup -d "$LOOP"
    exit 1
fi

# Монтируем
sudo mkdir -p "$MOUNT_DIR"
sudo mount "$PART" "$MOUNT_DIR"
if [ $? -ne 0 ]; then
    echo "Ошибка: не удалось смонтировать $PART"
    sudo losetup -d "$LOOP"
    exit 1
fi

# Копируем папки с бинарниками
echo "Копирую бинарники из $MOUNT_DIR в $ROOTFS..."
for dir in bin sbin usr/bin usr/sbin; do
    if [ -d "$MOUNT_DIR/$dir" ]; then
        echo "  → $dir"
        sudo rm -rf "$ROOTFS/$dir"
        sudo cp -a "$MOUNT_DIR/$dir" "$ROOTFS/$dir"
    fi
done

# Отмонтируем и чистим
echo "Отмонтирую..."
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP"
[ -f "$TMP_IMG" ] && rm -f "$TMP_IMG"
sudo chown -R photon:photon /home/photon/Pristella/rootfs

echo "Готово! Теперь 'make run' подхватит новые бинарники."