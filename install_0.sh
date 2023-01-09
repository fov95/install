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


# moving to chroot and reboot when everything is done
chmod +x install_1.sh
cp install_1.sh /mnt

arch-chroot /mnt /bin/bash install_1.sh
