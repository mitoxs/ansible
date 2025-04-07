#!/bin/bash

set -e

# --- Configuration ---
NETBOX_USER=netbox
NETBOX_DIR=/opt/netbox
NETBOX_BRANCH=master
NETBOX_VERSION=latest
NETBOX_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')
DB_NAME=netbox
DB_USER=netbox
DB_PASS=$(openssl rand -base64 32)
ALLOWED_HOSTS="localhost 127.0.0.1"

# --- Prérequis ---
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv python3-dev \
               libpq-dev libjpeg-dev libxml2-dev libxslt1-dev libffi-dev \
               libssl-dev zlib1g-dev redis postgresql nginx git curl \
               build-essential supervisor

# --- PostgreSQL ---
echo "Création de la base PostgreSQL..."
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

# --- NetBox ---
echo "Installation de NetBox..."
useradd -r -d $NETBOX_DIR -s /bin/false $NETBOX_USER || true
mkdir -p $NETBOX_DIR
cd /opt
git clone -b $NETBOX_BRANCH https://github.com/netbox-community/netbox.git
cd $NETBOX_DIR

cp netbox/netbox/configuration.example.py netbox/netbox/configuration.py

sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = \[$(echo $ALLOWED_HOSTS | sed 's/ /, /g' | sed 's/\([^, ]\+\)/'\''\1'\''/g')\]/" netbox/netbox/configuration.py
sed -i "s/^DATABASE =.*/DATABASE = {\n    'NAME': '$DB_NAME',\n    'USER': '$DB_USER',\n    'PASSWORD': '$DB_PASS',\n    'HOST': 'localhost',\n    'PORT': '',\n}/" netbox/netbox/configuration.py
sed -i "s/^SECRET_KEY = .*/SECRET_KEY = '$NETBOX_SECRET_KEY'/" netbox/netbox/configuration.py

python3 -m venv /opt/netbox/venv
source /opt/netbox/venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

./manage.py migrate
./manage.py collectstatic --no-input
./manage.py createsuperuser

# --- Gunicorn systemd ---
echo "Configuration de Gunicorn et systemd..."
cp contrib/gunicorn.py /opt/netbox/gunicorn.py

cat <<EOF >/etc/systemd/system/netbox.service
[Unit]
Description=NetBox WSGI Service
After=network.target

[Service]
Type=simple
User=$NETBOX_USER
Group=$NETBOX_USER
WorkingDirectory=$NETBOX_DIR/netbox
ExecStart=$NETBOX_DIR/venv/bin/gunicorn --config $NETBOX_DIR/gunicorn.py netbox.wsgi
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- Nginx ---
echo "Configuration de Nginx..."
cat <<EOF >/etc/nginx/sites-available/netbox
server {
    listen 80;
    server_name _;
    client_max_body_size 25m;

    location /static/ {
        alias $NETBOX_DIR/netbox/static/;
    }

    location / {
        proxy_pass http://localhost:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/netbox
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# --- Finalisation ---
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now netbox

echo "✅ NetBox est déployé et opérationnel !"
echo "🌐 Accédez à NetBox via http://<IP_DE_VOTRE_SERVEUR>"
