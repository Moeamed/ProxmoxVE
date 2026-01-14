#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Claude (Assistant)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/chiefonboarding/ChiefOnboarding

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  gpg \
  ca-certificates \
  apt-transport-https
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
msg_ok "Installed Docker"

msg_info "Setting up ${APPLICATION}"
mkdir -p /opt/chiefonboarding
cd /opt/chiefonboarding

# Generate secure secrets
SECRET_KEY=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 16)

# Create docker-compose.yml
cat <<EOF >/opt/chiefonboarding/docker-compose.yml
version: '3'

services:
  db:
    image: postgres:15-alpine
    container_name: chiefonboarding-db
    restart: unless-stopped
    volumes:
      - pgdata:/var/lib/postgresql/data/
    environment:
      - POSTGRES_DB=chiefonboarding
      - POSTGRES_USER=chiefonboarding
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U chiefonboarding"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: chiefonboarding/chiefonboarding:latest
    container_name: chiefonboarding-app
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - DATABASE_URL=postgres://chiefonboarding:${DB_PASSWORD}@db:5432/chiefonboarding
      - ALLOWED_HOSTS=*
      - HTTP_INSECURE=True
    depends_on:
      db:
        condition: service_healthy

volumes:
  pgdata:
EOF

# Create environment file for reference
cat <<EOF >/opt/chiefonboarding/.env
# ChiefOnboarding Configuration
SECRET_KEY=${SECRET_KEY}
DATABASE_URL=postgres://chiefonboarding:${DB_PASSWORD}@db:5432/chiefonboarding
ALLOWED_HOSTS=*

# Optional: Email Configuration (uncomment and configure)
# EMAIL_HOST=smtp.example.com
# EMAIL_PORT=587
# EMAIL_HOST_USER=your-email@example.com
# EMAIL_HOST_PASSWORD=your-password
# EMAIL_USE_TLS=True
# DEFAULT_FROM_EMAIL=noreply@example.com

# Optional: Slack Integration
# SLACK_APP_TOKEN=
# SLACK_SIGNING_SECRET=
# SLACK_BOT_TOKEN=

# Optional: AWS S3 for file storage
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# AWS_STORAGE_BUCKET_NAME=
# AWS_S3_REGION_NAME=
EOF

chmod 600 /opt/chiefonboarding/.env
msg_ok "Set up ${APPLICATION}"

msg_info "Pulling Docker Images"
cd /opt/chiefonboarding
$STD docker compose pull
msg_ok "Pulled Docker Images"

msg_info "Starting ${APPLICATION}"
$STD docker compose up -d
msg_ok "Started ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/chiefonboarding.service
[Unit]
Description=ChiefOnboarding Container Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/chiefonboarding
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now chiefonboarding.service
msg_ok "Created Service"

# Get version
RELEASE=$(curl -fsSL https://api.github.com/repos/chiefonboarding/ChiefOnboarding/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
