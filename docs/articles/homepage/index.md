# Homepage

## YouTube Video

* [Homepage Walkthrough](https://www.youtube.com/watch?v=7hc7mjitgIQ)

---

## What This Page Contains

This guide includes:

* Example `.env` file (safe template)
* `docker-compose.yaml`
* `services.yaml`
* `settings.yaml`
* `widgets.yaml`
* Notes on required vs optional sections

---

# Homepage Setup Walkthrough

---

## Folder Structure

In my setup, each container lives in:

```
/home/<user>/docker/<container_name>
```

Example:

```bash
~/docker/homepage/
├── config/
├── docker-compose.yaml
└── .env
```

The `config/` directory contains:

```
services.yaml
settings.yaml
widgets.yaml
icons/
images/
```

---

# .env file (Recommended)

Using an `.env` file makes configuration cleaner and prevents secrets from being hardcoded in YAML.

Create a file named:

```
.env
```

Example:

```bash
# User mapping
PUID=1000
PGID=1000

# -----------------------------
# Homepage variable substitution
# (used in config/*.yaml as {{HOMEPAGE_VAR_*}})
# -----------------------------

# Monitoring host (Glances / Uptime Kuma)
HOMEPAGE_VAR_MONITOR_HOST=192.168.1.10

# Portainer
HOMEPAGE_VAR_PORTAINER_URL=https://192.168.1.10:9443
HOMEPAGE_VAR_PORTAINER_ENV=1
HOMEPAGE_VAR_PORTAINER_KEY=<PORTAINER_API_KEY>

# Proxmox API (use API token, NOT root password)
HOMEPAGE_VAR_PROXMOX_USER=api@pam!homepage
HOMEPAGE_VAR_PROXMOX_SECRET=<PROXMOX_API_TOKEN_SECRET>

# Proxmox nodes
HOMEPAGE_VAR_PROXMOX_PVE1_URL=https://192.168.1.20:8006
HOMEPAGE_VAR_PROXMOX_PVE2_URL=https://192.168.1.21:8006
HOMEPAGE_VAR_PROXMOX_PVE3_URL=https://192.168.1.22:8006

HOMEPAGE_VAR_PROXMOX_PVE1_NODE=node1
HOMEPAGE_VAR_PROXMOX_PVE2_NODE=node2
HOMEPAGE_VAR_PROXMOX_PVE3_NODE=node3
```

---

# 3️⃣ docker-compose.yaml

This is the minimal working setup with optional Docker auto-discovery and Glances.

## Docker-compse.yaml breakdown

| Component              | What It Does                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| **homepage service**   | The main container running the Homepage dashboard UI                                                    |
| **config volume**      | Mounts your local `./config` folder into the container so your settings persist                         |
| **.env file**          | Stores variables (API keys, URLs, secrets) used inside your YAML files                                  |
| **dockerproxy**        | Optional security layer that allows Homepage to read Docker info without exposing the raw `docker.sock` |
| **glances**            | Optional monitoring container used to show live CPU/RAM stats in Homepage                               |
| **icons/images mount** | Optional mount allowing custom icons and background images                                              |

```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage

    env_file:
      - ./.env

    environment:
      PUID: ${PUID}
      PGID: ${PGID}

      # Use docker proxy (recommended over raw docker.sock)
      DOCKER_HOST: http://dockerproxy:2375

    ports:
      - 3009:3000

    volumes:
      - ./config:/app/config
      - ./config/icons:/app/public/icons:ro
      - ./config/images:/app/public/images:ro

    restart: unless-stopped

  # Optional: Docker auto-discovery proxy
  dockerproxy:
    image: tecnativa/docker-socket-proxy:latest
    container_name: dockerproxy
    restart: unless-stopped
    environment:
      CONTAINERS: 1
      INFO: 1
      IMAGES: 1
      NETWORKS: 1
      SERVICES: 1
      TASKS: 1
      EVENTS: 1
      VOLUMES: 1
      SYSTEM: 1
      VERSION: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  # Optional: Glances system monitoring
  glances:
    image: nicolargo/glances:latest
    container_name: glances
    restart: unless-stopped
    pid: host
    ports:
      - "61208:61208"
    environment:
      - GLANCES_OPT=-w
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

---

# services.yaml

This defines:

* Service groups (System Monitoring, Tools, Virtualization, etc.)
* Links (href)
* Icons
* Embedded widgets (Proxmox, Glances, Portainer, etc.)

Think of this file as:

> “What applications exist on my dashboard?”

```yaml
#####################################################################
- System Monitoring:
    - Glances:
        icon: glances.svg
        href: "http://{{HOMEPAGE_VAR_MONITOR_HOST}}:61208"
        container: glances
        description: Live system stats
        widget:
          type: glances
          url: "http://{{HOMEPAGE_VAR_MONITOR_HOST}}:61208"
          version: 4
          metric: cpu
          refreshInterval: 5000

#####################################################################
- Tools:
    - Portainer:
        icon: portainer.png
        href: "{{HOMEPAGE_VAR_PORTAINER_URL}}"
        description: Container management UI
        widget:
          type: portainer
          url: "{{HOMEPAGE_VAR_PORTAINER_URL}}"
          env: {{HOMEPAGE_VAR_PORTAINER_ENV}}
          key: "{{HOMEPAGE_VAR_PORTAINER_KEY}}"

#####################################################################
- Virtualization:
    - Proxmox (Node 1):
        icon: proxmox.svg
        href: "{{HOMEPAGE_VAR_PROXMOX_PVE1_URL}}"
        widget:
          type: proxmox
          url: "{{HOMEPAGE_VAR_PROXMOX_PVE1_URL}}"
          username: "{{HOMEPAGE_VAR_PROXMOX_USER}}"
          password: "{{HOMEPAGE_VAR_PROXMOX_SECRET}}"
          node: "{{HOMEPAGE_VAR_PROXMOX_PVE1_NODE}}"

    - Proxmox (Node 2):
        icon: proxmox.svg
        href: "{{HOMEPAGE_VAR_PROXMOX_PVE2_URL}}"
        widget:
          type: proxmox
          url: "{{HOMEPAGE_VAR_PROXMOX_PVE2_URL}}"
          username: "{{HOMEPAGE_VAR_PROXMOX_USER}}"
          password: "{{HOMEPAGE_VAR_PROXMOX_SECRET}}"
          node: "{{HOMEPAGE_VAR_PROXMOX_PVE2_NODE}}"
```

---

# settings.yaml

This controls:

* Theme (dark/light)
* Layout (columns, tabs)
* Background image
* Color scheme
* Tab structure

It does **not** define services.

It defines:

> “How is the dashboard arranged and styled?”

```yaml
title: "Homepage Dashboard"
language: en
theme: dark
color: slate
target: _self
headerStyle: boxed
statusStyle: dot
hideVersion: true

fullWidth: true
maxGroupColumns: 6
useEqualHeights: true

background:
  image: /images/background.jpg
  blur: sm
  saturate: 50
  brightness: 50
  opacity: 35

favicon: /icons/favicon.png

layout:
  System Monitoring:
    tab: HOME
    style: row
    columns: 2
    icon: mdi-server

  Tools:
    tab: HOME
    style: row
    columns: 2
    icon: mdi-tools

  Virtualization:
    tab: HOME
    style: row
    columns: 2
    icon: mdi-server-network
```

---

# widgets.yaml

Widgets are things that appear at the top or side of your dashboard:

* Logo
* Greeting
* System resource monitor
* Date/time
* Weather
* Search bar

These are not services — they are UI utilities.

Think of this file as:
> “What informational panels do I want above my services?”

```yaml
- logo:
    icon: /icons/logo.png

- greeting:
    text_size: 4xl
    text: Welcome!

- resources:
    expanded: false
    cpu: true
    memory: true
    refresh: 1000

- datetime:
    text_size: 4xl
    format:
      timeStyle: short
      hour12: false

- datetime:
    text_size: md
    format:
      dateStyle: long
      hour12: false

- search:
    provider: google
    focus: true
    showSearchSuggestions: true
    target: _parent

- openmeteo:
    label: Weather
    latitude: 0.0
    longitude: 0.0
    timezone: UTC
    units: metric
    cache: 5
    format:
      maximumFractionDigits: 0
```

---

# Start It

```bash
docker compose up -d
```

Then open:

```
http://<your-host>:3009
```

## Files

[View All Files on GitHub](/files/termix/homepage)

[Download All Files (ZIP)](/files/termix/homepage-files.zip)

## References

[Homepage GitHub](https://github.com/gethomepage/homepage)

[Homepage Website](https://gethomepage.dev/)
