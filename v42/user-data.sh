#!/bin/bash
# Novatrix v42 VG: körs av servern själv vid första starten.
# User data körs som root, därför behövs inte sudo.
# Loggen hamnar i /var/log/cloud-init-output.log på servern.

# Stanna vid första felet och skriv varje kommando i loggen
set -euxo pipefail

# Uppdatera paketen och installera webbservern
yum update -y
yum install -y httpd

# Starta webbservern nu och vid varje omstart
systemctl start httpd
systemctl enable httpd

# Hämta Novatrix-sidan från repot på GitHub
curl -fsSL -o /var/www/html/index.html https://raw.githubusercontent.com/80idralt/aws/master/v42/index.html
