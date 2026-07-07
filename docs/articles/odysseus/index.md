# Odysseus

## YouTube Video

<!-- youtube:url -->
- [Odysseus Part 1 — What Is It and How It Compares](https://www.youtube.com/watch?...)
- [Odysseus Part 2 — Full Install + RTX 5090 Demo](https://www.youtube.com/watch?...)
<!-- youtube:url:end -->

<!-- TODO: add real YouTube URLs before publishing -->

---

## What this page contains

This guide covers getting [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus)
running on a Linux machine with an NVIDIA GPU. It includes:

- NVIDIA driver setup — required reading for RTX 50-series cards
- Docker and NVIDIA Container Toolkit
- Odysseus clone and configuration
- GPU passthrough via Docker Compose
- Choosing and serving a model via Cookbook
- Notes on a known upstream dependency issue

**Prerequisites:**

- Ubuntu 22.04 or 24.04 (other Debian-based distros should work with minor
  adjustments)
- An NVIDIA GPU — this guide is written and tested on an RTX 5090
- Working internet access before you start

---

## NVIDIA Driver

Ubuntu's default repositories don't carry a new enough driver for modern
GPUs. Add the graphics-drivers PPA first:

```bash
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update
```

### RTX 50-series (Blackwell) — open kernel module required

If you have an RTX 50-series card, the standard NVIDIA driver package will
install and partially detect your GPU, but `nvidia-smi` will fail. Blackwell
architecture requires NVIDIA's open kernel module specifically — the
closed/proprietary default won't work.

Install the `-open` variant:

```bash
sudo apt install -y nvidia-driver-580-open
sudo reboot
```

After reboot, confirm the driver loaded:

```bash
nvidia-smi
```

You should see your GPU listed with driver version and available VRAM.

### Other NVIDIA GPUs (RTX 20/30/40-series)

The standard driver works fine for Turing, Ampere, and Ada Lovelace cards:

```bash
sudo ubuntu-drivers install
sudo reboot
```

---

## Docker

Install via the official Docker repository — not Ubuntu's bundled
`docker.io` package, which lags behind on Compose v2 and GPU runtime
support.

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

Verify:

```bash
docker compose version
sudo docker run hello-world
```

---

## NVIDIA Container Toolkit

The driver alone isn't enough for Docker to access the GPU — the Container
Toolkit is the bridge between them. It's a separate package from a separate
repository.

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor \
  -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L \
  https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Generate the CDI spec

Newer toolkit versions default to CDI (Container Device Interface) mode,
which requires an explicit spec file to be generated. Without it,
`--gpus all` fails with a vendor-discovery error even when the host driver
is working correctly.

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
nvidia-ctk cdi list
```

You should see entries like `nvidia.com/gpu=0` and `nvidia.com/gpu=all`.

Verify Docker can see the GPU end-to-end:

```bash
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi
```

This should print the same GPU output as the host `nvidia-smi`. If it does,
the passthrough stack is working correctly.

---

## Clone Odysseus

```bash
cd ~
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus
git checkout main
```

> The default branch is `dev`, which the README flags as potentially
> unstable. `main` is the curated stable branch.

---

## `.env` Configuration

```bash
cp .env.example .env
nano .env
```

Most defaults are correct for a local setup. The key setting to change for
LAN access:

```bash
# Bind to all interfaces so other devices on your network can reach the UI.
# Default is 127.0.0.1 (localhost only) — nothing on your LAN can reach a
# service bound here, not even the Docker host itself.
APP_BIND=0.0.0.0
```

Leave these at their defaults:

```bash
# AUTH_ENABLED=true      ← authentication stays on
# LOCALHOST_BYPASS=false ← do not bypass auth for local requests
# APP_PORT=7000          ← change only if 7000 is already in use
```

A ready-to-paste snippet is available in the downloadable
[odysseus-files.zip](/files/odysseus/odysseus-files.zip) (see the Files
section at the bottom).

> Only use `APP_BIND=0.0.0.0` on a trusted local network. Odysseus has
> shell access, file system access, and email/calendar integration — treat
> it like an admin console. Do not expose it directly to the internet
> without a reverse proxy and HTTPS in front of it.

---

## GPU Overlay

Odysseus ships a script that handles the GPU overlay for Docker Compose.
Run it first in diagnostic mode — read-only, no changes:

```bash
scripts/check-docker-gpu.sh
```

If it detects your GPU cleanly, enable the overlay:

```bash
scripts/check-docker-gpu.sh --enable-nvidia-overlay
```

This appends the following to your `.env`:

```bash
COMPOSE_FILE=docker-compose.yml:docker/gpu.nvidia.yml
```

Docker Compose will now layer in GPU access on every start automatically.

---

## tmux

Cookbook uses tmux for background model downloads and serving. Install it
before starting the stack:

```bash
sudo apt install -y tmux
```

---

## Start It

```bash
docker compose up -d --build
```

The first build takes a few minutes. Once complete, confirm all four
services are running:

```bash
docker compose ps
```

| Service    | Port | Purpose                                          |
|------------|------|--------------------------------------------------|
| `odysseus` | 7000 | Main web UI                                      |
| `chromadb` | 8100 | Vector memory                                    |
| `searxng`  | 8080 | Local web search (used by Deep Research)         |
| `ntfy`     | 8091 | Notification service for scheduled tasks         |

Get your generated admin password:

```bash
docker compose logs odysseus | grep -i password
```

Open a browser on any machine on your LAN:

```text
http://<host-ip>:7000
```

Log in with username `admin` and the password from the logs. Change the
password immediately in Settings, and disable open signup in
`data/auth.json` unless you want other users to be able to self-register.

---

## Cookbook — Choosing and Serving a Model

Navigate to **Cookbook** in the left sidebar. This is where you discover,
download, and serve models matched to your specific hardware.

### GPU mode vs RAM mode

Make sure you're on **GPU** mode before evaluating models.

> **GPU mode** reads your actual installed GPU and VRAM.
>
> **RAM mode** is a simulator for CPU-offload scenarios — it is meaningless
> for AWQ-format models, which are GPU-only by design. An AWQ model in RAM
> mode will show a confusing `TOO TIGHT` result even if it fits your GPU
> comfortably.

### FIT and SCORE

These two columns measure different things and don't always agree.

> **FIT** — can your hardware run this model comfortably?
> `PERFECT` = fits in VRAM with headroom. `GOOD` = runs but spills into
> system RAM (slower). `MARGINAL` = fits but barely — risky under load.
>
> **SCORE** — how capable is this model at the selected category?
> (Standard, Coding, Reasoning, Chat, Vision)

A model can have the highest score in a list while rated only `GOOD`,
because it exceeds your VRAM budget and runs partially on CPU. `PERFECT`-
rated models are the safer default: full GPU residency, no speed compromise.

### GGUF vs AWQ

| Format   | Serving engine  | Best for                                                   |
|----------|-----------------|------------------------------------------------------------|
| **GGUF** | llama.cpp       | Can split across GPU + system RAM — flexible for limited VRAM |
| **AWQ**  | vLLM / SGLang   | GPU-only, higher throughput when the model fits entirely in VRAM |

With sufficient VRAM to hold the full model, AWQ via vLLM is generally
faster. If you need to offload part of the model to system RAM, GGUF with
llama.cpp is the more flexible option.

### Installing serving dependencies

Navigate to **Cookbook → Dependencies**. Install the serving engine that
matches your chosen model format — `vllm` for AWQ, `llama_cpp` for GGUF.
`tmux` should already show as installed from the earlier step.

Once a serving engine is installed, go to the **Download** tab, pick a
model, click **Download**, then **Run** after it completes.

---

## Optional — ZFS Dataset for Model Files

If you're storing downloaded models on a ZFS pool, give them a dedicated
dataset rather than dumping them at the pool root. A ready-to-run version
of these commands is included in
[odysseus-files.zip](/files/odysseus/odysseus-files.zip) as `zfs-setup.sh`:

```bash
zfs create yourpool/models
zfs set recordsize=1M   yourpool/models
zfs set atime=off       yourpool/models
zfs set compression=lz4 yourpool/models
```

In Odysseus, point **Settings → Servers → Model Directory** at the new
dataset path instead of the default `~/.cache/huggingface/hub`.

---

## Troubleshooting

**`nvidia-smi` fails after driver install (RTX 50-series)**

Check `dmesg` for:

```text
NVRM: installed in this system requires use of the NVIDIA open kernel modules.
```

If you see this, the closed driver was installed. Remove it and install the
open variant:

```bash
sudo apt remove --purge -y nvidia-driver-580 nvidia-dkms-580
sudo apt install -y nvidia-driver-580-open
sudo reboot
```

**`docker run --gpus all` fails with "failed to discover GPU vendor from CDI"**

Generate the CDI spec:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

**Can't reach the UI from another machine on the LAN**

Confirm `APP_BIND=0.0.0.0` is set in `.env`, check that port 7000 isn't
blocked by a firewall (`sudo ufw status`), and confirm all containers are
running (`docker compose ps`).

**vLLM model loads but every API request returns HTTP 500**

Check logs for:

```text
AttributeError: '_IncludedRouter' object has no attribute 'path'
```

This is a known conflict between recent FastAPI versions and
`prometheus-fastapi-instrumentator`. See the Known Issue section below.

---

## Known Issue — vLLM + FastAPI Version Conflict

A breaking change in FastAPI 0.137.0 (June 2026) changed how sub-routers
are stored internally. The `prometheus-fastapi-instrumentator` package that
vLLM uses for metrics reads a `.path` attribute that no longer exists in
the new wrapper object. Because this middleware intercepts every request,
it breaks all API calls, not just the metrics endpoint.

This is an actively tracked upstream bug — not an Odysseus-specific issue.

**Fix options:**

1. Pin FastAPI below the breaking version:

   ```bash
   docker compose exec odysseus pip install "fastapi<0.137.0"
   docker compose restart odysseus
   ```

2. Pin `prometheus-fastapi-instrumentator` to a version compatible with
   your installed FastAPI/Starlette, if you need to stay on a newer
   FastAPI for some other reason.
3. Switch the model's serving backend to llama.cpp instead of vLLM, which
   sidesteps the middleware entirely. Only viable if the model is
   available in GGUF format.

> Check the issue trackers linked in References before pinning a version
> — a proper fix may have landed by the time you read this.

---

## Data Location

```text
~/odysseus/data/
  app.db          # sessions, messages, documents
  memory.json     # agent memory
  uploads/        # file uploads
  personal_docs/  # personal document store
  chroma/         # vector embeddings
  settings.json   # app settings
```

Back this up. `.env` + `data/` is everything needed to restore from scratch.

---

## Files

- [Browse on GitHub](https://github.com/Zack-45D/45homelab/tree/main/docs/public/files/odysseus)
- [Download All Files (ZIP)](/files/odysseus/odysseus-files.zip)

Contents:

- `env.example` — the `.env` setting to change for LAN access.
- `zfs-setup.sh` — optional ZFS dataset properties for a dedicated model store.

---

## References

- [Odysseus on GitHub](https://github.com/pewdiepie-archdaemon/odysseus)
- [Docker Engine — Ubuntu install](https://docs.docker.com/engine/install/ubuntu/)
- [NVIDIA Container Toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [vLLM FastAPI conflict — issue #45596](https://github.com/vllm-project/vllm/issues/45596)
- [vLLM FastAPI conflict — issue #45597](https://github.com/vllm-project/vllm/issues/45597)
- [prometheus-fastapi-instrumentator — issue #370](https://github.com/trallnag/prometheus-fastapi-instrumentator/issues/370)
