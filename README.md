# Playwright VNC Code Server Setup

## Overview
This repository provides a single `setup.sh` script that installs a full Playwright test environment with a desktop that can be viewed through VNC. It also installs code-server so you can use VS Code in the browser.

## Usage
Run the script on a fresh Ubuntu or Debian system **as root**:

```bash
sudo ./setup.sh [vnc_port] [novnc_port] [code_server_port] [password] [node_version] [disable_codeserver_auth] [disable_vnc_auth]
```

Parameters are optional and default to `5901 6080 8080 vscode 18 false false`.

## What the script sets up
- Node.js and Playwright (including browsers)
- code-server (VS Code in the browser)
- Xvfb and x11vnc for the virtual desktop
- noVNC so you can connect using a web browser
- A sample Playwright workspace at `/root/workspace` with demo tests
- Systemd services for VNC, noVNC and code-server that start automatically
- A helper command `playwright-vnc` for controlling the services
- Health checks and basic optimisations

After installation you can access:
- **VS Code** at `http://localhost:8080`
- **VNC Desktop** at `http://localhost:6080`
- **Direct VNC** on port `5901`

Check `/root/INSTALLATION_SUMMARY.txt` for a summary of the configuration after the script completes.

## License
This project is licensed under the MIT License.
