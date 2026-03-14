#!/bin/bash

# Цвета
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}>>> Настройка системы (Docker, UFW, Fail2Ban)${NC}"

# 1. Базовая установка
apt update && apt upgrade -y
apt install -y curl wget fail2ban ufw jq

# 2. Docker
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

# 3. Firewall
ufw allow 22/tcp
ufw allow 2222/tcp
ufw allow 45876/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

# 4. Создание директорий
mkdir -p /opt/remnanode /opt/beszel

# 5. Настройка Remnanode
echo -e "${YELLOW}>>> Настройка Remnanode...${NC}"
echo "Вставьте SECRET_KEY и нажмите Enter:"
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

# 6. Настройка Beszel
echo -e "${YELLOW}>>> Настройка Beszel Agent...${NC}"
read -p "Настраиваем Beszel сейчас? (y/n): " SETUP_BESZEL

if [[ "$SETUP_BESZEL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    read -p "Введите KEY (public key): " B_KEY
    read -p "Введите TOKEN: " B_TOKEN
    read -p "Введите HUB_URL: " B_URL
else
    B_KEY="PLACEHOLDER"
    B_TOKEN="PLACEHOLDER"
    B_URL="PLACEHOLDER"
fi

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

# 7. Запуск
echo -e "${GREEN}>>> Запуск сервисов...${NC}"
cd /opt/remnanode && docker compose up -d

if [[ "$SETUP_BESZEL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    cd /opt/beszel && docker compose up -d
fi

# 8. Fail2Ban
cat <<EOF > /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 1h
EOF
systemctl restart fail2ban

echo -e "${GREEN}Установка завершена! Проверьте логи: docker logs remnanode${NC}"
