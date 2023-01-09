#!/bin/bash
# vim:ft=sh

loadkeys uk
timedatectl set-ntp true

# Todo: better methods
# Create 2 partitions first and name them "boot" & "root" for now. (I'm using "cgdisk" for that)
# boot  512MB   ef00
# root  REST    8300 (default)

# Functions --------------------------------------------------------------------

# Select boot partition
select_boot(){
  clear
  lsblk
  echo -e "\nPlease select boot partiton ( like "sda1" or "sdb1" )"
  read BOOT_PARTITION
  echo "You selected "$BOOT_PARTITION""
  read -p "Are you sure (y/n)?" choice
  case "$choice" in
    y|Y ) : ;;
    n|N ) select_boot ;;
    * ) clear; echo -e "Invalid choice\n\nOnly y/n possible"; sleep 3; select_boot ;;
  esac
}

# Select root partition
select_root(){
  clear
  lsblk
  echo -e "\nPlease select root partiton ( like "sda2" or "sdb2" )"
  read ROOT_PARTITION
  echo "You selected "$ROOT_PARTITION""
  read -p "Are you sure (y/n)?" choice
  case "$choice" in
    y|Y ) : ;;
    n|N ) select_root ;;
    * ) clear; echo -e "Invalid choice\n\nOnly y/n possible"; sleep 3; select_root ;;
  esac
}

# Helper function. When there is an error, the function just makes it so that
# the command repeats until there is no error anymore.
RetryOnFail() {
  $1
while [ $? -ne 0 ]
do
  $1
done
}

# Encrypt function
EncryptPartition() {
  cryptsetup luksFormat -v -s 512 -h sha512 /dev/$ROOT_PARTITION
}

# Open function
OpenPartition() {
 cryptsetup luksOpen /dev/$ROOT_PARTITION luks
}
# ------------------------------------------------------------------------------

# Select boot partition
select_boot

# Select boot partition
select_root

# Create EFI partition
mkfs.vfat -F32 -n EFI /dev/$BOOT_PARTITION

# Setup the encryption of the system
RetryOnFail EncryptPartition
RetryOnFail OpenPartition

# Create encrypted partitions
pvcreate /dev/mapper/luks
vgcreate vg0 /dev/mapper/luks
lvcreate -l +100%FREE vg0 --name root

# Create filesystems on encrypted partitions
mkfs.ext4 -L root /dev/mapper/vg0-root

# Mount the new system
mount /dev/mapper/vg0-root /mnt
mkdir /mnt/boot
mount /dev/$BOOT_PARTITION /mnt/boot

# Todo: zram maybe?
# Create SWAP file
dd if=/dev/zero of=/mnt/swap bs=1M count=1024
mkswap /mnt/swap
swapon /mnt/swap
chmod 0600 /mnt/swap

# Install the system
pacstrap /mnt base base-devel efibootmgr lvm2 linux-lts linux-firmware networkmanager sudo vi neovim man-db zsh intel-ucode git

# Generate fstab
genfstab -pU /mnt >> /mnt/etc/fstab
# Relatime to noatime to decrease wear on SSD
sed -i "s|relatime|noatime,lazytime|g" /mnt/etc/fstab
# Make /tmp a ramdisk (add the following line to /mnt/etc/fstab)
echo "#tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /mnt/etc/fstab
# Add DATA partition
echo "/dev/disk/by-label/DATA /mnt/data auto nosuid,noatime,lazytime,nodev,nofail,x-gvfs-show 0 0" >> /mnt/etc/fstab


archchroot() {
# Functions --------------------------------------------------------------------
# Helper function. When there is an error, the function just makes it so that
# the command repeats until there is no error anymore.
RetryOnFail() {
  $1
while [ $? -ne 0 ]
do
  $1
done
}
# ------------------------------------------------------------------------------

# Setup system clock
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc

# Set the hostname
echo "Enter hostname please:"
read hostname
echo "$hostname" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 "$hostname".localdomain "$hostname"
EOT

# Generate locale
echo "en_GB.UTF-8 UTF-8" >  /etc/locale.gen
locale-gen
echo -e "LANG=en_GB.UTF-8\nLC_COLLATE=C" > /etc/locale.conf
echo "KEYMAP=uk" > /etc/vconsole.conf
echo "FONT=lat9-16" >> /etc/vconsole.conf

# Set password for root
echo "Enter root password please:"
RetryOnFail passwd

# Add user
echo "Enter username please:"
read username
groupadd "$username"
useradd -m -g "$username" -G wheel -s /bin/zsh "$username"
#useradd -m -G wheel -s /bin/zsh "$username"

# Set password for user
echo "Enter password for "$username" please:"
read -s pass
echo "$username":"$pass" | chpasswd

# Add user to wheel
visudo

# Configure mkinitcpio with modules needed for the initrd image
sed -i 's|MODULES=()|MODULES=(ext4)|' /etc/mkinitcpio.conf
sed -i 's|block filesystems|block encrypt lvm2 filesystems|' /etc/mkinitcpio.conf
# Regenerate initrd image
mkinitcpio -p linux-lts

# Setup systembootd (grub will not work on nvme at this moment)
bootctl --path=/boot install

# Create loader.conf
echo default arch-lts >> /boot/loader/loader.conf
echo timeout 5 >> /boot/loader/loader.conf

# Create arch-lts.conf (or XYZ.conf for default XYZ in loader.conf)
# Options:  rw = needed because of 'fsck' hook
#           quiet = silent boot
#           nowatchdog = Not needed on desktop & consumes power for no reason
# get UUID of "root"
ROOT_UUID=$(blkid | grep "root" | grep -v vg0 | cut -d'"' -f2)
cat <<EOT > /boot/loader/entries/arch-lts.conf
title Arch Linux LTS
linux /vmlinuz-linux-lts
initrd /intel-ucode.img
initrd /initramfs-linux-lts.img
options cryptdevice=UUID="$ROOT_UUID":vg0 root=/dev/mapper/vg0-root rw quiet nowatchdog
EOT
#  vm.dirty_ratio = 15 vm.dirty_background_ratio = 10 vm.vfs_cache_pressure = 50

# Some optional stuff ----------------------------------------------------------
# Disable VT switch
mkdir /etc/X11/xorg.conf.d
cat <<EOT > /etc/X11/xorg.conf.d/10-server.conf
Section "ServerFlags"
        Option "DontVTSwitch" "True"
        Option "DontZap"      "True"
EndSection
EOT

# Rootless Xorg
cat <<EOT > /etc/X11/Xwrapper.config
needs_root_rights = no
EOT

# Enable multilb
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

# Reduce swappiness
echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf

# Lock root
sed -i "s|root:/bin/bash|root:/usr/sbin/nologin|" /etc/passwd
passwd -l root
}

export -f archroot
arch-chroot /mnt /bin/bash -c "archroot" || echo "arch-chroot returned: $?"

# moving to chroot
#chmod +x install_1.sh
#cp install_1.sh /mnt

#arch-chroot /mnt /bin/bash install_1.sh
