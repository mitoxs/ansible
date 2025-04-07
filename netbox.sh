#!/bin/bash

# Mise à jour du système
apt update && apt upgrade -y

# Installation des dépendances
apt install -y python3 python3-pip python3-venv python3-dev build-essential libffi-dev \
               libssl-dev libxml2-dev libxslt1-dev libpq-dev libmysqlclient-dev \
               libjpeg-dev libldap2-dev libsasl2-dev git unzip curl

# Installation et configuration de PostgreSQL
apt install -y postgresql postgresql-contrib
systemctl enable postgresql
systemctl start postgresql

sudo -u postgres psql <<EOF
CREATE DATABASE netbox;
CREATE USER netbox WITH PASSWORD 'netbox';
ALTER ROLE netbox SET client_encoding TO 'utf8';
ALTER ROLE netbox SET default_transaction_isolation TO 'read committed';
ALTER ROLE netbox SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;
EOF

# Installation et configuration de Redis
apt install -y redis
systemctl enable redis
systemctl start redis

# Clonage de NetBox
cd /opt
git clone -b v3.6 https://github.com/netbox-community/netbox.git
cd netbox
cp netbox/configuration.example.py netbox/configuration.py

# Configuration du fichier NetBox
sed -i "s/POSTGRES_DB = 'netbox'/POSTGRES_DB = 'netbox'/g" netbox/configuration.py
sed -i "s/POSTGRES_USER = 'netbox'/POSTGRES_USER = 'netbox'/g" netbox/configuration.py
sed -i "s/POSTGRES_PASSWORD = ''/POSTGRES_PASSWORD = 'netbox'/g" netbox/configuration.py

# Création de l'environnement virtuel et installation des dépendances
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Migration de la base de données et collecte des fichiers statiques
./manage.py migrate
./manage.py collectstatic --no-input

# Création du compte superutilisateur
echo "from django.contrib.auth import get_user_model; get_user_model().objects.create_superuser('admin', 'admin@example.com', 'admin')" | ./manage.py shell

# Installation et configuration de gunicorn et supervisord
apt install -y gunicorn supervisor

cat <<EOF > /etc/supervisor/conf.d/netbox.conf
[program:netbox]
command=/opt/netbox/venv/bin/gunicorn --workers 3 --bind unix:/run/netbox.sock netbox.wsgi
directory=/opt/netbox
user=root
autostart=true
autorestart=true
stderr_logfile=/var/log/netbox.err.log
stdout_logfile=/var/log/netbox.out.log
EOF

systemctl restart supervisor

echo "Installation et configuration de NetBox terminées ! Accédez-y sur http://<adresse-ip>:8000"
