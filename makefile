# --- Настройки ---
KERNEL_DIR = kernel/linux-6.12
KERNEL_IMG = $(KERNEL_DIR)/arch/x86/boot/bzImage
INITRAMFS = builds/initramfs.cpio.gz
ROOTFS_DIR = rootfs
IMAGE = builds/pristella.img
MOUNT_DIR = /mnt/pristella
EFI_DIR = /mnt/pristella_efi
OVMF_VARS = OVMF_VARS.fd
TMP_DIR = $(HOME)/Pristella/tmp
RL = $(ROOTFS_DIR)/etc/runlevels

# Последняя console= становится /dev/console (сюда пишет OpenRC)
CONSOLE = console=tty0 console=ttyS0,115200

# Библиотеки, собранные вручную, кладутся в rootfs при сборке
LIBS = $(HOME)/Pristella/builds/util-linux-2.41.3/.libs/libmount.so.1 \
       $(HOME)/Pristella/builds/util-linux-2.41.3/.libs/libblkid.so.1 \
       $(HOME)/Pristella/builds/pcre2-10.44/.libs/libpcre2-8.so.0 \
       $(HOME)/Pristella/builds/openssl-3.3.1/libcrypto.so.3

# --- Команда запуска QEMU (выход: Ctrl+A, затем X) ---
QEMU = qemu-system-x86_64 \
     -enable-kvm \
     -m 1024 \
     -vga std \
     -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/OVMF_CODE.fd \
     -drive if=pflash,format=raw,file=$(OVMF_VARS) \
     -drive format=raw,file=$(IMAGE),if=ide

# --- Цели ---
.PHONY: all clean install rootfs-setup initramfs run boot

all: install

clean:
	-@sudo umount $(EFI_DIR) 2>/dev/null || true
	-@sudo umount $(MOUNT_DIR) 2>/dev/null || true
	-@losetup -j $(IMAGE) -O NAME -n 2>/dev/null | xargs -r sudo losetup -d
	rm -f $(INITRAMFS) $(IMAGE)

rootfs-setup:
	@mkdir -p $(ROOTFS_DIR)/etc $(ROOTFS_DIR)/sbin $(ROOTFS_DIR)/proc $(ROOTFS_DIR)/sys \
	          $(ROOTFS_DIR)/dev/pts $(ROOTFS_DIR)/run $(ROOTFS_DIR)/tmp $(ROOTFS_DIR)/root \
	          $(ROOTFS_DIR)/mnt $(ROOTFS_DIR)/var/log $(ROOTFS_DIR)/usr/lib
	@chmod 1777 $(ROOTFS_DIR)/tmp
	@chmod 700 $(ROOTFS_DIR)/root

	@echo 'root:x:0:0:root:/root:/bin/bash' > $(ROOTFS_DIR)/etc/passwd
	@echo 'root:$$6$$lp9x/eF9WPmq9.n9$$ESzMj.iEAFHNpp2nsfZjM1mZOq1xLzDDO7VAF8KYaIbwjzimq/zLG2SPWf8GkIBYVQeZ5XoWhhUybp0zwTzeQ0:19000:0:99999:7:::' > $(ROOTFS_DIR)/etc/shadow
	@chmod 600 $(ROOTFS_DIR)/etc/shadow
	@echo 'root:x:0:' > $(ROOTFS_DIR)/etc/group
	@echo 'pristella' > $(ROOTFS_DIR)/etc/hostname
	@echo '127.0.0.1 localhost pristella' > $(ROOTFS_DIR)/etc/hosts
	@printf '/dev/sda2\t/\text4\trw,noatime\t0\t0\n' > $(ROOTFS_DIR)/etc/fstab
	@printf '/lib64\n/usr/lib\n' > $(ROOTFS_DIR)/etc/ld.so.conf

	@for f in $(LIBS); do \
	  test -f "$$f" || { echo "НЕТ: $$f"; exit 1; }; \
	  cp -L "$$f" $(ROOTFS_DIR)/usr/lib/; \
	done

	@test -e $(ROOTFS_DIR)/sbin/fsck || { printf '#!/bin/sh\nexit 0\n' > $(ROOTFS_DIR)/sbin/fsck; chmod 755 $(ROOTFS_DIR)/sbin/fsck; }

	@ln -sfn ../usr/bin/agetty $(ROOTFS_DIR)/sbin/agetty
	@ln -sfn agetty $(ROOTFS_DIR)/etc/init.d/agetty.tty1
	@ln -sfn agetty $(ROOTFS_DIR)/etc/init.d/agetty.ttyS0
	@mkdir -p $(ROOTFS_DIR)/etc/conf.d
	@printf 'baud="115200"\nterm_type="vt100"\n' > $(ROOTFS_DIR)/etc/conf.d/agetty.ttyS0

	@mkdir -p $(RL)/sysinit $(RL)/boot $(RL)/default
	@for s in devfs dmesg sysfs procfs cgroups; do ln -sfn ../../init.d/$$s $(RL)/sysinit/$$s; done
	@for s in root localmount hostname bootmisc; do ln -sfn ../../init.d/$$s $(RL)/boot/$$s; done
	@ln -sfn ../../init.d/agetty.tty1 $(RL)/default/agetty.tty1
	@ln -sfn ../../init.d/agetty.ttyS0 $(RL)/default/agetty.ttyS0
	@ln -sfn ../../init.d/local $(RL)/default/local

	@rm -f $(RL)/default/devfs $(RL)/default/sysfs $(RL)/default/procfs $(RL)/default/agetty.tty0 $(RL)/boot/procfs
	@rm -f $(RL)/boot/fsck $(RL)/boot/hwclock $(RL)/default/fsck $(RL)/default/hwclock
	@for l in $(RL)/*/*; do \
	  if [ -L "$$l" ]; then ln -sfn ../../init.d/$$(basename "$$(readlink "$$l")") "$$l"; fi; \
	done

	@test -f $(ROOTFS_DIR)/etc/rc.conf && sed -i -E 's/^#?(rc_logger)=.*/\1="YES"/; s/^#?(rc_verbose)=.*/\1=yes/' $(ROOTFS_DIR)/etc/rc.conf || true

# Отдельная цель: initramfs в сборке образа не используется
initramfs: rootfs-setup
	mkdir -p builds
	cd $(ROOTFS_DIR) && find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../$(INITRAMFS)

install: clean rootfs-setup
	@test -f $(KERNEL_IMG) || (echo "Ядро не найдено: $(KERNEL_IMG). Соберите его сначала." && exit 1)
	mkdir -p $(TMP_DIR) builds
	printf 'set timeout=10\nset default=0\n\nmenuentry "Pristella GNU/Linux" {\n    insmod part_gpt\n    insmod ext2\n    set root=(hd0,gpt2)\n    linux /boot/bzImage root=/dev/sda2 rw init=/sbin/openrc-init $(CONSOLE)\n}\n' > $(TMP_DIR)/grub.cfg

	grub-mkimage \
	  -O x86_64-efi \
	  -o $(TMP_DIR)/BOOTX64.EFI \
	  -p /boot/grub \
	  part_gpt part_msdos ext2 fat normal linux configfile echo test

	truncate -s 2G $(IMAGE)

	parted -s $(IMAGE) mklabel gpt
	parted -s $(IMAGE) mkpart primary fat32 1MiB 129MiB
	parted -s $(IMAGE) mkpart primary ext4 129MiB 100%

	@set -e; \
	LOOP_DEV=$$(sudo losetup -fP --show $(IMAGE)); \
	echo "Loop: $$LOOP_DEV"; \
	sudo mkfs.vfat -F 32 $${LOOP_DEV}p1; \
	sudo mkfs.ext4 -q $${LOOP_DEV}p2; \
	sudo mkdir -p $(EFI_DIR) $(MOUNT_DIR); \
	sudo mount $${LOOP_DEV}p1 $(EFI_DIR); \
	sudo mount $${LOOP_DEV}p2 $(MOUNT_DIR); \
	sudo mkdir -p $(MOUNT_DIR)/boot/grub $(EFI_DIR)/EFI/BOOT $(EFI_DIR)/boot/grub; \
	sudo cp $(KERNEL_IMG) $(MOUNT_DIR)/boot/bzImage; \
	tar -C $(ROOTFS_DIR) --owner=0 --group=0 --numeric-owner -cf - . | sudo tar -C $(MOUNT_DIR) -xpf -; \
	sudo ldconfig -r $(MOUNT_DIR) || true; \
	sudo cp $(TMP_DIR)/grub.cfg $(EFI_DIR)/boot/grub/grub.cfg; \
	sudo cp $(TMP_DIR)/grub.cfg $(MOUNT_DIR)/boot/grub/grub.cfg; \
	sudo cp $(TMP_DIR)/BOOTX64.EFI $(EFI_DIR)/EFI/BOOT/BOOTX64.EFI; \
	sync; \
	sudo umount $(EFI_DIR); \
	sudo umount $(MOUNT_DIR); \
	sudo losetup -d $$LOOP_DEV

get-rootfs:
	cd $(HOME)/Pristella && tar -xJf pristella-rootfs.tar.xz

get-archive:
	cd $(HOME)/Pristella && tar -cJf pristella-rootfs.tar.xz rootfs/
	@echo "$(HOME)/Pristella/pristella-rootfs.tar.xz"

run: install
	$(QEMU)

boot:
	$(QEMU)

ng:
	$(QEMU) -nographic