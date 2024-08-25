#!/bin/bash

set -e  # Skriptdə hər hansı bir əmrin uğursuz olması halında skripti dayandır

# Log Yazma Funksiyası
log() {
    local LEVEL=$1
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $LEVEL: $*"
}

# İcraatın Uğurlu Olmasını Yoxla
check_success() {
    if [ $? -ne 0 ]; then
        log "ERROR" "$1"
        exit 1
    fi
}

# Paketlərin mövcudluğunu yoxla
check_package() {
    dpkg -l | grep -q "^ii  $1 "
}

# Paketlərin quraşdırılması və konfiqurasiyası
install_packages() {
    log "INFO" "Paketlərin quraşdırılması..."
    sudo apt update -y
    sudo apt upgrade -y
    for pkg in "$@"; do
        if ! check_package $pkg; then
            sudo apt install -y $pkg
            check_success "Paketlərin quraşdırılması uğursuz oldu: $pkg"
        else
            log "INFO" "$pkg artıq quraşdırılıb."
        fi
    done
}

# Snap quraşdırılması
install_snap() {
    log "INFO" "Snap paket menecerinin quraşdırılması..."
    if ! check_package snapd; then
        sudo apt install -y snapd
        check_success "Snap quraşdırılması uğursuz oldu."
    else
        log "INFO" "Snap artıq quraşdırılıb."
    fi
}

# Flatpak quraşdırılması
install_flatpak() {
    log "INFO" "Flatpak quraşdırılması..."
    if ! check_package flatpak; then
        sudo apt install -y flatpak
        check_success "Flatpak quraşdırılması uğursuz oldu."
    else
        log "INFO" "Flatpak artıq quraşdırılıb."
    fi
}

# Paketlərin yenilənməsi
update_software() {
    log "INFO" "Software Update..."
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt autoremove -y
    check_success "Paketlərin yenilənməsi uğursuz oldu."
}

# Sistem Yeniləmələri
log "INFO" "Sistem yeniləmələri..."
install_packages \
    build-essential \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    unzip

# UFW Firewall aktivləşdirilməsi və SSH icazəsi
log "INFO" "UFW firewall aktivləşdirilir və SSH icazəsi..."
sudo ufw allow ssh
sudo ufw --force enable
check_success "UFW firewall konfiqurasiyası uğursuz oldu."

# SSH Təhlükəsizliyi
log "INFO" "SSH təhlükəsizliyi konfiqurasiyası..."

# Faylın mövcudluğunu və yazma icazələrini yoxlayın
if [ -f /etc/ssh/sshd_config ]; then
    if [ -w /etc/ssh/sshd_config ]; then
        log "INFO" "Fayl mövcuddur və yazma icazəsi var, dəyişiklik ediləcək..."
        
        # SSH konfiqurasiya dəyişiklikləri
        sudo sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config || log "ERROR" "SSH konfiqurasiya dəyişikliyi uğursuz oldu."
        sudo sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config || log "ERROR" "SSH port dəyişikliyi uğursuz oldu."
        
        sudo systemctl restart sshd || log "ERROR" "SSHD xidməti yenidən başlamadı."
    else
        log "ERROR" "Fayla yazma icazəsi yoxdur: /etc/ssh/sshd_config"
        exit 1
    fi
else
    log "ERROR" "Fayl mövcud deyil: /etc/ssh/sshd_config"
    exit 1
fi

# Zəruri Paketlərin Quraşdırılması
log "INFO" "Zəruri paketlərin quraşdırılması..."
install_packages \
    ufw \
    fail2ban \
    rsync \
    gnupg2 \
    lsb-release \
    ca-certificates \
    software-properties-common \
    tmux \
    screen \
    sudo \
    cron \
    logrotate \
    locales \
    bash-completion \
    zip \
    unzip \
    apt-transport-https \
    iputils-ping \
    netcat

# VDS serverlər üçün əlavə paketlər
log "INFO" "VDS serverlər üçün əlavə paketlərin quraşdırılması..."
install_packages \
    nmap \
    tcpdump \
    iperf \
    tree \
    python3-pip \
    ncdu \
    lynis \
    bmon \
    ifstat \
    iotop

# Swap Yaratmaq
log "INFO" "Swap faylı yaradılır..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    check_success "Swap faylının yaradılması uğursuz oldu."
else
    log "INFO" "Swap faylı artıq mövcuddur."
fi

# NTP Quraşdırılması
log "INFO" "NTP quraşdırılır..."
install_packages ntp
check_success "NTP quraşdırılması uğursuz oldu."

# Təhlükəsizlik Yoxlanışı
log "INFO" "Təhlükəsizlik yoxlanışı..."
install_packages lynis
sudo lynis audit system || log "ERROR" "Təhlükəsizlik yoxlanışı uğursuz oldu."

# Təhlükəsizlik Yoxlamalarının nəticələrini nəzərdən keçirin
log "INFO" "Təhlükəsizlik yoxlamasının nəticələri /var/log/lynis.log faylında qeyd edilib."

# Performans Tənzimləmələri
log "INFO" "Performans tənzimləmələri..."
# CPU frekansını optimallaşdırma
if [ -d /sys/devices/system/cpu/cpu*/cpufreq ]; then
    echo "1" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || log "ERROR" "CPU performans tənzimləməsi uğursuz oldu."
else
    log "WARNING" "CPU performans tənzimləmələri üçün fayllar mövcud deyil."
fi

# Disk təmizliyi
log "INFO" "Disk təmizliyi..."
ncdu / | tee /tmp/disk_usage.txt || log "ERROR" "Disk təmizliyi uğursuz oldu."

# Zaman Zona Konfiqurasiyası
log "INFO" "Zaman zona konfiqurasiyası..."
sudo timedatectl set-timezone "UTC" || log "ERROR" "Zaman zona konfiqurasiyası uğursuz oldu."

# Log fayllarının idarə edilməsi
log "INFO" "Log fayllarının idarə edilməsi..."
sudo logrotate -f /etc/logrotate.conf || log "ERROR" "Log fayllarının idarə edilməsi uğursuz oldu."

# Sistemin İşini İzləmə
log "INFO" "Sistemin işini izləmə..."
top -b -n 1 | head -n 20 | tee /tmp/system_usage.txt || log "ERROR" "Sistemin işinin izlənməsi uğursuz oldu."

# Sistem Yedəkləmə
log "INFO" "Sistem yedəkləmə..."
sudo rsync -av --delete /etc/ /var/backups/etc_backup/ || log "ERROR" "Sistem yedəkləməsi uğursuz oldu."

# Sistem Təmizliyi
log "INFO" "Sistem təmizlənir..."
sudo apt autoremove -y
sudo apt clean || log "ERROR" "Sistem təmizlənməsi uğursuz oldu."

# Snap və Flatpak quraşdırılması
install_snap
install_flatpak

# Paketlərin Yenilənməsi
update_software

# Quraşdırma tamamlandı
log "INFO" "Sistem hazırdır! Yenidən başlatmaq lazımdır."

# Sistemi yenidən başlatmaq (isteğe bağlı)
read -p "Sistemi yenidən başlatmaq istəyirsinizmi? (y/n): " REBOOT
if [ "$REBOOT" = "y" ]; then
    sudo reboot
fi
