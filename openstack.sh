#!/bin/bash

# Fonction de gestion des erreurs
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Demande interactive pour les variables
read -p "Entrez le nom d'utilisateur pour Debian : " debian_user
read -p "Entrez le nom d'utilisateur pour Ansible : " ansible_user
read -p "Entrez l'adresse IP ou le nom d'hôte cible : " target_host

# Vérification des variables
[[ -z "$debian_user" ]] && error_exit "L'utilisateur Debian est requis."
[[ -z "$ansible_user" ]] && error_exit "L'utilisateur Ansible est requis."
[[ -z "$target_host" ]] && error_exit "L'hôte cible est requis."

# Variables de logs
LOGFILE="/var/log/deploy_openstack.log"
ERRFILE="/var/log/deploy_openstack_errors.log"
exec > >(tee -a "$LOGFILE") 2> >(tee -a "$ERRFILE" >&2)

# Fonction pour vérifier si un utilisateur existe déjà
user_exists() {
    id "$1" &>/dev/null
}

# Fonction pour installer les paquets nécessaires
install_packages() {
    local packages=$@
    for package in $packages; do
        if ! dpkg -l | grep -q "$package"; then
            sudo apt install -y "$package" || error_exit "Échec de l'installation de $package"
        fi
    done
}

# Vérification et création des utilisateurs
if ! user_exists "$debian_user"; then
    echo "Création de l'utilisateur Debian : $debian_user"
    sudo adduser --disabled-password --gecos "" "$debian_user" || error_exit "Erreur lors de la création de l'utilisateur Debian"
fi

if ! user_exists "$ansible_user"; then
    echo "Création de l'utilisateur Ansible : $ansible_user"
    sudo adduser --disabled-password --gecos "" "$ansible_user" || error_exit "Erreur lors de la création de l'utilisateur Ansible"
fi

# Ajout des utilisateurs au groupe sudo
echo "Ajout des utilisateurs au groupe sudo"
sudo usermod -aG sudo "$debian_user"
sudo usermod -aG sudo "$ansible_user"

# Installation des paquets nécessaires
install_packages openssh-server python3-venv curl wget git

# Génération de la clé SSH si elle n'existe pas
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Génération de la clé SSH"
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa || error_exit "Échec de la génération de la clé SSH"
fi

# Test de connexion SSH à l'hôte cible
echo "Test de connexion SSH à $target_host..."
if ! ssh -o BatchMode=yes "$debian_user@$target_host" exit 2>/dev/null; then
    echo "Copie de la clé SSH vers $target_host"
    ssh-copy-id "$debian_user@$target_host" || error_exit "Échec de la copie de la clé SSH"
fi

# Installation d'Ansible dans un environnement virtuel Python
if ! command -v ansible &>/dev/null; then
    echo "Installation d'Ansible"
    python3 -m venv ~/ansible || error_exit "Erreur lors de la création de l'environnement virtuel"
    source ~/ansible/bin/activate
    pip install --upgrade pip
    pip install ansible || error_exit "Échec de l'installation d'Ansible"
fi

# Configuration de SSH-Agent pour gérer les clés SSH
if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "Lancement de SSH-Agent"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa || error_exit "Échec de l'ajout de la clé SSH à SSH-Agent"
fi

# Désactivation des avertissements dans Ansible
echo -e "[defaults]\ninterpreter_python=auto_silent" | sudo tee /etc/ansible/ansible.cfg > /dev/null

# Création du fichier d'inventaire Ansible
echo -e "[openstack]\n$target_host ansible_python_interpreter=auto_silent" | sudo tee /etc/ansible/hosts > /dev/null

# Sécurisation des fichiers SSH
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

echo "Déploiement initial terminé. Vous pouvez maintenant utiliser Ansible pour gérer OpenStack."
