#!/bin/bash

# Цвета
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Исправление ошибки "unable to resolve host"
fix_hostname() {
    if ! grep -q "$(hostname)" /etc/hosts; then
        echo "127.0.1.1 $(hostname)" | sudo tee -a /etc/hosts > /dev/null
    fi
}

# --- БЛОК ПРОВЕРОК ---

check_system() {
    fix_hostname
    echo -e "${YELLOW}>>> Инспекция системы...${NC}"
    
    # 1. Проверка базовых утилит
    for pkg in curl wget fail2ban ufw jq openssl; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "${GREEN}[OK] $pkg уже установлен.${NC}"
        else
            echo -e "${YELLOW}[!] Установка $pkg...${NC}"
            apt update && apt install -y "$pkg"
        fi
    done

    # 2. Проверка Docker
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] Docker найден: $(docker --version | awk '{print $3}' | tr -d ',')${NC}"
    else
        echo -e "${YELLOW}[!] Docker не найден. Начинаю установку...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh && rm get-docker.sh
    fi

    # 3. Проверка UFW
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}[OK] Firewall (UFW) уже настроен и активен.${NC}"
    else
        echo -e "${YELLOW}[!] Настройка портов UFW...${NC}"
        ufw allow 22/tcp
        ufw allow 2222/tcp
        ufw allow 45876/tcp
        ufw allow 443/tcp
        ufw allow 443/udp
        ufw --force enable
    fi

    # 4. Проверка Fail2Ban
    if [ -f "/etc/fail2ban/jail.d/custom.local" ]; then
        echo -e "${GREEN}[OK] Конфиг защиты SSH (Fail2Ban) на месте.${NC}"
    else
        echo -e "${YELLOW}[!] Создание защиты Fail2Ban...${NC}"
        cat <<EOF > /etc/fail2ban/jail.d/custom.local
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 1h
EOF
        systemctl restart fail2ban
    fi
}

# --- БЛОК УСТАНОВКИ КОМПОНЕНТОВ ---

install_remnanode() {
    echo -e "\n${CYAN}--- Конфигурация Remnanode ---${NC}"
    if [ -f "/opt/remnanode/docker-compose.yml" ]; then
        echo -e "${RED} ПРЕДУПРЕЖДЕНИЕ: Конфигурация Remnanode уже существует!${NC}"
        read -p "Вы уверены, что хотите ПОЛНОСТЬЮ ЗАМЕНИТЬ текущий конфиг? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo -e "${YELLOW}Установка отменена. Старый конфиг сохранен.${NC}"
            return
        fi
    fi

    mkdir -p /opt/remnanode
    echo -e "${YELLOW}Вставьте ваш SECRET_KEY (Base64) и нажмите Enter:${NC}"
    read -r REMNA_SECRET
    
    cat <<EOF > /opt/remnanode/docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=$REMNA_SECRET
EOF
    cd /opt/remnanode && docker compose up -d
    echo -e "${GREEN}✔ Remnanode запущен.${NC}"
}

install_beszel() {
    echo -e "\n${CYAN}--- Конфигурация Beszel Agent ---${NC}"
    if [ -f "/opt/beszel/docker-compose.yml" ]; then
        echo -e "${RED} ПРЕДУПРЕЖДЕНИЕ: Конфигурация Beszel Agent уже существует!${NC}"
        read -p "Вы уверены, что хотите ПОЛНОСТЬЮ ЗАМЕНИТЬ текущий конфиг? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo -e "${YELLOW}Установка отменена. Старый конфиг сохранен.${NC}"
            return
        fi
    fi

    mkdir -p /opt/beszel
    read -p "Введите KEY: " B_KEY
    read -p "Введите TOKEN: " B_TOKEN
    read -p "Введите HUB_URL: " B_URL

    cat <<EOF > /opt/beszel/docker-compose.yml
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./beszel_agent_data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: 45876
      KEY: "$B_KEY"
      TOKEN: "$B_TOKEN"
      HUB_URL: "$B_URL"
EOF
    cd /opt/beszel && docker compose up -d
    echo -e "${GREEN}✔ Beszel Agent запущен.${NC}"
}

# --- ГЛАВНОЕ МЕНЮ ---

show_menu() {
    echo -e "\n${CYAN}==========================================${NC}"
    echo -e "${CYAN}        МЕНЕДЖЕР УСТАНОВКИ НОДЫ           ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "1) Установить/Обновить Remnanode"
    echo -e "2) Установить/Обновить Beszel Agent"
    echo -e "3) Установить ВСЁ (Remnanode + Beszel)"
    echo -e "4) Выход"
    echo -e "${CYAN}==========================================${NC}"
    read -p "Выберите вариант [1-4]: " choice

    case $choice in
        1)
            check_system
            install_remnanode
            ;;
        2)
            check_system
            install_beszel
            ;;
        3)
            check_system
            install_remnanode
            install_beszel
            ;;
        4)
            echo -e "${YELLOW}Завершение работы.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ошибка: выберите пункт от 1 до 4.${NC}"
            sleep 1
            show_menu
            ;;
    esac
}

# Запуск программы
show_menu
