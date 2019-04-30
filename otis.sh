# Do some unimportant stuff

loadkeys us
locale-gen
timedatectl set-ntp true

# Lets get some info
echo "Choose a hostname:"
read hostname

echo "Enter user account name (lowercase, no spaces):"
read username

# Partition and mount harddrive

lsblk
echo ""
echo "Drive to partition:"
read drive
echo "Drivetype (UEFI or BIOS):"
read drivetype

partition() {
if [ "$drivetype" == "UEFI" ]; then
	parted $drive mklabel gpt
	parted $drive mkpart ESP fat32 1MiB 513MiB
	parted $drive set 1 boot on
	parted $drive mkpart primary ext4 513MiB 20GiB
	parted $drive mkpart primary linux-swap 20GiB 24GiB
	parted $drive mkpart primary ext4 24GiB 100%
else
	parted $drive mklabel msdos
	parted $drive mkpart primary ext4 1MiB 20GiB
	parted $drive set 1 boot on
	parted $drive mkpart primary linux-swap 20GiB 24GiB
	parted $drive mkpart primary ext4 24GiB 100%
fi
}

prepareDrive() {
if [ "$drivetype" == "UEFI" ]; then
	mkfs.vfat -F32 $drive\1
	mkfs.ext4 -F $drive\2
	mkfs.ext4 -F $drive\4
	mkswap $drive\3
	swapon $drive\3
	mount $drive\2 /mnt
	mkdir /mnt/boot
	mkdir /mnt/home
	mount $drive\1 /mnt/boot
	mount $drive\4 /mnt/home
else
	mkfs.ext4 -F $drive\1
	mkswap $drive\2
	swapon $drive\2
	mkfs.ext4 -F $drive\3
	mkdir /mnt
	mount $drive\1 /mnt
	mkdir /mnt/home
	mount $drive\3 /mnt/home
fi
}

partition $drive
prepareDrive $drive

# Install reflector and rate mirrors

pacman -Sy reflector --noconfirm
reflector --verbose -l 200 -p http --sort rate --save /etc/pacman.d/mirrorlist

# Install base system and extras, then chroot into install

pacstrap -i /mnt base base-devel --noconfirm
genfstab -U /mnt > /mnt/etc/fstab

# Do some unimportant stuff

arch-chroot /mnt loadkeys us
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Kentucky/Louisville /etc/localtime
arch-chroot /mnt hwclock --systohc --utc

# Configure hostname

echo $hostname > /mnt/etc/hostname
echo "#<ip-address>	<hostname.domain.org>	<hostname>
127.0.0.1		localhost.localdomain	localhost	$hostname
::1		localhost.localdomain	localhost	$hostname" > /mnt/etc/hosts

# Enable services

echo "Enabling services..."
sleep 3
arch-chroot /mnt systemctl enable dhcpcd.service

# Install additional packages

echo "Installing additional packages..."
sleep 3
while read package; do
    # Do what you want to $name
    arch-chroot /mnt pacman -S ${package} --noconfirm
done < "packages"

# Set root password

echo "Choose a root password:"
arch-chroot /mnt passwd

# Install and configure bootloader

if [ "$drivetype" == "UEFI" ]; then
	touch /mnt/boot/loader/entries/arch.conf
	arch-chroot /mnt pacman -S dosfstools --noconfirm
	arch-chroot /mnt bootctl --path=/boot install
	mkdir -p /mnt/boot/loader/entries/
	echo "title	Arch Linux
	linux	/vmlinuz-linux
	initrd	/initramfs-linux.img
	options	root=$drive\2 rw" > /mnt/boot/loader/entries/arch.conf
else
	mkdir -p /mnt/boot/grub/
	arch-chroot /mnt pacman -S grub os-prober --noconfirm
	arch-chroot /mnt grub-install --recheck $drive
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

# Create user account

arch-chroot /mnt useradd -m -G wheel -s /bin/bash $username
echo "Enter user account password for $username:"
arch-chroot /mnt passwd $username

# End installation

umount -R /mnt
reboot
