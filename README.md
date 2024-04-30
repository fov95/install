# install
If you want to use the scripts read first and make changes according to your needs.

Create 2 partitions (in cgdisk for example) 1 'boot' 500MB ef00 and 1 'root' 8300 for the rest and either:
- `curl -O https://raw.githubusercontent.com/fov95/install/main/P407_install; chmod +x P407_install; ./P407_install`

OR

- `pacman -Sy`
- `pacman -S git`
- `git clone https://github.com/fov95/install`
- `chmod +x install/P407_install`
- `./install/P407_install`
