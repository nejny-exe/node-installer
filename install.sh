#!/bin/bash

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (sudo)."
  exit
fi

echo "--- Настройка системы и установка компонентов ---"

# 1. Обновление системы
apt update && apt upgrade -y

# 2. Установка базовых утилит, Docker, Fail2Ban и UFW
apt install -y curl wget git fail2ban ufw apt-transport-https ca-certificates software-properties-common

# Установка Docker (официальный скрипт)
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

# 3. Настройка UFW (Файрвол)
echo "--- Настройка портов ---"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp          # SSH
ufw allow 80/tcp          # HTTP
ufw allow 443/tcp         # HTTPS
ufw allow 45876/tcp       # Beszel Agent Default Port
ufw allow 443/udp         # Для протоколов VPN (Reality/etc)
ufw --force enable

# 4. Запрос данных у пользователя
echo "--- Ввод данных для конфигурации ---"
read -p "Введите KEY для Beszel Agent: " BESZEL_KEY
read -p "Введите TOKEN для Beszel Agent: " BESZEL_TOKEN
read -p "Введите HUB_URL для Beszel Agent (например, https://hub.example.com): " BESZEL_HUB_URL

# 5. Настройка Remnanode
echo "--- Установка Remnanode ---"
mkdir -p /opt/remnanode
cat <<EOF > /opt/remnanode/docker-compose.yml
services:
  remnanode:
    image: remnawave/remnanode:latest
    container_name: remnanode
    restart: unless-stopped
    network_mode: host
    volumes:
      - /etc/remnanode:/etc/remnanode
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - NODE_NAME=Sand-VPN-Node
      # Добавьте специфичные переменные Remnanode, если требуется
EOF

# 6. Настройка Beszel Agent
echo "--- Установка Beszel Agent ---"
mkdir -p /opt/beszel
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
      KEY: "$BESZEL_KEY"
      TOKEN: "$BESZEL_TOKEN"
      HUB_URL: "$BESZEL_HUB_URL"
EOF

# 7. Запуск контейнеров
echo "--- Запуск сервисов ---"
cd /opt/remnanode && docker compose up -d
cd /opt/beszel && docker compose up -d

# 8. Настройка Fail2Ban для защиты SSH
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
EOF

systemctl restart fail2ban

echo "--- Установка завершена! ---"
echo "Remnanode: /opt/remnanode"
echo "Beszel Agent: /opt/beszel"
echo "Статус портов:"
ufw status
