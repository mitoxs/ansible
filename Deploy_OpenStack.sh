#!/bin/bash

set -e  # Arrêter le script en cas d'erreur
LOGFILE="/var/log/deploy_openstack.log"
ERRFILE="/var/log/deploy_openstack_errors.log"
exec > >(tee -a "$LOGFILE") 2> >(tee -a "$ERRFILE" >&2)

# Demande des variables à l'utilisateur
echo "Entrez le nom de l'utilisateur Debian : "
read -r debian_user
echo "Entrez le nom de l'utilisateur Ansible : "
read -r ansible_user
echo "Entrez l'adresse IP du serveur cible : "
read -r target_host

# Fonction pour vérifier si un utilisateur existe déjà
user_exists() {
    id "$1" &>/dev/null
}

# Création des utilisateurs s'ils n'existent pas encore
if ! user_exists "$debian_user"; then
    sudo adduser --disabled-password --gecos "" "$debian_user"
fi
if ! user_exists "$ansible_user"; then
    sudo adduser --disabled-password --gecos "" "$ansible_user"
fi

# Ajout des utilisateurs au groupe sudo
sudo usermod -aG sudo "$debian_user"
sudo usermod -aG sudo "$ansible_user"

# Installation d'OpenSSH Server
if ! dpkg -l | grep -q openssh-server; then
    sudo apt update && sudo apt install -y openssh-server
fi

# Génération de la clé SSH
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
fi

# Copie de la clé SSH vers la machine cible
echo "Test de connexion à $target_host..."
if ! ssh -o BatchMode=yes "$debian_user@$target_host" exit; then
    ssh-copy-id "$debian_user@$target_host"
fi

# Installation de Python et Ansible
if ! command -v ansible &>/dev/null; then
    sudo apt install -y python3-venv
    python3 -m venv ~/ansible
    source ~/ansible/bin/activate
    pip install --upgrade pip
    pip install ansible
fi

# Configuration de SSH-Agent
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa
fi

# Désactivation des avertissements Ansible
echo -e "[defaults]\ninterpreter_python=auto_silent" | sudo tee /etc/ansible/ansible.cfg > /dev/null

# Création d'un inventaire Ansible
echo -e "[openstack]\n$target_host ansible_python_interpreter=auto_silent" | sudo tee /etc/ansible/hosts > /dev/null

# Sécurisation des fichiers SSH
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Configuration d'Ansible Vault
echo "Entrez un mot de passe pour Ansible Vault : "
read -s ansible_vault_pass
echo "$ansible_vault_pass" > ~/.ansible_vault_pass
chmod 600 ~/.ansible_vault_pass
echo "vault_password_file = ~/.ansible_vault_pass" | sudo tee -a /etc/ansible/ansible.cfg > /dev/null

echo "Déploiement initial terminé. Vous pouvez maintenant utiliser Ansible pour gérer OpenStack."
