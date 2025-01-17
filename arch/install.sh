#!/usr/bin/env -S bash -e
clear

# Updating the live environment usually causes more problems than its worth, and quite often can't be done without remounting cowspace with more capacity, especially at the end of any given month.
pacman -Sy

# Installing curl
pacman -S --noconfirm curl git

# Target for the installation.

DISK=/dev/nvme0n1
echo "Installing Arch Linux on $DISK."

# Setting username.

read -r -p "Please enter name for a user account (leave empty to skip): " username

# Setting password.

if [[ -n $username ]]; then
    read -r -p "Please enter a password for the user account: " password
fi

# Deleting old partition scheme.

wipefs -af "$DISK" &>/dev/null
sgdisk -Zo "$DISK" &>/dev/null

# Creating a new partition scheme.

echo "Creating new partition scheme on $DISK."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 512MiB \
    set 1 esp on \
    mkpart cryptroot 512MiB 100% \

sleep 0.1
ESP="/dev/$(lsblk $DISK -o NAME,PARTLABEL | grep ESP| cut -d " " -f1 | cut -c7-)"
cryptroot="/dev/$(lsblk $DISK -o NAME,PARTLABEL | grep cryptroot | cut -d " " -f1 | cut -c7-)"

# Informing the Kernel of the changes.

echo "Informing the Kernel about the disk changes."
partprobe "$DISK"

# Formatting the ESP as FAT32.

echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 -s 2 $ESP &>/dev/null

# Creating a LUKS Container for the root partition.

echo "Creating LUKS Container for the root partition."
cryptsetup luksFormat $cryptroot
echo "Opening the newly created LUKS Container."
cryptsetup luksOpen $cryptroot cryptroot
EXT4="/dev/mapper/cryptroot"

# Create encrypted partitions - Encrypted Linux (Root + Home) & Swap partitions

pvcreate $EXT4
vgcreate vg0 $EXT4
lvcreate -L 200G -n root vg0
lvcreate -L 32G -n swap vg0
lvcreate -l 100%FREE -n home vg0

# Formatting the LUKS Container as EXT4.

echo "Formatting the LUKS container as EXT4."
mkfs.ext4 /dev/mapper/vg0-root &>/dev/null
mkfs.ext4 /dev/mapper/vg0-home &>/dev/null
mkswap /dev/mapper/vg0-swap &>/dev/null

# Mounting the newly created subvolumes.

echo "Mounting volumes."
mount /dev/mapper/vg0-root /mnt
mkdir -p /mnt/{boot,home}
mount /dev/mapper/vg0-home /mnt/home
mount $ESP /mnt/boot
swapon /dev/mapper/vg0-swap

# Pacstrap (setting up a base sytem onto the new root).

echo "Installing the base system (it may take a while)."
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers sudo plymouth lvm2 efibootmgr intel-ucode mesa vim reflector mlocate man-db sof-firmware fwupd pcsc-tools grc unzip pacman-contrib rsync chrony networkmanager pcsclite ccid pcsc-tools apparmor firewalld flatpak sway swaybg swayidle swaylock waybar xdg-desktop-portal-wlr thunar thunar-archive-plugin thunar-volman xorg-xwayland dunst wezterm wofi pavucontrol brightnessctl playerctl slurp grim greetd network-manager-applet gnome-keyring blueberry git python-psutil python-notify2 blueman bluez bluez-utils gparted rsync ly qt5-wayland lxappearance qt5ct polkit lxqt-policykit imv fastfetch wireplumber pipewire pipewire-jack pipewire-alsa pipewire-pulse xdg-desktop-portal galculator evince eog wget exa bat btop tree speedtest-cli net-tools waybar wofi firefox chromium bitwarden vlc unzip p7zip libreoffice-fresh thunderbird deluge ntfs-3g neovim python-pip jdk17-openjdk jre17-openjdk docker docker-compose veracrypt ttf-font-awesome ttf-caladea ttf-carlito ttf-dejavu ttf-liberation ttf-linux-libertine-g noto-fonts adobe-source-code-pro-fonts adobe-source-sans-pro-fonts adobe-source-serif-pro-fonts 

# Generating /etc/fstab.

echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.

hostname=xps
echo "$hostname" > /mnt/etc/hostname

# Setting hosts file.

echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Setting up locales.

echo "en_US.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# Setting up keyboard layout.

echo "KEYMAP=us-acentos" > /mnt/etc/vconsole.conf

# Configuring /etc/mkinitcpio.conf

echo "Configuring /etc/mkinitcpio for ZSTD compression and LUKS hook."
sed -i 's,MODULES=(),MODULES=(ext4),g' /mnt/etc/mkinitcpio.conf
sed -i 's,block,plymouth block encrypt lvm2 resume ,g' /mnt/etc/mkinitcpio.conf

# Enabling CPU Mitigations
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/default/grub.d/40_cpu_mitigations.cfg -o /mnt/etc/grub.d/40_cpu_mitigations.cfg

# Distrusting the CPU
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/default/grub.d/40_distrust_cpu.cfg -o /mnt/etc/grub.d/40_distrust_cpu.cfg

# Enabling IOMMU
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/default/grub.d/40_enable_iommu.cfg -o /mnt/etc/grub.d/40_enable_iommu.cfg

# Enabling NTS

curl https://raw.githubusercontent.com/GrapheneOS/infrastructure/main/chrony.conf >> /mnt/etc/chrony.conf

# Configure AppArmor Parser caching

sed -i 's/#write-cache/write-cache/g' /mnt/etc/apparmor/parser.conf
sed -i 's,#Include /etc/apparmor.d/,Include /etc/apparmor.d/,g' /mnt/etc/apparmor/parser.conf

# Blacklisting kernel modules
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/modprobe.d/30_security-misc.conf -o /mnt/etc/modprobe.d/30_security-misc.conf
chmod 600 /mnt/etc/modprobe.d/*

# Security kernel settings.
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/usr/lib/sysctl.d/990-security-misc.conf -o /mnt/etc/sysctl.d/990-security-misc.conf
sed -i 's/kernel.yama.ptrace_scope=2/kernel.yama.ptrace_scope=3/g' /mnt/etc/sysctl.d/990-security-misc.conf
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/sysctl.d/30_silent-kernel-printk.conf -o /mnt/etc/sysctl.d/30_silent-kernel-printk.conf
curl https://raw.githubusercontent.com/Kicksecure/security-misc/master/etc/sysctl.d/30_security-misc_kexec-disable.conf -o /mnt/etc/sysctl.d/30_security-misc_kexec-disable.conf
chmod 600 /mnt/etc/sysctl.d/*

# Remove nullok from system-auth

sed -i 's/nullok//g' /mnt/etc/pam.d/system-auth

# Disable coredump

echo "* hard core 0" >> /mnt/etc/security/limits.conf

# Disable su for non-wheel users

bash -c 'cat > /mnt/etc/pam.d/su' <<-'EOF'
#%PAM-1.0
auth		sufficient	pam_rootok.so
# Uncomment the following line to implicitly trust users in the "wheel" group.
#auth		sufficient	pam_wheel.so trust use_uid
# Uncomment the following line to require a user to be in the "wheel" group.
auth		required	pam_wheel.so use_uid
auth		required	pam_unix.so
account		required	pam_unix.so
session		required	pam_unix.so
EOF

# Randomize Mac Address.

bash -c 'cat > /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf' <<-'EOF'
[device]
wifi.scan-rand-mac-address=yes
[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
connection.stable-id=${CONNECTION}/${BOOT}
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf

# Enable IPv6 privacy extensions

bash -c 'cat > /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf' <<-'EOF'
[connection]
ipv6.ip6-privacy=2
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf

# Configuring the system.

arch-chroot /mnt /bin/bash -e <<-EOF

    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null

    # Setting up clock.
    hwclock --systohc

    # Generating locales.my keys aren't even on
    echo "Generating locales."
    locale-gen &>/dev/null

    # Generating a new initramfs.
    echo "Creating a new initramfs."
    chmod 600 /boot/initramfs-linux* &>/dev/null
    mkinitcpio -p linux &>/dev/null

    # Install systemd-boot
    echo "Install systemd-boot."
    bootctl install --path=/boot &>/dev/null

    # Adding user with sudo privilege
    if [ -n "$username" ]; then
        echo "Adding $username with root privilege."
        useradd -m $username
        usermod -aG wheel $username

        groupadd -r audit
        gpasswd -a $username audit
    fi
EOF

cat > /mnt/boot/loader/loader.conf <<-EOF
    default arch.conf
    timeout 0
    console-mode max
    editor no
EOF

cat > /mnt/boot/loader/entries/arch.conf <<-EOF
    title   Arch Linux
    linux   /vmlinuz-linux
    initrd  /intel-ucode.img
    initrd  /initramfs-linux.img
    options cryptdevice=$cryptroot:luks:allow-discards resume=/dev/mapper/vg0-swap root=/dev/mapper/vg0-root rw quiet splash lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOF

# Enable AppArmor notifications
# Must create ~/.config/autostart first

mkdir -p -m 700 /mnt/home/${username}/.config/autostart/
bash -c "cat > /mnt/home/${username}/.config/autostart/apparmor-notify.desktop" <<-'EOF'
[Desktop Entry]
Type=Application
Name=AppArmor Notify
Comment=Receive on screen notifications of AppArmor denials
TryExec=aa-notify
Exec=aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
StartupNotify=false
NoDisplay=true
EOF
chmod 700 /mnt/home/${username}/.config/autostart/apparmor-notify.desktop
arch-chroot /mnt chown -R $username:$username /home/${username}/.config

# Settings swap

echo "vm.swappiness=10" >> /mnt/etc/sysctl.conf

#  Settings SSD/NVME
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
echo "vm.dirty_background_ratio = 5" >> /etc/sysctl.conf

# Setting user password.

[ -n "$username" ] && echo "Setting user password for ${username}." && echo -e "${password}\n${password}" | arch-chroot /mnt passwd "$username" &>/dev/null

# Giving wheel user sudo access.

sed -i 's/# \(%wheel ALL=(ALL\(:ALL\|\)) ALL\)/\1/g' /mnt/etc/sudoers

# Change audit logging group

echo "log_group = audit" >> /etc/audit/auditd.conf

# Enabling audit service.

systemctl enable auditd --root=/mnt &>/dev/null

# Enabling auto-trimming service.

systemctl enable fstrim.timer --root=/mnt &>/dev/null

# Enabling NetworkManager.

systemctl enable NetworkManager --root=/mnt &>/dev/null

# Enabling ly

systemctl enable ly.service --root=/mnt &>/dev/null

# Enabling AppArmor.

echo "Enabling AppArmor."
systemctl enable apparmor --root=/mnt &>/dev/null

# Enabling pcscd

systemctl enable pcscd.service --root=/mnt &>/dev/null

# Enabling paccache

systemctl enable paccache.timer --root=/mnt &>/dev/null

# Enabling Firewalld.
echo "Enabling Firewalld."
systemctl enable firewalld --root=/mnt &>/dev/null

# Enabling Bluetooth Service (This is only to fix the visual glitch with gnome where it gets stuck in the menu at the top right).
# IF YOU WANT TO USE BLUETOOTH, YOU MUST REMOVE IT FROM THE LIST OF BLACKLISTED KERNEL MODULES IN /mnt/etc/modprobe.d/30_security-misc.conf

systemctl enable bluetooth --root=/mnt &>/dev/null

# Enabling Reflector timer.

echo "Enabling Reflector."
systemctl enable reflector.timer --root=/mnt &>/dev/null

# Enabling libvirt

systemctl enable libvirtd.service --root=/mnt &>/dev/null
systemctl enable virtlogd.service --root=/mnt &>/dev/null

# Disabling systemd-timesyncd

systemctl disable systemd-timesyncd --root=/mnt &>/dev/null

# Enabling chronyd

systemctl enable chronyd --root=/mnt &>/dev/null

# Finishing up

echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
