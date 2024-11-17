#!/bin/bash
if ! command -v vagrant &> /dev/null; then
    echo "Vagrant not installed"
    exit 1
fi
if ! command -v virtualbox &> /dev/null; then
    echo "VirtualBox not installed"
    exit 1
fi

#Vagrantfile création
cat <<EOF > Vagrantfile

Vagrant.configure("2") do |config|

  # Configuration pour le  Squid Proxy VM avec Debian
  config.vm.define "squid_proxy" do |squid_proxy|
    squid_proxy.vm.box = "debian/bullseye64"
    squid_proxy.vm.hostname = "squid-proxy"
    squid_proxy.vm.network "private_network", ip: "192.168.56.10"

    squid_proxy.vm.provider "virtualbox" do |vb|
      vb.name = "Squid_Server"
      vb.memory = "512"
      vb.cpus = 1
    end

    # Installation Squid, SquidGuard, Apache2
    squid_proxy.vm.provision "shell", inline: <<-SHELL
      apt-get update
      apt-get install -y squid squidguard apache2

      # Configuration de Squid avec localnet ACL
      cat <<EOF2 > /etc/squid/squid.conf
acl localnet src 192.168.56.0/24
http_access allow localnet
http_access deny all

# Configuration de SquidGuard pour utiliser blacklists
url_rewrite_program /usr/bin/squidGuard -c /etc/squid/squidGuard.conf


http_port 3128
EOF2

      # Création du chemin de blaclists
      mkdir -p /etc/squid/blacklists

      # Ajout de domaine interdit 'blacklist_domains'
      echo "google.com" >> /etc/squid/blacklists/blacklist_domains  

      # Ajout idem pour l'url 'blacklist_urls'
      echo "https://www.google.com/" >> /etc/squid/blacklists/blacklist_urls  # Block specific URL

      # Configuration de SquidGuard
      cat <<EOF3 > /etc/squid/squidGuard.conf
dbhome /etc/squid/blacklists
logdir /var/log/squidGuard

dest blacklist_domains {
    domainlist blacklist_domains
}

dest blacklist_urls {
    urllist blacklist_urls
}

acl {
    default {
        pass !blacklist_domains !blacklist_urls any
        redirect http://192.168.56.10/block.html
    }
}
EOF3

      # Generation de la BDD SquiGuard
      squidGuard -C all

      # Créationd de la page de blocage
      cat <<EOF4 > /var/www/html/block.html
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Accès Bloqué</title>
</head>
<body>
    <h1>Accès Bloqué</h1>
    <p>L'accès à cette page a été bloqué en raison des règles de sécurité du réseau.</p>
</body>
</html>
EOF4

      # on redémarre les services
      systemctl restart squid
      systemctl start apache2
      systemctl enable apache2
    SHELL
  end

  # Configuration pour le client (Debian Desktop)
  config.vm.define "squid_client" do |squid_client|
    squid_client.vm.box = "debian/bullseye64"
    squid_client.vm.hostname = "squid-client"
    squid_client.vm.network "private_network", ip: "192.168.56.11"

    squid_client.vm.provider "virtualbox" do |vb|
      vb.name = "Squid_Client"
      vb.memory = "2048"
      vb.cpus = 1
    end

    # Configure des paramètres de proxy pour le client
    squid_client.vm.provision "shell", inline: <<-SHELL
      echo 'http_proxy="http://192.168.56.10:3128/"' >> /etc/environment
      echo 'https_proxy="http://192.168.56.10:3128/"' >> /etc/environment
      echo 'ftp_proxy="http://192.168.56.10:3128/"' >> /etc/environment
      echo 'no_proxy="localhost,127.0.0.1,::1"' >> /etc/environment
    SHELL
  end

end
EOF

