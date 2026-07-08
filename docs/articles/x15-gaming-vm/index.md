# X15 Gaming VM

## YouTube Video

<!-- youtube:url -->
- [45Homelab X15 Gaming VM Video](https://www.youtube.com/watch?...)
<!-- youtube:url:end -->

<!-- TODO: add real YouTube URL before publishing -->

---

## What this page contains

Companion guide for setting up a Windows 11 gaming VM on the
**45HomeLab X15 Signature Series** running Unraid, with the discrete
RTX 4060 LP passed through and streamed to remote clients via
[Sunshine](https://app.lizardbyte.dev/Sunshine/) +
[Moonlight](https://moonlight-stream.org/).

Covers:

- BIOS + Unraid prep for GPU passthrough (IOMMU / VFIO binding)
- Creating the Windows 11 VM (VirtIO, TPM, OVMF)
- Installing and configuring Sunshine inside the VM
- Pairing Moonlight clients on LAN and over Tailscale
- CPU core pinning for consistent frame times
- Troubleshooting and Docker-based alternatives

---

## Reference Hardware

This guide is written around the X15 Signature Series build. Confirm your
system matches before starting.

| Component  | Spec                                                        |
|------------|-------------------------------------------------------------|
| CPU        | Intel i7-14700 (UHD 770 iGPU + 20 cores)                    |
| GPU        | RTX 4060 LP (8 GB GDDR6, 115 W TDP)                         |
| RAM        | ECC DDR4-3200 UDIMM (8 / 16 / 32 GB per order)              |
| HBA        | LSI 9400-16i (16-port SAS/SATA)                             |
| Network    | Intel X550T2 10 GbE                                         |
| Boot Drive | Kingston 1 TB NV3 NVMe M.2                                  |
| OS         | Unraid (pre-installed, license included)                    |

> The i7-14700's integrated UHD 770 is why single-GPU passthrough works
> cleanly on this box. Unraid runs its console off the iGPU, and the
> RTX 4060 LP is never touched by the host — it passes cleanly to the VM.

---

## Reference Links

- [Unraid VM Passthrough Guide](https://forums.unraid.net/topic/133563-gpu-passthrough-is-easy-heres-how/)
- [Unraid Gaming VM (community)](https://forums.unraid.net/topic/147697-unraid-gaming-vm-guide-with-nvidia-gpu-passthrough/)
- [Sunshine on GitHub](https://github.com/LizardByte/Sunshine)
- [Sunshine official site](https://app.lizardbyte.dev/Sunshine/)
- [Moonlight official site](https://moonlight-stream.org/)
- [Tailscale download](https://tailscale.com/download)
- [Steam Headless (Docker)](https://github.com/Steam-Headless/docker-steam-headless)
- [Games on Whales (Docker)](https://github.com/games-on-whales/gow)

---

## Section 1 — Prepare Unraid for GPU Passthrough

### 1.1 Enable IOMMU in BIOS

Before Unraid can pass a PCIe device to a VM, your CPU and motherboard
need IOMMU enabled. On Intel this is called **VT-d**. On the X15's
Gigabyte MW34-SP0 board:

1. Reboot the X15 and press **Delete** to enter BIOS.
2. Go to **Advanced → CPU Configuration → Intel Virtualization Technology → Enabled**.
3. Go to **Advanced → System Agent → VT-d → Enabled**.
4. Save and reboot.

> If you're not sure whether VT-d is active, check after boot in Unraid's
> **Settings → VM Manager** — it will warn you if IOMMU is not detected.

### 1.2 Enable VMs in Unraid

1. In the Unraid web UI go to **Settings → VM Manager**.
2. Set **Enable VMs** to `Yes`.
3. Set **PCIe ACS override** to `Downstream` (only needed if devices share
   IOMMU groups — try without it first).
4. Click **Apply**.

### 1.3 Isolate the RTX 4060 LP for Passthrough

1. In Unraid go to **Tools → System Devices**.
2. Find your RTX 4060 entry — it will show as `NVIDIA Corporation AD107`
   or similar.
3. Check the box next to the 4060 **and** the associated NVIDIA
   High Definition Audio device on the same IOMMU group.
4. Click **Bind Selected to VFIO** at the bottom of the page.
5. Reboot Unraid.

> **Do not bind the iGPU (Intel UHD 770) to VFIO.** Unraid needs it for
> its own display. Only bind the discrete 4060 LP.

After rebinding, the 4060 will no longer be usable by Unraid itself — it
will show as claimed by VFIO in **System Devices**. This is correct.

### 1.4 Verify IOMMU Groups

Confirm the 4060 sits in its own IOMMU group. If it shares a group with
other devices, those devices will also be unavailable to the host when
the GPU is passed through.

In the Unraid terminal, run:

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  echo "Group $(basename $(dirname $d)): $(lspci -nns ${d##*/})"
done | sort -V
```

Look for your 4060. Ideally it's alone in its group or sharing only with
its own audio device. If it shares a group with unrelated devices, enable
**ACS override** in VM Manager settings and reboot.

---

## Section 2 — Create the Windows Gaming VM

### 2.1 Download Required Files

Before creating the VM, download these two ISOs and place them on your
Unraid server (e.g. under `/mnt/user/isos/`):

- **Windows 11 ISO** — from
  [Microsoft's download page](https://www.microsoft.com/software-download/windows11).
- **VirtIO drivers ISO** — from the Fedora project:
  [virtio-win.iso](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso).

> VirtIO drivers are what give the VM fast storage and network
> performance. Without them Windows falls back to slow generic drivers.

### 2.2 Create the VM Template

In the Unraid web UI, go to the **VMs** tab and click
**Add VM → Windows 11**.

**CPU & Memory**

- **Logical CPUs:** assign 8–12 cores. On the i7-14700, pin to physical
  cores not shared with Unraid's main workloads.
- **Initial Memory:** `16384 MB` (16 GB) is a good gaming baseline. Don't
  allocate more than half your total RAM.
- **Enable CPU Pinning:** click the CPU grid and pin dedicated cores.
  Avoid hyperthreads shared with the array or Docker.

**Storage**

- **Primary vDisk:** create a new virtual disk of at least **250 GB**.
  Store it on your NVMe pool, not the spinning HDD array.
- **vDisk Bus:** set to `VirtIO` (not SATA).
- **CD-ROM 1:** your Windows 11 ISO.
- **CD-ROM 2:** the VirtIO drivers ISO.

**GPU Passthrough**

- **Graphics Card:** select your RTX 4060 LP from the PCIe device list.
- **Sound Card:** select the NVIDIA HD Audio device that was bound
  alongside the GPU.
- Remove the **VNC graphics** entry — you won't need it once the GPU is
  passed through.

**Machine & BIOS**

- **Machine:** `Q35`
- **BIOS:** `OVMF` (UEFI)
- **Enable TPM:** `Yes` (required for Windows 11)

Click **Create**. The VM will appear in your VM list.

> **Do not start the VM yet.** Plug a real monitor and keyboard into the
> X15's rear GPU ports first, or have a dummy HDMI plug installed.
> Sunshine isn't running yet, so you need a physical display for the
> initial Windows setup.

### 2.3 Install Windows 11

1. Start the VM.
2. Follow the Windows installer. When prompted to choose a drive, you
   won't see the VirtIO disk yet.
3. Click **Load Driver → Browse**, point to the VirtIO CD →
   `vioscsi → w11 → amd64`. This loads the storage driver so Windows can
   see the virtual disk.
4. Complete the Windows 11 install normally.
5. Once at the Windows desktop, open File Explorer → the VirtIO CD → run
   `virtio-win-gt-x64.msi`. Install all drivers.
6. Reboot the VM.

> If Windows 11 forces you to sign in with a Microsoft account and you
> want a local account: during setup when it asks for network, press
> `Shift+F10` to open a command prompt and run `oobe\bypassnro` — this
> restarts setup and offers an offline account option.

---

## Section 3 — Install and Configure Sunshine

Sunshine is the streaming host. It runs inside the Windows VM and uses
the 4060's NVENC encoder to stream the desktop to Moonlight clients.

### 3.1 Install a Virtual Display (Headless Setup)

If you're going to run this VM headlessly — no physical monitor plugged
into the X15 — you need to give the GPU something to encode:

- **Option A (recommended):** plug a cheap HDMI dummy plug into the GPU's
  HDMI port (~$5–10 on Amazon; search "HDMI dummy plug headless"). This
  tricks the GPU into thinking a display is connected.
- **Option B:** install a Virtual Display Driver (VDD) — search for
  `parsec-vdd` on GitHub. More flexible (lets you set custom resolutions)
  but more setup involved.

> Without a display — real or virtual — Sunshine cannot do
> hardware-accelerated encoding on the GPU and will either fail to start
> or fall back to slow software encoding.

### 3.2 Download and Install Sunshine

1. Inside the Windows VM, open a browser and go to
   [github.com/LizardByte/Sunshine/releases](https://github.com/LizardByte/Sunshine/releases).
2. Download the latest `sunshine-windows-installer.exe`.
3. Run the installer as **Administrator** — accept the driver installation
   prompts (Sunshine installs virtual controller and audio drivers).
4. Reboot the VM when prompted.

After rebooting, Sunshine will start automatically as a Windows service
and appear as a tray icon.

### 3.3 First-Time Configuration

1. Right-click the Sunshine tray icon → **Open Sunshine** (or navigate to
   `https://localhost:47990` in the VM's browser).
2. Your browser will show a certificate warning — accept it and proceed.
3. Create a username and password when prompted.
4. In the Sunshine web UI go to **Configuration → Audio/Video**.

**Recommended settings:**

- **Encoder:** `nvenc` (hardware) — should auto-detect your 4060.
- **Codec:** `AV1` if your client supports it, otherwise `HEVC`. AV1
  gives better quality at lower bitrate.
- **Resolution:** `1920×1080` for 1080p clients, `2560×1440` if streaming
  to a 1440p display.
- **FPS:** `60` (or `120` if your network can handle it).

> Leave bitrate at auto initially. Sunshine will negotiate with the
> Moonlight client. You can tune it later if you see compression
> artifacts.

### 3.4 Add Your Games and Apps

In the Sunshine web UI, go to **Applications**. Sunshine ships with a
**Desktop** entry by default (streams the full Windows desktop). Add
Steam or an individual game as a launch target:

1. Click **Add Application**.
2. **Name:** `Steam Big Picture`
3. **Command:** `C:\Program Files (x86)\Steam\steam.exe -bigpicture`
4. Save.

Moonlight will show each configured application as a tile the client can
launch directly.

---

## Section 4 — Set Up Moonlight on Your Client Device

### 4.1 Install Moonlight

Moonlight is available on almost every platform. Install it on whatever
device you're gaming from:

- **Windows / macOS / Linux:**
  [moonlight-stream.org](https://moonlight-stream.org/) → download the
  desktop client.
- **Android:** Google Play Store → search "Moonlight Game Streaming".
- **iOS / iPadOS / Apple TV:** App Store → Moonlight Game Streaming.
- **Steam Deck:** Discover Store (Desktop Mode) → Moonlight.

Moonlight is completely free and open source with no ads or subscriptions.

### 4.2 Pair Moonlight with Sunshine

1. Make sure your client device is on the same network as the X15.
2. Open Moonlight — it should automatically discover the X15/VM on the
   local network. If not, tap the `+` button and enter the VM's IP
   address.
3. Click the X15 host tile — Moonlight will show a 4-digit PIN.
4. Go back to the Sunshine web UI on the VM → **PIN Pairing** tab →
   enter the PIN.
5. Moonlight is now paired and will remember the host.

> After pairing once over LAN, Moonlight remembers the client
> permanently. You don't need to re-pair after reboots.

### 4.3 Start Streaming

1. In Moonlight, click your X15 host.
2. Choose **Desktop** or **Steam Big Picture** (or any app you
   configured).
3. The stream will connect — you should see the Windows desktop or Steam.

If the stream looks blurry or has artifacts, go to Moonlight's settings
and increase the bitrate. For a LAN connection, **50–80 Mbps** gives
excellent quality. Over a strong Wi-Fi 6 connection, **30–50 Mbps** is
usually enough.

---

## Section 5 — Stream From Outside Your Home (Tailscale)

If you want to play from outside the house without port forwarding, the
cleanest solution is [Tailscale](https://tailscale.com/download) — the
same tool covered in the 45Homelab Tailscale vs NetBird video. Tailscale
creates a private WireGuard mesh between your devices, so Moonlight sees
the X15 as if it's on the local network from anywhere.

### 5.1 Install Tailscale on the VM

1. Inside the Windows VM, go to
   [tailscale.com/download](https://tailscale.com/download).
2. Download and install the Windows client.
3. Sign in with your Tailscale account — the VM gets a `100.x.x.x` IP on
   your Tailscale network.

### 5.2 Install Tailscale on Your Client Device

1. Install Tailscale on your phone, laptop, or whatever you're gaming
   from.
2. Sign in with the same Tailscale account.
3. In Moonlight, add the VM's Tailscale IP (`100.x.x.x`) as a host
   manually if it doesn't auto-discover.

> For better performance outside the house, set bitrate to
> **20–30 Mbps** in Moonlight settings. Remote streaming is limited by
> your home upload speed and the client's download speed.

---

## Section 6 — CPU Core Pinning (Don't Skip This)

CPU pinning is the single most impactful tuning step. Without it,
Unraid's array operations and Docker containers compete with the gaming
VM for the same CPU cores — you'll see frame time spikes and stutters
during parity checks or when containers are doing heavy work.

The i7-14700 has 8 Performance cores (P-cores) and 12 Efficiency cores
(E-cores), totalling 20 cores. The general strategy:

- Give the gaming VM dedicated **P-cores** — these are cores 0–7
  (threads 0–15 with hyperthreading).
- Leave at least **4 cores for Unraid** itself — the E-cores are fine
  for this.
- **Never give the VM core 0** — that's used by system interrupts.

**How to pin cores in Unraid VM Manager:**

1. Edit your Windows VM in Unraid.
2. Click the CPU grid — you'll see a grid of logical processors.
3. Click to select the cores for the VM. A safe starting point: select
   cores `2–9` (4 P-cores with hyperthreading = 8 logical processors).
4. Leave core `0`, core `1`, and the E-cores unchecked for Unraid.
5. Save the VM config.

> The exact optimal pinning depends on your workload mix. If you're not
> running heavy Docker workloads during gaming sessions, you can give
> the VM more cores. Start conservative and expand if needed.

> If you change core pinning while the VM is running, the changes don't
> take effect until the VM is fully **stopped and restarted** — not just
> rebooted.

---

## Section 7 — Troubleshooting

**GPU not appearing in VM template**

- Confirm the 4060 was bound to VFIO in **Tools → System Devices** and
  Unraid was rebooted afterwards.
- Check that VT-d is enabled in BIOS.
- Run the IOMMU group check from Section 1.4 and confirm the GPU is in
  its own group.

**Black screen after VM starts**

- The VM is likely booting but has no display output. Confirm the dummy
  HDMI plug is installed or VDD is running.
- Try connecting a real monitor temporarily to verify the VM is
  actually posting.
- Check the VM's VNC output in Unraid to see if Windows is at a login
  screen.

**Sunshine won't use hardware encoding**

- Confirm the GPU is visible in Windows **Device Manager** inside the
  VM — it should show as `NVIDIA GeForce RTX 4060`.
- Install or update NVIDIA drivers inside the VM if the GPU shows with
  an error.
- Confirm a display is attached (dummy plug or VDD) — without it NVENC
  may refuse to initialize.

**Moonlight can't find the host**

- Confirm Sunshine is running — check the system tray in the VM.
- Ensure the client device and the VM are on the same network (or both
  connected to Tailscale for remote).
- Try adding the VM's IP address manually in Moonlight using the `+`
  button.
- Temporarily disable Windows Firewall to test — if that fixes it, add
  Sunshine to Windows Firewall exceptions.

**High latency / lag**

- Use a wired Ethernet connection between the X15 and your router if at
  all possible.
- Reduce stream bitrate in Moonlight settings — high bitrate over
  congested Wi-Fi causes buffering.
- Enable the 4060's AV1 codec in Sunshine if your client supports it —
  better quality at lower bitrate.
- Check CPU pinning — if the VM is competing for cores it will cause
  frame time spikes that look like lag.

**Anti-cheat blocking the game**

- This is a known limitation of VM-based gaming. Kernel-level anti-cheat
  (Easy Anti-Cheat, BattlEye) is increasingly VM-aware.
- Check the community compatibility list: many games work, some don't.
  The situation changes with every driver update.
- Hiding VM status is possible but not covered here — search the Unraid
  forums for "anti-cheat VM hiding" for current methods.

---

## Section 8 — Lightweight Alternative: Docker Gaming Containers

If you'd rather not manage a full Windows VM, two projects offer
GPU-passthrough gaming inside Docker containers.

### Steam Headless

[github.com/Steam-Headless/docker-steam-headless](https://github.com/Steam-Headless/docker-steam-headless)

Runs Steam with full GPU passthrough inside a container. No Windows
license required. Works with Moonlight as the streaming client.

- **Pros:** fast to spin up, no OS licensing, lower overhead than a full
  VM, fits the Docker-everything workflow.
- **Cons:** some games have Linux compatibility issues, anti-cheat
  compatibility is worse than a Windows VM, less community documentation.

### Games on Whales (Wolf)

[github.com/games-on-whales/gow](https://github.com/games-on-whales/gow)

More modular than Steam Headless. Designed to run individual games and
applications inside containers and stream them to Moonlight clients via
Wolf, its streaming component.

- **Pros:** very clean architecture, actively developed, good docs.
- **Cons:** more configuration involved, same anti-cheat caveats as
  Steam Headless.

> Both of these are excellent for single-player and non-competitive
> games. For anything with kernel-level anti-cheat, the Windows VM from
> Section 2 is the better path.

---

## References

- [Unraid VM Passthrough Guide](https://forums.unraid.net/topic/133563-gpu-passthrough-is-easy-heres-how/)
- [Unraid Gaming VM (community)](https://forums.unraid.net/topic/147697-unraid-gaming-vm-guide-with-nvidia-gpu-passthrough/)
- [Sunshine on GitHub](https://github.com/LizardByte/Sunshine)
- [Sunshine official site](https://app.lizardbyte.dev/Sunshine/)
- [Moonlight official site](https://moonlight-stream.org/)
- [Tailscale download](https://tailscale.com/download)
- [Steam Headless (Docker)](https://github.com/Steam-Headless/docker-steam-headless)
- [Games on Whales (Docker)](https://github.com/games-on-whales/gow)
