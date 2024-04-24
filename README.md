# Minecraft Server Configuration Script

This script automates the setup and configuration of a Minecraft server environment on a Unix-like system. It manages Docker, Docker Compose, Portainer, and Rclone setups to handle game server operations efficiently and securely. It also takes care of backups via WebDAV, manages Docker volumes, and configures network rules using UFW (Uncomplicated Firewall).

## Features

- **Minecraft Server Management**: Automates Docker-based deployments of Minecraft servers.
- **Docker Installation**: Installs Docker in a rootless mode to enhance security.
- **Docker Compose Installation**: Sets up Docker Compose for managing Docker applications including the Minecraft server.
- **Rclone Configuration**: Configures Rclone for managing cloud storage systems via WebDAV for backup operations.
- **Portainer Setup**: Deploys Portainer for easy Docker management, allowing easy container management via a web interface.
- **Backup and Restore**: Provides functionalities to backup and restore Docker volumes, including game data, using WebDAV.
- **Firewall Configuration**: Uses UFW to manage network traffic to and from the Minecraft server.

## Requirements

- A Unix-like operating system (e.g., Ubuntu, Debian)
- Sudo privileges
- Internet connection for downloading necessary packages

## Installation

1. **Clone the repository**:
   ```
   git clone <repository-url>
   cd <repository-directory>
   ```

2. **Make the script executable**:
   ```
   chmod +x setup.sh
   ```

3. **Run the script**:
   ```
   ./setup.sh
   ```

## Usage

- To run the entire setup process, simply execute the script without any parameters:
  ```
  ./setup.sh
  ```

- To skip environment variable setup (e.g., if `.env` is already configured or not needed):
  ```
  ./setup.sh --skip-env
  ```

## Detailed Function Descriptions

- `install_docker()`: Checks if Docker is already installed; if not, installs Docker in rootless mode.
- `install_docker_compose()`: Installs Docker Compose if it's not already installed.
- `install_rclone()`: Ensures Rclone is installed for managing backups and remote storage.
- `configure_docker()`: Configures Docker to ensure it uses the specified user's Docker daemon and sets necessary capabilities.
- `configure_rclone()`: Sets up Rclone with the given WebDAV settings stored in `.env` file.
- `create_env_file()`: Creates a `.env` file to store sensitive information like WebDAV credentials securely.
- `restore()`: Function to restore a Docker volume from a backup stored in a WebDAV location.
- `install_portainer()`: Installs and configures Portainer, handling previous installations if found.
- `configure_ufw()`: Configures the UFW firewall to secure the server's network traffic.
- `start_portainer()`: Starts the Portainer service using Docker Compose.

## Notes

- Ensure that all WebDAV credentials are kept secure.
- The script requires sudo access to install packages and configure system settings.

## Troubleshooting

- If you encounter permission issues, ensure the script is run with sudo privileges.
- For issues with Docker or Docker Compose, verify that your user is part of the docker group:
  ```
  sudo usermod -aG docker $USER
  ```

## License

MIT License

Copyright (c) 2024 René Kann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.