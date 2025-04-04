#!/bin/bash

# Mettre à jour les paquets
sudo apt update && sudo apt upgrade -y

# Installer les dépendances
sudo apt install -y python3 python3-pip python3-venv ansible

# Créer un environnement virtuel Python
mkdir -p ~/venv
python3 -m venv ~/venv/ansible_env

# Activer l'environnement virtuel et installer Ansible
source ~/venv/ansible_env/bin/activate
pip install --upgrade pip
pip install ansible

# Vérifier l'installation
ansible --version

echo "Installation et configuration d'Ansible terminées !"

# Définir le nom de l'utilisateur
USERNAME="nouvel_utilisateur"

# Ajouter l'utilisateur et définir un mot de passe (à modifier en conséquence)
sudo adduser --gecos "" $USERNAME
sudo passwd $USERNAME

# Créer le dossier .ssh
sudo mkdir -p /home/$USERNAME/.ssh
sudo chown $USERNAME:$USERNAME /home/$USERNAME/.ssh
sudo chmod 700 /home/$USERNAME/.ssh

# Générer la clé SSH sans mot de passe
sudo -u $USERNAME ssh-keygen -t rsa -b 4096 -f /home/$USERNAME/.ssh/id_rsa -N ""

# Afficher la clé publique
echo "Clé publique générée :"
cat /home/$USERNAME/.ssh/id_rsa.pub

echo "L'utilisateur $USERNAME et ses clés SSH ont été créés avec succès !"
echo "Pour activer l'environnement virtuel Python, utilisez : source ~/venv/ansible_env/bin/activate"
