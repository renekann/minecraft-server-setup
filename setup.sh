#!/bin/bash

# Global variables
DOCKER_HOST_PATH="/run/user/1000/docker.sock"
DOCKER_VOLUMES_PATH="./.local/share/docker/volumes"
PORTAINER_VOLUME="portainer_data"

restore() {
    BACKUP_FILENAME=$1
    EXTRACT_PATH=$2
    WEBDAV_PATH=$3
    VOLUME_NAME=$4  # Assuming this is the Docker volume name

    # Ensure BACKUP_FILENAME is set
    if [ -z "$BACKUP_FILENAME" ]; then
        echo "BACKUP_FILENAME is not set."
        exit 1
    fi

    # Create a unique temporary directory
    TEMP_DIR=$(mktemp -d)

    # Compose the download URL
    DOWNLOAD_URL="${WEBDAV_URL}/${WEBDAV_PATH}/${BACKUP_FILENAME}"

    echo "Downloading backup from: $DOWNLOAD_URL"

    # Download the file from WebDAV
    curl -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" $CURL_INSECURE_FLAG -o "${TEMP_DIR}/${BACKUP_FILENAME}" $DOWNLOAD_URL

    # Check if the file was downloaded successfully
    if [ -f "${TEMP_DIR}/${BACKUP_FILENAME}" ]; then
        # Locally extract the backup file
        mkdir "${TEMP_DIR}/extracted"
        tar -xzf "${TEMP_DIR}/${BACKUP_FILENAME}" -C "${TEMP_DIR}/extracted"

        # Check if the specified path exists in the extracted content
        if [ ! -d "${TEMP_DIR}/extracted/${EXTRACT_PATH}" ]; then
            echo "${EXTRACT_PATH} does not exist in the archive."
            exit 1
        fi

        # Use a Docker container to copy the specified path into the volume
        docker run --rm -v "${TEMP_DIR}/extracted/${EXTRACT_PATH}:/source" -v "${VOLUME_NAME}:/_data" alpine cp -a /source/. /_data

        echo "Backup segment successfully copied into the Docker volume."
    else
        echo "The file could not be downloaded."
    fi

    # Remove the temporary directory
    rm -rf "$TEMP_DIR"
}

install_uidmap() {
    if ! command -v uidmap &> /dev/null; then
        echo "Installing uidmap..."
        sudo apt-get update && sudo apt-get install -y uidmap
    else
        echo "uidmap is already installed."
    fi
}

install_docker() {
    if command -v docker &>/dev/null && docker --version &>/dev/null; then
        echo "Docker is already installed."
        return
    fi

    echo "Installing Docker Rootless..."
    curl -fsSL https://get.docker.com/rootless | sh
}

install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose is already installed."
    fi
}

install_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo "Installing rclone..."
        curl -s https://rclone.org/install.sh | sudo bash
    else
        echo "rclone is already installed."
    fi
}

configure_docker() {
    local modified=0
    grep -q 'export PATH=/home/$USER/bin:$PATH' ~/.bash_aliases || {
        echo 'export PATH=/home/$USER/bin:$PATH' >> ~/.bash_aliases
        modified=1
    }

    grep -q 'export DOCKER_HOST=unix:///run/user/1000/docker.sock' ~/.bash_aliases || {
        echo 'export DOCKER_HOST=unix:///run/user/1000/docker.sock' >> ~/.bash_aliases
        modified=1
    }

    (( modified )) && source ~/.bash_aliases

    if ! getcap $HOME/bin/rootlesskit | grep -q 'cap_net_bind_service=ep'; then
        sudo setcap cap_net_bind_service=ep $HOME/bin/rootlesskit
    fi

    if ! systemctl --user is-active --quiet docker; then
        systemctl --user start docker
        systemctl --user enable docker
        sudo loginctl enable-linger $(whoami)
    fi

    docker info || {
        echo "Error checking Docker installation."
        exit 1
    }
}

configure_rclone() {
    echo "Configuring rclone for WebDAV..."

    RCLONE_CONF_PATH="$HOME/.config/rclone/rclone.conf"

    if [ -f "$RCLONE_CONF_PATH" ]; then
        echo "Removing existing rclone configuration file..."
        rm -f "$RCLONE_CONF_PATH"
    fi

    rclone config create nas webdav \
        url=$WEBDAV_URL \
        vendor=other \
        user=$WEBDAV_USERNAME \
        pass=$WEBDAV_PASSWORD

    echo "rclone configured."
}

create_env_file() {
    echo "Creating .env file with secrets for the backup service..."

    read -p "Enter the WEBDAV_URL (e.g., http://192.168.1.1:5005): " webdav_url
    while [[ ! "$webdav_url" =~ ^http ]]; do
        echo "Invalid URL. Please enter again:"
        read -p "Enter the WEBDAV_URL (e.g., http://192.168.1.1:5005): " webdav_url
    done

    read -p "Enter the WEBDAV_USERNAME: " webdav_username
    read -p "Enter the WEBDAV_BASE_PATH: " WEBDAV_BASE_PATH
    read -sp "Enter the WEBDAV_PASSWORD: " webdav_password
    echo
    read -p "Is the WEBDAV_URL insecure and still to be used (true/false)?: " webdav_url_insecure

    cat > .env << EOF
WEBDAV_URL=$webdav_url
WEBDAV_USERNAME=$webdav_username
WEBDAV_PASSWORD=$webdav_password
WEBDAV_BASE_PATH=$WEBDAV_BASE_PATH
WEBDAV_URL_INSECURE=$webdav_url_insecure
EOF

    echo ".env file created."
}

load_env_file() {
    # Load variables from the .env file
    source .env
}

install_portainer() {
    # Stop and remove existing Portainer containers and volumes, if any, with Docker Compose
    echo "Stopping and removing existing Portainer containers and volumes with Docker Compose..."
    docker-compose -f docker-compose-portainer.yml down

    # Wait and check if Portainer is completely stopped
    while docker ps -a | grep -q 'portainer'; do
        echo "Waiting for Portainer to fully stop..."
        sleep 2
    done
    echo "Portainer has been fully stopped."

    # Create volume for portainer
    docker volume create $PORTAINER_VOLUME

    # Query whether to restore from a backup
    read -p "Do you want to restore Portainer from a backup? [yes/no, default: no]: " RESTORE_ANSWER
    RESTORE_ANSWER=${RESTORE_ANSWER:-yes}

    if [[ "$RESTORE_ANSWER" =~ ^[Yy]es$ ]]; then
        # Download and extract the backup file
        echo "Downloading and extracting Portainer backup..."
        read -p "Enter the name of the backup file for Portainer: " BACKUP_FILENAME
        restore $BACKUP_FILENAME "backup/portainer" "${WEBDAV_BASE_PATH}/portainer" $PORTAINER_VOLUME
    fi
}

configure_ufw() {
    echo "Configuring UFW"
    # Ensure SSH access is allowed to not get locked out
    sudo ufw allow ssh
    
    sudo ufw allow 9000/tcp # Portainer
    
    # Creative Minecraft
    sudo ufw allow 25565/tcp # Minecraft Java
    sudo ufw allow 19132/udp # Minecraft Bedrock (Geyser)

    # Survival Minecraft
    sudo ufw allow 25566/tcp # Minecraft Java
    sudo ufw allow 19133/udp # Minecraft Bedrock (Geyser)

    sudo ufw status verbose | grep "Status: active" > /dev/null || sudo ufw enable
}

start_portainer() {
    # Check if a Portainer container is already running
    if docker ps --format '{{.Names}}' | grep -q 'portainer'; then
        echo "Portainer is already running."
    else
        echo "Starting Portainer with Docker Compose..."
        docker-compose -f docker-compose-portainer.yml up -d
        echo "Portainer has been started with Docker Compose."
    fi
}

main() {
    install_uidmap
    install_docker
    configure_docker
    install_docker_compose
    install_portainer

    if [[ " $* " != *" --skip-env "* ]]; then
        create_env_file
    fi

    load_env_file

    install_rclone
    configure_rclone

    configure_ufw

    start_portainer

    echo "Installation completed. Please restart your shell or run 'source ~/.bash_aliases' to apply changes."
}

main "$@"
