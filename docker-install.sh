#!/bin/bash

# Log faylı
LOG_FILE="/var/log/docker-install.log"
exec > >(tee -a $LOG_FILE) 2>&1

# Funksiya: Səhv baş verdikdə skripti dayandırmaq və tədbir görmək
handle_error() {
    local error_msg=$1
    local error_code=$2
    local service=$3

    echo "Səhv baş verdi: $error_msg"
    echo "$(date): Səhv baş verdi: $error_msg" >> $LOG_FILE

    case $error_code in
        1)  # Sistem yeniləmələri və ya paket quraşdırılması ilə bağlı səhvlər
            echo "Avtomatik tədbir: Problemin həlli üçün paketlərin yenidən quraşdırılması cəhd edilir..."
            sudo apt-get update -y
            sudo apt-get upgrade -y
            ;;
        2)  # Xidmətlərin başlamaması
            echo "Avtomatik tədbir: Xidmətin yenidən başladılması cəhd edilir..."
            if [ -n "$service" ]; then
                sudo systemctl restart $service
            fi
            ;;
        3)  # Firewall və ya digər konfiqurasiya problemləri
            echo "Avtomatik tədbir: Konfiqurasiya problemlərinin həlli üçün yenidən konfiqurasiya edilməsi cəhd edilir..."
            sudo ufw --force reset
            sudo ufw allow 2376/tcp
            sudo ufw allow 7946/tcp
            sudo ufw allow 7946/udp
            sudo ufw allow 4789/udp
            sudo ufw --force enable
            ;;
        *)
            echo "Avtomatik tədbir tapılmadı. Əlavə müayinə tələb olunur."
            ;;
    esac

    # Problemi təkrar yoxlayın
    if [ $error_code -eq 2 ]; then
        if [ -n "$service" ]; then
            systemctl is-active --quiet $service
            if [ $? -ne 0 ]; then
                echo "Təkrar yoxlama: Xidmət hələ də işləməyir. Əlavə müayinə tələb olunur."
            else
                echo "Xidmət uğurla yenidən başladıldı."
            fi
        fi
    fi

    exit 1
}

# Funksiya: Xidmətin işlədiyini yoxlamaq
check_service() {
    local service=$1
    systemctl is-active --quiet $service
    if [ $? -eq 0 ]; then
        echo "$service xidməti işləyir."
    else
        echo "$service xidməti işləməyir."
        handle_error "$service xidməti işləməyib." 2 $service
    fi
}

# Funksiya: Docker Compose versiyasını yoxlamaq
check_docker_compose_version() {
    local expected_version=$1
    local installed_version=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
    if [ "$installed_version" == "$expected_version" ]; then
        echo "Docker Compose versiyası uyğundur: $installed_version"
    else
        echo "Docker Compose versiyası uyğunsuz: Quraşdırılmış $installed_version, gözlənilən $expected_version"
        handle_error "Docker Compose versiyası uyğunsuzdur." 1
    fi
}

# Funksiya: Paketlərin quraşdırılmasını yoxlamaq
check_package_installation() {
    local package=$1
    dpkg -l | grep -qw $package
    if [ $? -eq 0 ]; then
        echo "$package quraşdırılıb."
    else
        echo "$package quraşdırılmayıb."
        handle_error "$package quraşdırılmayıb." 1
    fi
}

# Skriptin başlaması
echo "Docker və Docker Compose quraşdırılır..."

# Sistem yeniləmələri
echo "Sistem yeniləmələri..."
sudo apt-get update -y || handle_error "Sistem yeniləmələri uğursuz oldu." 1
sudo apt-get upgrade -y || handle_error "Sistem yeniləmələri uğursuz oldu." 1

# Təmizləmə
echo "Təmizləmə..."
sudo apt-get autoremove -y || handle_error "Təmizləmə uğursuz oldu." 1
sudo apt-get autoclean -y || handle_error "Təmizləmə uğursuz oldu." 1

# Lazım olan paketlərin quraşdırılması
echo "Lazım olan paketlərin quraşdırılması..."
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common || handle_error "Paketlərin quraşdırılması uğursuz oldu." 1

# Docker GPG açarını əlavə edin
echo "Docker GPG açarını əlavə edin..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - || handle_error "Docker GPG açarının əlavə edilməsi uğursuz oldu." 1

# Docker repo əlavə edin
echo "Docker reposunu əlavə edin..."
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || handle_error "Docker reposunun əlavə edilməsi uğursuz oldu." 1

# Yenidən paketlərin siyahısını yeniləyin
echo "Paketlərin siyahısını yeniləyin..."
sudo apt-get update -y || handle_error "Paketlərin siyahısının yenilənməsi uğursuz oldu." 1

# Docker quraşdırın
echo "Docker quraşdırılır..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io || handle_error "Docker quraşdırılması uğursuz oldu." 1

# Docker Compose versiyası
COMPOSE_VERSION="2.15.0"  # Versiyanı rəsmi saytından yoxlayın

# Docker Compose quraşdırın
echo "Docker Compose quraşdırılır..."
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || handle_error "Docker Compose yüklənməsi uğursuz oldu." 1
sudo chmod +x /usr/local/bin/docker-compose || handle_error "Docker Compose icazələrinin təyin edilməsi uğursuz oldu." 1

# Docker Compose versiyasını yoxlayın
check_docker_compose_version $COMPOSE_VERSION

# İstifadəçi qrupuna əlavə edin
echo "İstifadəçi qrupuna əlavə edilirsiniz..."
sudo usermod -aG docker $USER || handle_error "İstifadəçi qrupuna əlavə edilmə uğursuz oldu." 1

# Docker daemon konfiqurasiyası (isteğe bağlı)
DOCKER_DAEMON_CONF="/etc/docker/daemon.json"
echo "Docker daemon konfiqurasiyası..."
if [ ! -f "$DOCKER_DAEMON_CONF" ]; then
    echo '{
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "100m",
        "max-file": "3"
      },
      "storage-driver": "overlay2"
    }' | sudo tee $DOCKER_DAEMON_CONF || handle_error "Docker daemon konfiqurasiyası uğursuz oldu." 1
    sudo systemctl restart docker || handle_error "Docker xidmətinin yenidən başladılması uğursuz oldu." 2
fi

# Docker xidmətlərinin avtomatik başlamaq üçün konfiqurasiya
echo "Docker xidmətlərinin avtomatik başlamaq üçün konfiqurasiya..."
sudo systemctl enable docker || handle_error "Docker xidmətinin avtomatik başlamaq üçün konfiqurasiyası uğursuz oldu." 1

# Firewall konfiqurasiyası
echo "Firewall konfiqurasiyası..."
sudo ufw allow 2376/tcp   # Docker Daemon API
sudo ufw allow 7946/tcp   # Docker Swarm Management
sudo ufw allow 7946/udp   # Docker Swarm Management
sudo ufw allow 4789/udp   # Docker Overlay Network

# Firewall-i aktivləşdir
echo "Firewall-i aktivləşdir..."
sudo ufw --force enable || handle_error "Firewall-i aktivləşdirmək uğursuz oldu." 3

# NTP quraşdırılması (saatın düzgün qurulması üçün)
echo "NTP quraşdırılması..."
sudo apt-get install -y ntp || handle_error "NTP quraşdırılması uğursuz oldu." 1

# Təhlükəsizlik təkmilləşdirmələri
echo "Təhlükəsizlik təkmilləşdirmələri..."
sudo apt-get install -y fail2ban || handle_error "Fail2ban quraşdırılması uğursuz oldu." 1

# Xidmətlərin statusunu yoxlamaq
echo "Xidmətlərin statusunu yoxlayır..."
check_service docker
check_service ntp
check_service fail2ban

# Quraşdırma tamamlandı
echo "Docker və Docker Compose quraşdırıldı və konfiqurasiya edildi. NTP və Fail2ban quraşdırıldı."

# Quraşdırma sonrası tövsiyələr
echo "Siz sisteminizi yenidən başlatmaqla, dəyişiklikləri tətbiq edə bilərsiniz."

# Yenidən başlatma
echo "Sistemi yenidən başlatmaq istəyirsinizmi? (yes/no)"
read REBOOT
if [ "$REBOOT" == "yes" ]; then
    sudo reboot
fi
