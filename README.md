# Yu-Panel Installer

Public bootstrap installer for the private **Yu-Panel** repository.

## One-command install / update

Ubuntu / Debian x86_64:

```bash
sudo su -c "wget -qO- https://raw.githubusercontent.com/Yu817/Yu-Panel-Installer/main/setup.sh | bash"
```

The installer will automatically:

- Install required system packages
- Install Node.js 20
- Install Java 21
- Install PM2
- Prepare a dedicated read-only GitHub Deploy Key when needed
- Clone/update the private `Yu817/Yu-Panel` repository
- Download Linux helper binaries
- Build Yu-Panel
- Install the runtime under `/opt/yu-panel-runtime`
- Keep Yu-Panel data under `/opt/yu-panel-data`
- Start the Yu-Panel Web and Daemon processes with PM2
- Configure PM2 systemd startup

## First installation on a new server

Because the main Yu-Panel repository is private, a new server needs read access before it can clone the source code.

If GitHub access is not already configured, the installer automatically creates a dedicated Ed25519 key and prints the **public key**.

Add that public key here:

`Yu817/Yu-Panel` → **Settings** → **Deploy keys** → **Add deploy key**

Recommended settings:

- Title: `Yu-Panel - <server hostname>`
- Allow write access: **OFF**

After adding the key, return to the terminal and press Enter. The installer verifies access and continues automatically.

The private key remains only on the server, normally at:

```text
~/.ssh/yupanel_deploy_ed25519
```

## Default paths

```text
Source:   /opt/yu-panel
Runtime:  /opt/yu-panel-runtime
Data:     /opt/yu-panel-data
Web:      port 30660
Daemon:   port 30661
```

## Update Yu-Panel

Run the same installation command again:

```bash
sudo su -c "wget -qO- https://raw.githubusercontent.com/Yu817/Yu-Panel-Installer/main/setup.sh | bash"
```

The installer fetches the latest `main`, rebuilds the application, replaces the runtime, and keeps the data directory separate.

## Useful commands

```bash
pm2 status
pm2 logs yu-panel-web
pm2 logs yu-panel-daemon
```

## Supported platform

Currently intended for:

- Ubuntu / Debian
- x86_64 / amd64

The installer intentionally does not grant write access to the private Yu-Panel repository.
