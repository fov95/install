#!/bin/bash
# vim:ft=sh

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

# Create arch.conf (or XYZ.conf for default XYZ in loader.conf)
# get UUID of "root"
ROOT_UUID=$(blkid | grep "root" | grep -v vg0 | cut -d'"' -f2)
cat <<EOT > /boot/loader/entries/arch-lts.conf
title Arch Linux LTS
linux /vmlinuz-linux-lts
initrd /intel-ucode.img
initrd /initramfs-linux-lts.img
options cryptdevice=UUID="$ROOT_UUID":vg0 root=/dev/mapper/vg0-root rw
EOT

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
