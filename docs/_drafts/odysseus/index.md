# Odysseus

## YouTube Video

<!-- youtube:url -->
- [45Homelab Odysseus Video](https://www.youtube.com/watch?...)
<!-- youtube:url:end -->

---

## What this page contains

Notes, commands, and downloadable example files used in the **Odysseus**
video — a walkthrough of setting up [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus)
on Ubuntu 22.04 with an RTX 5090 (Blackwell) for local LLM serving.

**Reference machine:** `ubu22` — Ubuntu 22.04 LTS, Zotac RTX 5090
(GB202, 32 GB GDDR7), accessed at `http://<ubu22-ip>:7000`.

This page captures what was actually verified working on that hardware,
including a few failure modes worth recognizing if they recur.

---

## Notes / Walkthrough

### Step 1 — NVIDIA driver (Blackwell needs the *open* module)

Ubuntu 22.04's default repos don't carry a driver new enough for Blackwell,
so use the graphics-drivers PPA:

```bash
add-apt-repository ppa:graphics-drivers/ppa -y
apt update
```

**Critical:** the 5090 requires the **open** kernel module, not the
proprietary one. `nvidia-driver-570` resolves to `nvidia-driver-580`
underneath, but that pulls the **closed** module — the GPU gets detected,
`nvidia-smi` fails, and `dmesg` shows:

```text
NVRM: installed in this system requires use of the NVIDIA open kernel modules.
```

Install the `-open` variant directly:

```bash
apt install -y nvidia-driver-580-open
reboot
```

After reboot:

```bash
lsmod | grep nvidia
nvidia-smi
```

Should show driver `580.159.03`, ~32607 MiB VRAM, CUDA 13.0.

#### If you already installed the closed driver

```bash
apt remove --purge -y nvidia-driver-570 nvidia-driver-580 nvidia-dkms-580
apt autoremove -y
apt install -y nvidia-driver-580-open
reboot
```

#### Quick diagnostic reference

```bash
lsmod | grep nvidia
lsmod | grep nouveau     # should be empty
dmesg | grep -i nvidia | tail -20
lspci | grep -i nvidia
```

---

### Step 2 — Docker (official repo)

Use Docker's official repo, not `apt install docker.io`:

```bash
apt update
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verify:

```bash
docker compose version
docker run hello-world
```

---

### Step 3 — NVIDIA Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

Before continuing, confirm both files actually have content (curl can
silently produce 0-byte files if DNS or routing is flaky):

```bash
ls -la /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
cat   /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

Install and configure:

```bash
apt update
apt install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

#### Generate the CDI spec

```bash
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
nvidia-ctk cdi list
```

#### Verify Docker can see the GPU

```bash
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi
```

> The `nvidia/cuda` image tags need a full patch version
> (e.g. `12.6.0`, not `12.0`).

---

### Step 4 — ZFS dataset for model files

If you're storing downloaded models on a ZFS pool, give them a dedicated
dataset rather than dumping them at the pool root:

```bash
zfs create yourpool/models
zfs set recordsize=1M   yourpool/models
zfs set atime=off       yourpool/models
zfs set compression=lz4 yourpool/models
```

A ready-to-run version of these commands is available as
[`zfs-setup.sh`](/files/odysseus/zfs-setup.sh).

**Why these settings**

- `recordsize=1M` matches ZFS's block allocation to the scale of model
  weight files (multi-GB), cutting metadata overhead versus the default 128K.
- `compression=lz4` — model weights are dense, mostly-incompressible binary
  data, but `lz4` has an early-abort path: it samples a block and stores it
  raw if it doesn't compress well, so the CPU cost on incompressible data
  is negligible. Turning compression *off* gives up the free wins on the
  parts of the dataset that *do* compress (safetensors headers, tokenizer
  and config JSON, padding/alignment regions).
- `atime=off` — read-only model files don't need access-time tracking.

**Vdev topology (8x SSDs)**

- **RAIDZ2** (single 8-wide vdev) — ~2.88 TB usable, 2-drive fault tolerance.
- **Striped mirrors** (4x 2-way) — ~1.92 TB usable, better random IOPS.

For a workload dominated by loading one large file at a time, RAIDZ2's
capacity-and-resilience tradeoff is the more sensible default. Both
topologies parallelize sequential reads across drives, just at different
levels (across vdevs vs across vdev members), so the throughput gap is
smaller than it looks on paper.

```bash
zpool get ashift yourpool   # should read 12 for 4K-sector SSDs — can't change after pool creation
```

In Odysseus, point **Settings → Servers → Model Directory** at the new
dataset path instead of the default `~/.cache/huggingface/hub`.

---

### Step 5 — Clone Odysseus

```bash
cd ~
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus
git checkout main
```

---

### Step 6 — Configure `.env`

```bash
cp .env.example .env
nano .env
```

Set:

```bash
APP_BIND=0.0.0.0       # bind to all interfaces for LAN access
AUTH_ENABLED=true      # leave on — always
LOCALHOST_BYPASS=false # leave off
```

A ready-to-paste snippet is available as
[`env.example`](/files/odysseus/env.example).

`APP_BIND=0.0.0.0` is required for LAN access. Binding to loopback
(the default) means nothing outside the container — not even the Docker
host — can reach the UI. Opening it up is fine here because
`AUTH_ENABLED=true` keeps a login in front of the app.

---

### Step 7 — Enable the GPU overlay

```bash
scripts/check-docker-gpu.sh
scripts/check-docker-gpu.sh --enable-nvidia-overlay
```

Adds `COMPOSE_FILE=docker-compose.yml:docker/gpu.nvidia.yml` to `.env`.

---

### Step 8 — Install tmux

Handy for long-running model downloads / first-time builds:

```bash
apt install -y tmux
```

---

### Step 9 — Build and start the stack

```bash
docker compose up -d --build
docker compose ps
```

Four services come up:

| Service    | Port |
|------------|------|
| `odysseus` | 7000 |
| `chromadb` | 8100 |
| `searxng`  | 8080 |
| `ntfy`     | 8091 |

Grab the initial admin password and confirm the container sees the GPU:

```bash
docker compose logs odysseus | grep -i password
docker compose exec odysseus nvidia-smi -L
```

---

### Step 10 — First login

Open `http://<ubu22-ip>:7000`. Log in as `admin` with the password from
Step 9. **Change the password immediately**, then check `data/auth.json`
to confirm open signup is off.

---

### Step 11 — Cookbook: GPU mode vs RAM mode

When evaluating models, **use GPU mode**:

- **GPU mode** reads your real detected GPU (5090, ~31.8 GB usable VRAM).
- **RAM mode** is a CPU-offload simulator. It's meaningless for
  AWQ/safetensors models, which are GPU-only by format — pointing an AWQ
  model at RAM mode produces a nonsensical `TOO TIGHT` / `0.0` score.
  That's the wrong lens, not a real problem with the model.

**FIT vs SCORE are different axes:**

- **FIT** — does it fit your hardware comfortably (PERFECT / GOOD / MARGINAL)?
- **SCORE** — how capable is the model at the selected category
  (Standard / Coding / Reasoning / Chat / Vision)?

A model can have the highest SCORE in a list while only rating GOOD,
because it needs CPU+RAM offload to fit (slower, via llama.cpp) rather
than living entirely in VRAM (faster, via vLLM/SGLang on AWQ format).

With 32 GB of VRAM and no offload needed, AWQ models showing **PERFECT
fit** are the better default pick on this hardware.

---

### Step 12 — Known issue: vLLM + prometheus-fastapi-instrumentator

**Symptom:** vLLM's engine initializes successfully (model loads, KV cache
allocates fine), but every API request afterward — including basic health
checks — returns HTTP 500. The actual crash:

```text
AttributeError: '_IncludedRouter' object has no attribute 'path'
```

**Root cause:** FastAPI 0.137.0 (released June 14, 2026) changed how
`include_router()` stores sub-routers internally — it now wraps them in
`_IncludedRouter` objects that don't expose a `.path` attribute.
`prometheus-fastapi-instrumentator`, which vLLM uses for its metrics
middleware, reads `route.path` directly and crashes. The middleware
intercepts every request before it reaches the route handler, so the
500s aren't limited to the metrics endpoint.

This is a confirmed open upstream bug, tracked on vLLM
(#45596, #45597) and `prometheus-fastapi-instrumentator` (#370).
It's not specific to Odysseus, but it can surface inside an Odysseus +
vLLM stack since vLLM's metrics middleware is on by default.

**Fix options:**

1. **Pin FastAPI below 0.137.0** (the version that introduced the change):

   ```bash
   docker compose exec odysseus pip install "fastapi<0.137.0"
   docker compose restart odysseus
   ```

2. **Pin `prometheus-fastapi-instrumentator`** to a version compatible
   with your installed FastAPI/Starlette, if you need to stay on a newer
   FastAPI for some other reason.
3. **Switch the model's serving backend to llama.cpp** instead of vLLM,
   which sidesteps the middleware entirely. Only viable if the model is
   available in GGUF format.

> Check current package versions before deploying — this is a very
> recent, actively-tracked bug, and a fix may have landed in either
> project by the time you read this. Don't treat version pins as
> permanent.

---

## Useful Commands

```bash
docker compose up -d
docker compose down
docker compose restart odysseus
docker compose logs -f odysseus
docker compose logs --tail=100 odysseus
git pull && docker compose up -d --build
docker compose exec odysseus nvidia-smi -L
nvidia-smi
nvidia-ctk cdi list
```

---

## Troubleshooting

**`nvidia-smi` fails after driver install** — Blackwell needs
`nvidia-driver-580-open` specifically. Work through the diagnostic block
in Step 1.

**`apt install` says "unable to locate package" for a repo you just added**
— check the relevant `.list` and keyring files for 0-byte / empty content.
Re-run the curl steps once networking is confirmed working.

**`docker run --gpus all` fails with "failed to discover GPU vendor from
CDI"** — run `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.

**vLLM model loads but every API request returns 500** — see Step 12.

**Can't reach the UI from another LAN machine** — confirm
`APP_BIND=0.0.0.0`, check `ufw status`, and confirm `docker compose ps`
shows everything `Up`.

**Port 7000 already in use** — set `APP_PORT=7001` in `.env` and restart.

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

- [`env.example`](/files/odysseus/env.example) — the three `.env` settings
  to change (Step 6).
- [`zfs-setup.sh`](/files/odysseus/zfs-setup.sh) — dataset properties from
  Step 4.

> All downloadable files for this article live in
> `docs/public/files/odysseus/`.

---

## References

- [Odysseus on GitHub](https://github.com/pewdiepie-archdaemon/odysseus)
- [NVIDIA Container Toolkit docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [vLLM issue #45596](https://github.com/vllm-project/vllm/issues/45596)
- [prometheus-fastapi-instrumentator issue #370](https://github.com/trallnag/prometheus-fastapi-instrumentator/issues/370)
