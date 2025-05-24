#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://zammad.com

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ZAMMAD_VERSION="6.0.0"
ZAMMAD_STABLE="stable-6.0"
msg_info "Installing Zammad Version 6.0.0"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  gpg \
  nginx \
  apt-transport-https \
  gnupg
msg_ok "Installed Dependencies"

msg_info "Setting up Elasticsearch"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list >/dev/null
$STD apt-get update
$STD apt-get -y install elasticsearch
echo "-Xms2g" >>/etc/elasticsearch/jvm.options
echo "-Xmx2g" >>/etc/elasticsearch/jvm.options
$STD /usr/share/elasticsearch/bin/elasticsearch-plugin install ingest-attachment -b
systemctl enable -q elasticsearch
systemctl restart -q elasticsearch
msg_ok "Setup Elasticsearch"

msg_info "Installing Zammad"
curl -fsSL https://dl.packager.io/srv/zammad/zammad/key | gpg --dearmor | sudo tee /etc/apt/keyrings/pkgr-zammad.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/pkgr-zammad.gpg] https://dl.packager.io/srv/deb/zammad/zammad/${ZAMMAD_STABLE}/debian 12 main" | sudo tee /etc/apt/sources.list.d/zammad.list >/dev/null
$STD apt-get update

msg_info "Installing Zammad version ${ZAMMAD_VERSION}"

# Create apt preferences to pin version
cat > /etc/apt/preferences.d/zammad << EOF
Package: zammad
Pin: version ${ZAMMAD_VERSION}*
Pin-Priority: 1001
EOF

# Install specific version
$STD apt-get -y install zammad=${ZAMMAD_VERSION}*

# Create version info file
echo "${ZAMMAD_VERSION}" > /opt/zammad/VERSION
chown zammad:zammad /opt/zammad/VERSION

msg_ok "Installed Zammad ${ZAMMAD_VERSION}"

msg_info "Configuring Elasticsearch Integration"
$STD zammad run rails r "Setting.set('es_url', 'http://localhost:9200')"
$STD zammad run rake zammad:searchindex:rebuild
msg_ok "Configured Elasticsearch Integration"

msg_info "Setup Services"
cp /opt/zammad/contrib/nginx/zammad.conf /etc/nginx/sites-available/zammad.conf
IPADDRESS=$(hostname -I | awk '{print $1}')
sed -i "s/server_name localhost;/server_name $IPADDRESS;/g" /etc/nginx/sites-available/zammad.conf
$STD systemctl reload nginx
msg_ok "Created Service"

# Create backup directory for future migrations
mkdir -p /opt/zammad-backup
chown zammad:zammad /opt/zammad-backup

# Add version info to motd if specific version was installed
cat >> /etc/motd << EOF

Zammad Version: ${ZAMMAD_VERSION}
EOF

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
