# install
my install scripts. I strictly advice against using them. I'm not responsible if you wipe your hard drives for good.

If you want to use it anyway and just want a quick way to get an arch install on UEFI running, read first and make changes according to your needs.
The only things you need to do manually (after creating a bootable USB and making sure to have a network connection of course) are:
Create 2 partitions (in cgdisk for example) 1 'boot' 500MB ef00 and 1 'root' 8300 for the rest and either:
- `curl -O https://raw.githubusercontent.com/fov95/install/main/arch_install; chmod +x arch_install; ./arch_install `

OR

- `pacman -Sy`
- `pacman -S git`
- `git clone https://github.com/fov95/install`
- `chmod +x install/arch_install`
- `./install/arch_install`
