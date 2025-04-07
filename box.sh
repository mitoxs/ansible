#!/bin/bash

# Mise à jour du système et installation des dépendances
apt update && apt upgrade -y
apt install -y git curl

# Installation de Docker et Docker Compose
curl -fsSL https://get.docker.com | bash
apt install -y docker-compose
systemctl enable docker
systemctl start docker

# Clonage du dépôt NetBox Docker
git clone -b release https://github.com/netbox-community/netbox-docker.git
cd netbox-docker

# Configuration des ports (optionnel)
cat <<EOF > docker-compose.override.yml
version: '3.4'
services:
  netbox:
    ports:
      - "8000:8080"
EOF

# Téléchargement des images et démarrage des conteneurs
docker compose pull
docker compose up -d

echo "NetBox est en cours d'exécution sur http://localhost:8000"

# Création d'un utilisateur administrateur
docker compose exec netbox /opt/netbox/netbox/manage.py createsuperuser

# Clonage du dépôt de la bibliothèque de types d’appareils
cd ..
git clone https://github.com/netbox-community/devicetype-library.git
cd devicetype-library

# Clonage du script d'importation
git clone https://github.com/netbox-community/Device-Type-Library-Import.git
cd Device-Type-Library-Import

# Configuration de l'environnement Python
apt install -y python3 python3-venv python3-pip
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configuration des variables d'environnement
cp .env.example .env
echo "Veuillez éditer le fichier .env pour y insérer l'URL de NetBox et votre token d'API."

echo "Déploiement terminé ! NetBox est disponible sur http://localhost:8000"

