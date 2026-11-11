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

# Защита от случайного rm -rf /
if [ -z "$ROOTFS" ] || [ "$ROOTFS" = "/" ]; then
    echo "Ошибка: ROOTFS не задан или равен '/'. Прерываю."
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

# Полная синхронизация
echo "Очищаю $ROOTFS и копирую всё из $MOUNT_DIR..."
# Используем find ... -delete, чтобы не удалить сам каталог rootfs
sudo find "$ROOTFS" -mindepth 1 -delete

# Копируем всё содержимое с сохранением прав, симлинков и владельцев
sudo cp -a "$MOUNT_DIR/." "$ROOTFS/"

# Отмонтируем и чистим
echo "Отмонтирую..."
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP"
[ -f "$TMP_IMG" ] && rm -f "$TMP_IMG"

# Возвращаем владельца (на случай, если вы работаете от photon)
if id "photon" &>/dev/null; then
    sudo chown -R photon:photon "$ROOTFS"
else
    sudo chown -R $(logname):$(logname) "$ROOTFS" 2>/dev/null || true
fi

echo "Готово! Теперь 'make run' подхватит новую rootfs."