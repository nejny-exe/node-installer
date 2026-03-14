#!/bin/bash

# Цвета
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}>>> Запуск комплексной настройки сервера${NC}"

# 1. Системные обновления и база
apt update && apt upgrade -y
apt install -y curl wget fail2ban ufw jq

# 2. Установка Docker
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}>>> Установка Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

# 3. Настройка Firewall
ufw allow 22/tcp
ufw allow 2222/tcp
ufw allow 45876/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

# 4. Сбор данных для Remnanode
echo -e "${YELLOW}--- Настройка Remnanode ---${NC}"
read -p "Введите SECRET_KEY для ноды (или Enter для автогенерации): " REMNA_SECRET
if [ -z "$REMNA_SECRET" ]; then
    REMNA_SECRET=$(openssl rand -hex 16)
    echo -e "Сгенерирован ключ: ${GREEN}$REMNA_SECRET${NC}"
fi

# 5. Опрос по Beszel
echo -e "${YELLOW}--- Настройка Beszel Agent ---${NC}"
read -p "Настраиваем Beszel сейчас? (y/n): " SETUP_BESZEL

if [[ "$SETUP_BESZEL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    read -p "Введите KEY: " B_KEY
    read -p "Введите TOKEN: " B_TOKEN
    read -p "Введите HUB_URL: " B_URL
else
    echo -e "${YELLOW}Ок, создам конфиг с пустыми значениями.${NC}"
    B_KEY="YOUR_KEY_HERE"
    B_TOKEN="YOUR_TOKEN_HERE"
    B_URL="YOUR_HUB_URL_HERE"
fi

# 6. Создание директорий и файлов
mkdir -p /opt/remnanode /opt/beszel

# Конфиг Remnanode
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
      - SECRET_KEY="$REMNA_SECRET"
EOF

# Конфиг Beszel
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
echo -e "${GREEN}>>> Запуск Remnanode...${NC}"
cd /opt/remnanode && docker compose up -d && docker compose logs -f -t

if [[ "$SETUP_BESZEL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${GREEN}>>> Запуск Beszel Agent...${NC}"
    cd /opt/beszel && docker compose up -d
else
    echo -e "${YELLOW}>>> Beszel Agent не запущен (заполните /opt/beszel/docker-compose.yml и запустите вручную)${NC}"
fi

# 8. Fail2Ban
cat <<EOF > /etc/fail2ban/jail.d/custom.local
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 1h
EOF
systemctl restart fail2ban

echo -e "${GREEN}Готово! Данные сохранены в /opt/${NC}"
