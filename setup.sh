#!/bin/bash

# Globale Variablen
DOCKER_HOST_PATH="/run/user/1000/docker.sock"
DOCKER_VOLUMES_PATH="./.local/share/docker/volumes"
PORTAINER_VOLUME="portainer_data"

restore() {
    BACKUP_FILENAME=$1
    EXTRACT_PATH=$2
    WEBDAV_PATH=$3
    VOLUME_NAME=$4  # Angenommen, dies ist der Name des Docker Volumes

    # Stellen Sie sicher, dass BACKUP_FILENAME gesetzt ist
    if [ -z "$BACKUP_FILENAME" ]; then
        echo "BACKUP_FILENAME ist nicht gesetzt."
        exit 1
    fi

    # Erstellen eines einzigartigen temporären Verzeichnisses
    TEMP_DIR=$(mktemp -d)

    # Download-URL zusammensetzen
    DOWNLOAD_URL="${WEBDAV_URL}/${WEBDAV_PATH}/${BACKUP_FILENAME}"

    echo "Lade Backup herunter von: $DOWNLOAD_URL"

    # Datei von WebDAV herunterladen
    curl -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" $CURL_INSECURE_FLAG -o "${TEMP_DIR}/${BACKUP_FILENAME}" $DOWNLOAD_URL

    # Überprüfen, ob die Datei erfolgreich heruntergeladen wurde
    if [ -f "${TEMP_DIR}/${BACKUP_FILENAME}" ]; then
        # Backup-Datei lokal entpacken
        mkdir "${TEMP_DIR}/extracted"
        tar -xzf "${TEMP_DIR}/${BACKUP_FILENAME}" -C "${TEMP_DIR}/extracted"

        # Prüfen, ob der spezifizierte Pfad im entpackten Inhalt existiert
        if [ ! -d "${TEMP_DIR}/extracted/${EXTRACT_PATH}" ]; then
            echo "${EXTRACT_PATH} existiert nicht im Archiv."
            exit 1
        fi

        # Verwenden Sie einen Docker-Container, um den spezifizierten Pfad in das Volume zu kopieren
        docker run --rm -v "${TEMP_DIR}/extracted/${EXTRACT_PATH}:/source" -v "${VOLUME_NAME}:/_data" alpine cp -a /source/. /_data

        echo "Backup-Teil wurde erfolgreich in das Docker-Volume kopiert."
    else
        echo "Die Datei konnte nicht heruntergeladen werden."
    fi

    # Löschen des temporären Verzeichnisses
    rm -rf "$TEMP_DIR"
}

cleanup() {
    echo "Entferne bestehende Docker-Installationen..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc

    echo "Entferne nicht mehr benötigte Pakete..."
    sudo apt autoremove -y
}

install_uidmap() {
    if ! command -v uidmap &> /dev/null; then
        echo "Installiere uidmap..."
        sudo apt-get update && sudo apt-get install -y uidmap
    else
        echo "uidmap ist bereits installiert."
    fi
}

install_docker() {
    if [ -x "$HOME/bin/dockerd" ]; then
        echo "Entferne existierende Docker Rootless Installation..."
        systemctl --user stop docker
        rm -f /home/$USER/bin/dockerd
    fi

    echo "Installiere Docker Rootless..."
    curl -fsSL https://get.docker.com/rootless | sh
}

configure_docker() {
    echo "Füge Umgebungsvariablen zu ~/.bash_aliases hinzu..."
    echo 'export PATH=/home/$USER/bin:$PATH' >> ~/.bash_aliases
    echo 'export DOCKER_HOST=unix:///run/user/1000/docker.sock' >> ~/.bash_aliases

    source ~/.bash_aliases

    if [ "$DOCKER_HOST" != "unix:///run/user/1000/docker.sock" ]; then
        echo "Die DOCKER_HOST-Umgebungsvariable wurde nicht korrekt gesetzt."
    fi

    echo "Setze cap_net_bind_service für rootlesskit, um Ports unter 1024 zu nutzen..."
    sudo setcap cap_net_bind_service=ep $HOME/bin/rootlesskit

    echo "Konfiguriere und starte Docker-Dienst..."
    systemctl --user start docker
    systemctl --user enable docker
    sudo loginctl enable-linger $(whoami)

    echo "Überprüfe die Docker-Installation mit 'docker info'..."
    docker info
}

install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Installiere Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose ist bereits installiert."
    fi
}

create_env_file() {
    echo "Erstelle .env Datei mit Secrets für den Backup-Service..."

    # WEBDAV Credentials abfragen
    read -p "Geben Sie die WEBDAV_URL ein (z.B. http://192.168.1.50:5005): " webdav_url
    read -p "Geben Sie den WEBDAV_USERNAME ein (z.B. minecraft-server): " webdav_username
    read -p "Geben Sie den WEBDAV_BASE_PATH ein (z.B. /minecraft-server/backups): " WEBDAV_BASE_PATH
    read -sp "Geben Sie das WEBDAV_PASSWORD ein: " webdav_password
    echo
    read -p "Ist die WEBDAV_URL unsicher und soll trotzdem verwendet werden (true/false)?: " webdav_url_insecure

    # .env Datei erstellen
    cat > .env << EOF
WEBDAV_URL=$webdav_url
WEBDAV_USERNAME=$webdav_username
WEBDAV_PASSWORD=$webdav_password
WEBDAV_BASE_PATH=$WEBDAV_BASE_PATH
WEBDAV_URL_INSECURE=$webdav_url_insecure
EOF

    echo ".env Datei erstellt."
}

load_env_file() {
    # Lädt die Variablen aus der .env Datei
    source .env
}

restore_portainer() {
    # Stoppen und Entfernen des bestehenden Portainer-Containers und -Volumes, falls vorhanden, mit Docker Compose
    echo "Stoppe und entferne bestehende Portainer-Container und -Volumes mit Docker Compose..."
    docker-compose -f docker-compose-portainer.yml down

    # Volume für portainer anlegen
    docker volume create $PORTAINER_VOLUME

    # Abfrage, ob ein Backup wiederhergestellt werden soll
    read -p "Möchten Sie das Portainer aus einem Backup wiederherstellen? [yes/no, default: yes]: " RESTORE_ANSWER
    RESTORE_ANSWER=${RESTORE_ANSWER:-yes}

    if [[ "$RESTORE_ANSWER" =~ ^[Yy]es$ ]]; then
        # Backup-Datei herunterladen und extrahieren
        echo "Lade Portainer-Backup herunter und extrahiere es..."
        read -p "Geben Sie den Namen der Backup-Datei für Portainer ein: " BACKUP_FILENAME
        restore $BACKUP_FILENAME "backup/portainer" "${WEBDAV_BASE_PATH}/portainer" $PORTAINER_VOLUME
    fi
}

restore_minecraft_data() {
    TARGET_VOLUME=$1

    # Abfrage, ob ein Backup wiederhergestellt werden soll
    read -p "Möchten Sie Minecraft Daten für \"${TARGET_VOLUME}\" aus einem Backup wiederherstellen? [yes/no, default: yes]: " RESTORE_ANSWER
    RESTORE_ANSWER=${RESTORE_ANSWER:-yes}

    if [[ "$RESTORE_ANSWER" =~ ^[Yy]es$ ]]; then
        # Backup-Datei herunterladen und extrahieren
        echo "Lade Minecraft-Backup herunter und extrahiere es..."
        read -p "Geben Sie den Namen der Backup-Datei für Minecraft ein: " BACKUP_FILENAME
        restore $BACKUP_FILENAME "backup/${TARGET_VOLUME}" "${WEBDAV_BASE_PATH}/${TARGET_VOLUME}" $TARGET_VOLUME
    fi
}

configure_ufw() {
    echo "Konfiguriere UFW"
    # Stellen Sie sicher, dass SSH-Zugriff erlaubt ist, um nicht ausgesperrt zu werden
    sudo ufw allow ssh
    
    sudo ufw allow 9000/tcp # Portainer
    sudo ufw allow 25565/tcp # Minecraft Java
    sudo ufw allow 19132/udp # Minecraft Bedrock (Geyser)
    sudo ufw status verbose | grep "Status: active" > /dev/null || sudo ufw enable
}

start_portainer() {
    echo "Starte Portainer mit Docker Compose..."
    docker-compose -f docker-compose-portainer.yml up -d
    echo "Portainer wurde mit Docker Compose gestartet."
}

main() {
    #cleanup
    #install_uidmap
    #install_docker
    #configure_docker
    #install_docker_compose

    if [[ " $* " != *" --skip-env "* ]]; then
        create_env_file
    fi

    load_env_file

    restore_portainer
    restore_minecraft_data "minecraft-creative"

    configure_ufw

    start_portainer

    echo "Installation abgeschlossen. Bitte starten Sie Ihre Shell neu oder führen Sie 'source ~/.bash_aliases' aus, um die Änderungen zu übernehmen."
}

main "$@"
