# Homelable

[Homelable](https://github.com/Pouzor/homelable) is a self-hosted homelab visualizer. You draw your network on a canvas, but you don't have to draw all of it by hand: it scans your network with nmap, imports your Proxmox VMs and LXCs over the API, keeps a live online/offline status on every node, and writes a documentation page for each device.

In my setup it runs in a Proxmox LXC, pulls in every VM and container from my Proxmox host, and shows the Docker containers running inside one of my VMs as their own nodes. This page walks through the whole build, from install to a finished canvas.

---

## YouTube Video

<!-- youtube:url -->
- [Watch the Homelable walkthrough on YouTube](https://youtu.be/VIDEO_ID)
<!-- youtube:url:end -->

---

## What This Page Contains

- Installing Homelable in a Proxmox LXC (with a Docker option)
- First login, password change, and pointing the scanner at your subnet
- Scanning the network and working the Device Inventory
- Creating a read-only Proxmox API token and importing your VMs and LXCs
- Getting real IPs onto VMs (QEMU guest agent) and LXCs (static `net0`)
- Building the canvas: nodes, links, nesting, zones, text, layout and style
- Showing Docker containers inside a VM, automatically, through the Homelable API
- Status checks, documentation pages, export, sharing, and updates
- Troubleshooting the problems I actually ran into
- Every script used, in full

---

## How Homelable Fits Together

A few terms show up everywhere, so here they are up front:

| Term | What it is |
|---|---|
| **Canvas** | A diagram. You can have several (Network, Rack, Home Automation). Each one saves on its own. |
| **Node** | One thing on the canvas: a router, switch, server, VM, LXC, Docker container, and so on. The node type sets its icon and shape. |
| **Link** | A line between two nodes. The link type (`ethernet`, `wifi`, `virtual`, `vlan`, `fibre`...) sets its colour and style. |
| **Nesting / container mode** | A node that holds other nodes. A Proxmox host holds its VMs and LXCs; a VM can hold its Docker containers. |
| **Zone** | A labelled background box for grouping nodes by area or purpose ("Network", "Rack 1", "IoT"). |
| **Device Inventory** | The holding area for everything a scan or import finds before it goes on the canvas. |
| **Documentation** | A Markdown page per device, written from what Homelable found, plus your own runbooks. |

The flow is always the same: **discover** (scan or import) into the inventory, **approve** onto the canvas, then **arrange** with nesting, links and zones.

---

## Install Homelable

### Option 1: Proxmox LXC (what I use)

The Proxmox community scripts have a Homelable installer. Run this in the **Proxmox host** shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/homelable.sh)"
```

The defaults are fine: an unprivileged Debian 13 container with 2 cores, 2 GB RAM and 8 GB disk. When it finishes, the UI is on port `3000`:

```text
http://<homelable-lxc-ip>:3000
```

Where things live inside the LXC:

| Path / name | What |
|---|---|
| `/opt/homelable` | The app |
| `/opt/homelable/backend/.env` | All backend settings (scanner, Proxmox token, auth) |
| `/opt/homelable/data` | The SQLite database |
| `homelable` | systemd service for the backend |
| `~/homelable.creds` | The generated admin password |
| `/root/change_password.sh` | Changes the admin password and restarts the service |

### Option 2: Docker

On any Docker host:

```bash
curl -fsSL https://raw.githubusercontent.com/Pouzor/homelable/main/install.sh | bash
cd homelable && docker compose up -d
```

The UI is on `http://<docker-host-ip>:3000` and the default login is `admin` / `admin`. Change it before you do anything else (see the Homelable install docs linked in References for generating the password hash). The `.env` file sits next to `docker-compose.yml`, and after editing it you apply changes with `docker compose up -d`.

One thing to know with Docker: on the default bridge network the scanner can't see MAC addresses. If you want MACs, run the backend with `network_mode: host` as described in the install docs, or use the LXC install.

> The rest of this guide uses the LXC paths. On Docker, swap `/opt/homelable/backend/.env` for the `.env` next to your compose file, and `systemctl restart homelable` for `docker compose up -d`.

---

## First Login and Basic Config

### Get the password

**On the Homelable LXC:**

```bash
cat ~/homelable.creds
```

Log in as `admin` with that password. To set your own:

```bash
/root/change_password.sh
```

### Point the scanner at your subnet

The installer defaults the scan range to `192.168.1.0/24`. If your LAN is anything else, change it, or the scan will come back empty.

**On the Homelable LXC:**

```bash
vim /opt/homelable/backend/.env
```

```dotenv
SCANNER_RANGES=["192.168.1.0/24"]
```

Use your own subnet. It's a JSON array, so you can list more than one: `["192.168.1.0/24","10.0.10.0/24"]`.

Two other settings worth knowing about in the same file:

```dotenv
# How often node status is checked, in seconds
STATUS_CHECKER_INTERVAL=60

# Optional deep scan: extra ports to probe for services on non-standard ports
SCANNER_HTTP_RANGES=["3000-3999","8000-9999"]
SCANNER_HTTP_PROBE_ENABLED=true
```

By default the scanner uses nmap's standard port list, which misses a lot of homelab apps on odd ports. The deep scan settings fix that.

Apply the changes:

```bash
systemctl restart homelable
systemctl status homelable --no-pager
```

> Use the full path when editing: `vim /opt/homelable/backend/.env`. If you run `vim backend/.env` from your home folder, vim opens an empty buffer and fails to save with `E212: Can't open file for writing`, because that folder doesn't exist there.

---

## Scan the Network

1. In the sidebar, click **Scan Network**. Scan History opens and updates until the scan is done.
2. Open **Device Inventory**. Every host it found is listed with IP, MAC, hostname and detected services.
3. For each device, pick one:
   - **Approve** puts it on the canvas as a node.
   - **Hide** moves it to the Hidden list, where you can restore it later.
   - **Ignore** dismisses it.

I hide phones, TVs and smart appliances on my main canvas so it stays readable, and only approve infrastructure.

> Hold off approving your Proxmox host and its guests from the scan. Do the Proxmox import first (next section). A plain network scan can lump several guests into one device behind the host, while the Proxmox import creates each VM and LXC as its own node.

---

## Connect Proxmox

Homelable reads Proxmox through the API with a **read-only** token. It never needs write access.

### Create the token

**On the Proxmox host**, as root:

```bash
# Dedicated user for Homelable
pveum user add homelable@pve --comment "Homelable read-only"

# Read-only role on everything
pveum acl modify / --users homelable@pve --roles PVEAuditor

# Token with privilege separation
pveum user token add homelable@pve homelable --privsep 1

# With privilege separation the token needs its own ACL too
pveum acl modify / --tokens 'homelable@pve!homelable' --roles PVEAuditor
```

The `token add` command prints a table. Copy the `value` field right away; Proxmox only shows it once.

> Don't skip the last command. With `--privsep 1`, the token only gets the permissions you give it directly, even though the user already has `PVEAuditor`. Missing this is the most common cause of "Authentication failed".

Prefer the web UI? Datacenter > Permissions > API Tokens > Add, then Datacenter > Permissions > Add > **API Token Permission** with path `/`, your token, role `PVEAuditor`, and **Propagate** ticked.

### Test the token

**On the Homelable LXC:**

```bash
curl -k -H 'Authorization: PVEAPIToken=homelable@pve!homelable=<token-secret>' https://<proxmox-ip>:8006/api2/json/nodes
```

JSON with your node name means it works. Keep the single quotes, otherwise bash trips over the `!`.

### Add the token to Homelable

**On the Homelable LXC:**

```bash
vim /opt/homelable/backend/.env
```

Add these lines at the bottom, with no spaces in front of them:

```dotenv
PROXMOX_TOKEN_ID=homelable@pve!homelable
PROXMOX_TOKEN_SECRET=<token-secret>
PROXMOX_HOST=<proxmox-ip>
PROXMOX_PORT=8006
PROXMOX_VERIFY_TLS=false
```

`PROXMOX_VERIFY_TLS=false` is for the default self-signed Proxmox certificate. Leave it out if you've put a real certificate on Proxmox.

```bash
systemctl restart homelable
```

The token lives only in `.env`. Homelable never stores it in the database or sends it back through the API.

### Run the import

1. Sidebar > **Import from...** > **Proxmox**.
2. **Proxmox Host**: your Proxmox IP. **Port**: `8006`.
3. Leave **Token ID** and **Token Secret** blank so it uses the token from `.env`.
4. Untick **Verify TLS certificate** (self-signed cert).
5. Click **Test Connection**.
6. Under **Send devices to**:
   - **Device inventory only** lets you review first. I use this so templates and VMs I'm about to delete never reach the canvas.
   - **Inventory + canvas** drops everything straight onto the canvas.
7. Click **Import**.

What you get:

- Your Proxmox host becomes a `proxmox` node, shown as a box.
- Each VM becomes a `vm` node and each LXC an `lxc` node, nested inside the host.
- Running/stopped maps to online/offline. CPU, RAM and disk come in as properties.

If a guest's IP matches a device the network scan already found, that device is updated instead of duplicated.

### Turn on auto-sync

Once the token is in `.env`, **Settings** shows a **Proxmox auto-sync** section. Turn it on and set the interval (minimum 300 seconds). Each run updates status, specs and IPs, and adds new guests as pending. It never deletes anything, so a VM you remove from Proxmox stays on the canvas until you delete the node yourself.

---

## Get IPs Onto Your VMs and LXCs

The Proxmox import is only as good as the IP data Proxmox has:

- **VMs** report their IP through the **QEMU guest agent**. No agent, no IP.
- **LXCs** are read from their static `net0` config. Containers set to `ip=dhcp` come in without an IP.

### Check what you have

`enable-qga.sh` (full script in the Scripts section) shows, for every VM, whether the agent option is on and whether the agent answers, and lists every LXC on DHCP. It's a dry run by default.

**On the Proxmox host:**

```bash
chmod +x enable-qga.sh
./enable-qga.sh
```

```text
=== VMs ===
VMID   NAME                      STATUS    AGENT_OPT  AGENT_PING
100    docker-host               running   off(dry)   -
109    lab-03                    running   on         ok
...
=== LXCs without a static IP in net0 ===
CTID   HOSTNAME                  NET0
101    ubuntu-docker             name=eth0,bridge=vmbr0,...,ip=dhcp,...
```

### Install the guest agent on a VM

Two parts: the package inside the VM, and the agent option on the VM in Proxmox.

**Inside the VM** (Debian/Ubuntu):

```bash
apt install -y qemu-guest-agent
```

**On the Proxmox host** (replace `100` with the VM ID):

```bash
qm set 100 --agent enabled=1
qm shutdown 100 && qm start 100
```

It has to be a full shutdown and start from Proxmox. A reboot from inside the guest doesn't add the agent device.

**Check it on the Proxmox host:**

```bash
qm agent 100 ping && qm agent 100 network-get-interfaces | grep -m3 ip-address\"
```

Doing a lot of VMs? Install the package everywhere first (with Ansible or by hand), then on the Proxmox host:

```bash
APPLY=1 RESTART=1 ./enable-qga.sh
```

That enables the option on every VM missing it and cold-restarts only the running ones it changed. Leave off `RESTART=1` if you'd rather restart them yourself. For VMs that are currently stopped, you can turn the option on now and install the package the next time they boot:

```bash
for id in 103 112 113; do qm set $id --agent enabled=1; done
```

Windows VMs need the guest agent installer from the virtio-win ISO (`guest-agent\qemu-ga-x86_64.msi`).

### Pin LXC IPs

`pin-lxc-ips.sh` reads each running DHCP container's current IP and gateway and writes them back into `net0` as static. Everything else in `net0` (MAC, firewall, IPv6) is left alone.

**On your router/DHCP server first:** reserve each container's MAC and IP, or make sure those IPs are outside the DHCP pool. Otherwise the router will eventually hand one of them to something else.

**On the Proxmox host:**

```bash
chmod +x pin-lxc-ips.sh
./pin-lxc-ips.sh            # dry run, shows the new net0 for each
APPLY=1 ./pin-lxc-ips.sh    # apply
```

The IPs don't change, so each container only drops its network for a moment.

To do one container by hand:

```bash
pct set 105 --net0 name=eth0,bridge=vmbr0,ip=192.168.1.50/24,gw=192.168.1.1
```

Then re-run the Proxmox import (or wait for auto-sync) to pick up the IPs.

---

## Build the Canvas

### Nodes

- **From the inventory:** approve devices in **Device Inventory**.
- **By hand:** sidebar > **Add Node**. Pick a type, give it a label, and optionally an IP and a status check method.

Useful node types: `router`, `firewall`, `switch`, `ap`, `server`, `nas`, `proxmox`, `vm`, `lxc`, `docker_host`, `docker_container`. The type only changes the icon and shape, so pick whatever reads best.

Things a scan won't find usually need adding by hand: an **Internet** node at the top, unmanaged switches, and anything on another VLAN the scanner can't reach.

### Links

Drag from a connection dot on one node to a dot on another. Then pick the link type:

| Type | Use it for |
|---|---|
| `ethernet` | Physical cables |
| `wifi` | Wireless clients and APs |
| `fibre` | Fibre/DAC uplinks |
| `vlan` | Logical VLAN links |
| `virtual` | Host to VM/LXC (the Proxmox import draws these for you) |
| `cluster` | Cluster members |

The chain I draw first: **Internet > Router > Switch > Proxmox host**, then switch to AP, NAS and anything else physical.

### Nesting

Nesting is how a Proxmox host shows its guests inside it. The import does this for you, but you can also do it by hand: drag a `vm` or `lxc` onto a `proxmox` node and confirm **Add to container**. Click a container's header to collapse or expand it.

A nested node can't be dragged outside its parent. If a child grows bigger than its parent box, it can't move at all. Resize the parent by dragging its corner, or use `homelable-fix-layout.sh` (see the Docker section).

### Zones

Zones are coloured background boxes for grouping.

1. Sidebar > **Add Zone**. Give it a title and colour.
2. Drag and resize it.
3. Drop nodes onto it. Homelable asks if you want to add them to the zone.

The zones I use:

- **Network:** Internet, router, switches, APs
- **Compute:** the Proxmox box (optional, since the box already groups its guests)
- **Storage:** NAS boxes
- **Clients / IoT:** only if you want them on this canvas

Two or three zones is plenty. Any more and the diagram gets busy.

### Text, layout and style

- **Add Text** drops a free label, handy for section titles or notes.
- **Auto Layout** (top bar) re-spaces everything. Use it once after a big import, then fine-tune by hand.
- **Style** (top bar) switches between Default, Dark, Light, Neon and Matrix, or a custom palette. It's saved per canvas.
- **Save** (or `Ctrl+S`) saves the canvas. Saving is manual unless you turn on **Autosave canvas** in Settings.

---

## Show Docker Containers Inside a VM

Homelable doesn't discover Docker containers. It goes down to the VM and LXC level, and a network scan only sees the ports a container publishes, which show up as **services** on the VM's node.

To show each container as its own node inside the VM, you have two options.

### By hand

1. **Add Node** with type `docker_container` for each container.
2. Turn on **container mode** on the VM node (edit the node), then drag each container onto it.

Containers on Docker's default bridge share the VM's IP. Leave the IP blank on the container nodes and put the port in the label or a property, otherwise Homelable may see them as duplicates of the VM.

### Automatically, with the API

Everything the UI does goes through Homelable's REST API at `/api/v1` (interactive docs at `http://<homelable-ip>:3000/docs`). `homelable-docker-nodes.sh` uses it to:

- read `docker ps` on the Docker host
- find that VM's node in Homelable by IP
- turn on container mode and size the box
- create a `docker_container` node for each container in a grid inside it, with its published ports shown on the node and the image in the detail panel

It skips containers that already have a node, so it's safe to re-run after you add containers.

**On the Docker host VM:**

```bash
apt install -y curl jq
chmod +x homelable-docker-nodes.sh
```

Dry run first:

```bash
HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='<password>' ./homelable-docker-nodes.sh
```

Leave helper containers (databases, Redis, sidecars) off the canvas with `SKIP`:

```bash
SKIP="app-postgres app-redis" HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='<password>' ./homelable-docker-nodes.sh
```

When the dry run looks right:

1. In Homelable, click **Save**.
2. Run it again with `APPLY=1` in front. You should see `HTTP 200` for container mode and `HTTP 201` for each container.
3. Reload the Homelable page. Don't click Save on a tab that was open before the script ran, because the UI saves the whole canvas at once and would wipe out the new nodes.

> Note the `:3000` in `HL_URL`. Without it the script talks to port 80, gets nothing back, and reports "Login failed".

### If the VM box is now too big for the Proxmox box

The VM sits inside the Proxmox host box, and the host box is still its default size of about 300x200. A child bigger than its parent can't be dragged, and it covers the other guests. `homelable-fix-layout.sh` grows the host box, puts the big VM on the left, and lays out every other guest in a grid beside it.

**On the Docker host VM:**

```bash
chmod +x homelable-fix-layout.sh
HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='<password>' ./homelable-fix-layout.sh
```

Check the dry run, save the canvas, run it again with `APPLY=1`, then reload the page.

---

## Status Monitoring

Every node can have a check method. The results stream to the canvas live, and the sidebar footer keeps an online/offline count.

| Method | What it checks |
|---|---|
| `ping` | ICMP reachability |
| `http` | GET, online if status is below 500 |
| `https` | GET with TLS verify |
| `tcp` | TCP connect to `host:port` |
| `ssh` | TCP connect to port 22 |
| `prometheus` | GET `/metrics` |
| `health` | GET `/health` |

Set it when you add or edit a node. For Docker container nodes, `http` or `tcp` against `<docker-vm-ip>:<port>` works well.

In **Settings** you can change the check interval and turn on **Check services individually**, which probes each detected service port and turns offline services red.

---

## Documentation Pages

Sidebar > **Documentation**. Picking any device with no page writes one from what Homelable knows: type, IPs, MAC, hardware, services, network. After that it's yours to edit, and Homelable won't overwrite it.

- The **Devices** tree can be grouped by zone, type, subnet, status and more.
- The **Library** is for your own pages, with templates for runbooks, incidents, procedures, decisions and network overviews.
- Link pages with `[[device:name]]` or `[[Page title]]`.
- Every save keeps a revision. The clock icon shows history, diffs and restore.
- **Regenerate** rebuilds a device page from current data, keeping the old one in history.

---

## Export and Share

- **PNG / SVG** (top bar): an image of the canvas for docs, thumbnails or a README.
- **Export** (YAML): the whole canvas, nodes and links, which you can import again.
- **Hide IP addresses** (Settings): hides IPs on the canvas, which is useful for screenshots and recording.
- **Live View**: a read-only canvas URL with no login, for a wall display. Add a key to `.env` and restart:

```dotenv
LIVEVIEW_KEY=<random-secret>
```

```text
http://<homelable-ip>:3000/view?key=<random-secret>
```

Homelable is meant for your LAN. Don't expose it to the internet.

---

## Updating Homelable

**LXC install, on the Homelable LXC:**

```bash
update
```

The community script update backs up `.env`, deploys the new release, rebuilds, and keeps your `data` folder.

**Docker install:**

```bash
curl -fsSL https://raw.githubusercontent.com/Pouzor/homelable/main/install.sh | bash
cd homelable && docker compose pull && docker compose up -d
```

The sidebar shows a version badge when a new release is out.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `E212: Can't open file for writing` in vim | Relative path to a folder that doesn't exist where you are | Use the full path: `vim /opt/homelable/backend/.env` |
| Settings still says "No API token configured" | Backend not restarted, or `.env` lines have leading spaces | `systemctl restart homelable`; strip leading spaces in vim with `:%s/^\s\+//` |
| Proxmox import: "Authentication failed" | Token ACL missing (privsep), or wrong token ID/secret | Run `pveum acl modify / --tokens 'homelable@pve!homelable' --roles PVEAuditor` |
| Proxmox import: "TLS verification failed" | Self-signed Proxmox cert | Untick Verify TLS, or set `PROXMOX_VERIFY_TLS=false` |
| One node with a dozen IPs and the wrong hostname | Network scan lumped guests together | Delete it and use the Proxmox import for the host and guests |
| VMs imported without an IP | No QEMU guest agent | Install the package, enable the option, cold restart |
| LXCs imported without an IP | `ip=dhcp` in `net0` | Pin a static IP with `pin-lxc-ips.sh` |
| Scan finds nothing | `SCANNER_RANGES` is still `192.168.1.0/24` | Set your subnet in `.env` and restart |
| Apps on odd ports missing from services | nmap's default port list | Set `SCANNER_HTTP_RANGES` and `SCANNER_HTTP_PROBE_ENABLED=true` |
| API script: "Login failed" | Missing `:3000` in `HL_URL`, or wrong password | `HL_URL=http://<homelable-ip>:3000` |
| `jq: error: syntax error, unexpected label` | jq 1.6 treats `$label` as a reserved word | Use the scripts on this page, which avoid it |
| Can't drag a nested VM | It's bigger than its parent box | Resize the parent, or run `homelable-fix-layout.sh` |
| New nodes vanished after Save | Saved from a tab opened before the API script ran | Re-run the script and reload before saving |

---

## Scripts

### enable-qga.sh

Runs on the **Proxmox host**. Reports the guest agent state on every VM and lists DHCP LXCs. `APPLY=1` turns on the agent option, and `RESTART=1` also cold-restarts the changed VMs.

```bash
#!/usr/bin/env bash
# enable-qga.sh
# Run on the Proxmox host as root.
#
# - Turns on the QEMU guest agent option for every VM that doesn't have it.
# - Optionally cold-restarts changed VMs so the agent device appears.
# - Checks which running VMs have a responding agent.
# - Lists LXCs whose net0 has no static IP (Homelable can't read their IP).
#
# Usage:
#   ./enable-qga.sh               # dry run, shows what would change
#   APPLY=1 ./enable-qga.sh       # enable the agent option on VMs
#   APPLY=1 RESTART=1 ./enable-qga.sh
#                                    # also shutdown + start changed running VMs

set -uo pipefail

APPLY="${APPLY:-0}"
RESTART="${RESTART:-0}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-180}"

changed=()

echo "=== VMs ==="
printf "%-6s %-25s %-9s %-10s %s\n" "VMID" "NAME" "STATUS" "AGENT_OPT" "AGENT_PING"

for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    cfg="$(qm config "$vmid")"
    name="$(awk -F': ' '/^name:/ {print $2}' <<<"$cfg")"
    status="$(qm status "$vmid" | awk '{print $2}')"
    agent="$(awk -F': ' '/^agent:/ {print $2}' <<<"$cfg")"

    if [[ "$agent" == 1* || "$agent" == *enabled=1* ]]; then
        agent_opt="on"
    else
        agent_opt="off"
        if [[ "$APPLY" == "1" ]]; then
            if qm set "$vmid" --agent enabled=1 >/dev/null; then
                agent_opt="set"
                changed+=("$vmid")
            else
                agent_opt="FAILED"
            fi
        else
            agent_opt="off(dry)"
        fi
    fi

    ping="-"
    if [[ "$status" == "running" && "$agent_opt" == "on" ]]; then
        if qm agent "$vmid" ping >/dev/null 2>&1; then
            ping="ok"
        else
            ping="no reply (package not installed/running?)"
        fi
    fi

    printf "%-6s %-25s %-9s %-10s %s\n" "$vmid" "${name:0:25}" "$status" "$agent_opt" "$ping"
done

if [[ "$APPLY" == "1" && "$RESTART" == "1" && ${#changed[@]} -gt 0 ]]; then
    echo
    echo "=== Cold restarting changed running VMs ==="
    for vmid in "${changed[@]}"; do
        if [[ "$(qm status "$vmid" | awk '{print $2}')" == "running" ]]; then
            echo "VM $vmid: shutting down (timeout ${SHUTDOWN_TIMEOUT}s)..."
            if qm shutdown "$vmid" --timeout "$SHUTDOWN_TIMEOUT"; then
                qm start "$vmid" && echo "VM $vmid: started"
            else
                echo "VM $vmid: clean shutdown failed, left as is. Handle manually."
            fi
        fi
    done
elif [[ ${#changed[@]} -gt 0 ]]; then
    echo
    echo "Agent option set on: ${changed[*]}"
    echo "These need a full shutdown + start (not a reboot from inside) to take effect."
fi

echo
echo "=== LXCs without a static IP in net0 ==="
printf "%-6s %-25s %s\n" "CTID" "HOSTNAME" "NET0"
found=0
for ctid in $(pct list | awk 'NR>1 {print $1}'); do
    cfg="$(pct config "$ctid")"
    host="$(awk -F': ' '/^hostname:/ {print $2}' <<<"$cfg")"
    net0="$(awk -F': ' '/^net0:/ {print $2}' <<<"$cfg")"
    if [[ -z "$net0" || "$net0" == *ip=dhcp* || "$net0" != *ip=* ]]; then
        printf "%-6s %-25s %s\n" "$ctid" "${host:0:25}" "${net0:-<none>}"
        found=1
    fi
done
[[ "$found" == "0" ]] && echo "All LXCs have a static IP in net0."
```

### pin-lxc-ips.sh

Runs on the **Proxmox host**. Rewrites `ip=dhcp` in each running LXC's `net0` with its current IP and gateway.

```bash
#!/usr/bin/env bash
# pin-lxc-ips.sh
# Run on the Proxmox host as root.
# For each running LXC on ip=dhcp, reads its current IPv4 + gateway and
# rewrites net0 with that same address as static. Other net0 options are kept.
#   ./pin-lxc-ips.sh          dry run
#   APPLY=1 ./pin-lxc-ips.sh  apply

set -uo pipefail
APPLY="${APPLY:-0}"

printf "%-6s %-18s %-20s %-15s %s\n" "CTID" "HOSTNAME" "CURRENT_IP" "GATEWAY" "RESULT"

for ctid in $(pct list | awk 'NR>1 {print $1}'); do
    cfg="$(pct config "$ctid")"
    net0="$(awk -F': ' '/^net0:/ {print $2}' <<<"$cfg")"
    host="$(awk -F': ' '/^hostname:/ {print $2}' <<<"$cfg")"

    [[ "$net0" == *ip=dhcp* ]] || continue

    if [[ "$(pct status "$ctid" | awk '{print $2}')" != "running" ]]; then
        printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "-" "-" "skipped (stopped)"
        continue
    fi

    cidr="$(pct exec "$ctid" -- ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4; exit}')"
    gw="$(pct exec "$ctid" -- ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"

    if [[ -z "$cidr" || -z "$gw" ]]; then
        printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "${cidr:--}" "${gw:--}" "skipped (no IP/gw found)"
        continue
    fi

    # Replace only the IPv4 ip=dhcp, leave ip6= alone
    new_net0="$(sed -E "s/(^|,)ip=dhcp(,|$)/\1ip=${cidr//\//\\/},gw=${gw}\2/" <<<"$net0")"

    if [[ "$APPLY" == "1" ]]; then
        if pct set "$ctid" --net0 "$new_net0"; then
            result="pinned"
        else
            result="FAILED"
        fi
    else
        result="would set: $new_net0"
    fi

    printf "%-6s %-18s %-20s %-15s %s\n" "$ctid" "${host:0:18}" "$cidr" "$gw" "$result"
done
```

### homelable-docker-nodes.sh

Runs on the **Docker host VM**. Creates a `docker_container` node for each running container, nested inside the VM's node.

```bash
#!/usr/bin/env bash
# homelable-docker-nodes.sh
# Run on the Docker host VM as a user that can run `docker ps`.
#
# Reads the running containers and creates a Homelable `docker_container` node for
# each one, nested inside that VM's node (container mode). Safe to re-run:
# containers that already have a node under the VM are skipped.
#
# Needs: curl, jq   (apt install -y curl jq)
#
# Usage:
#   HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='yourpass' ./homelable-docker-nodes.sh          # dry run
#   APPLY=1 HL_URL=http://<homelable-ip>:3000 HOST_IP=<docker-vm-ip> HL_USER=admin HL_PASS='yourpass' ./homelable-docker-nodes.sh  # create nodes
#
# Before APPLY: save your canvas in the browser. After APPLY: reload the page
# (do not click Save on an old, unreloaded tab or it will overwrite the new nodes).

set -uo pipefail

HL_URL="${HL_URL:?set HL_URL, e.g. http://192.168.1.20:3000}"
HL_USER="${HL_USER:?set HL_USER}"
HL_PASS="${HL_PASS:?set HL_PASS}"
HOST_IP="${HOST_IP:?set HOST_IP to the IP of this VM as shown in Homelable}"
APPLY="${APPLY:-0}"
COLS="${COLS:-4}"                      # containers per row inside the VM box
CELL_W=230; CELL_H=100; PAD_X=20; PAD_Y=70

# Helper containers (databases, caches, sidecars) to leave off the canvas.
# Space separated container names, e.g. SKIP="app-postgres app-redis"
SKIP=" ${SKIP:-} "

# Optional notes per container, shown on the node's detail panel. Example:
#   [myapp]="Uses myapp-postgres + myapp-redis"
declare -A NOTES=(
)

API="$HL_URL/api/v1"
command -v jq >/dev/null || { echo "jq is required: apt install -y jq"; exit 1; }

# --- Log in ---
TOKEN="$(curl -s "$API/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$HL_USER" --arg p "$HL_PASS" '{"username":$u,"password":$p}')" \
  | jq -r '.access_token // empty')"
[[ -n "$TOKEN" ]] || { echo "Login failed. Check HL_URL / HL_USER / HL_PASS."; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")

# --- Find the VM node for this host ---
NODES="$(curl -s "$API/nodes" "${AUTH[@]}")"
PARENT="$(jq -c --arg ip "$HOST_IP" '
  [ .[] | select((.ip // "") | split(",") | map(gsub("\\s";"")) | index($ip)) ]
  | (map(select(.type=="vm")) + .) | .[0] // empty' <<<"$NODES")"
[[ -n "$PARENT" ]] || { echo "No node with IP $HOST_IP found. Import the VM from Proxmox first."; exit 1; }

PID="$(jq -r .id <<<"$PARENT")"
PLABEL="$(jq -r .label <<<"$PARENT")"
DESIGN="$(jq -r '.design_id // empty' <<<"$PARENT")"
echo "Parent node: $PLABEL ($PID, type $(jq -r .type <<<"$PARENT"))"

EXISTING="$(jq -r --arg pid "$PID" '.[] | select(.parent_id==$pid) | .label' <<<"$NODES")"

# --- Collect containers ---
mapfile -t ROWS < <(docker ps --format '{{.Names}}|{{.Image}}|{{.Ports}}' | sort)

TODO=()
for row in "${ROWS[@]}"; do
  name="${row%%|*}"
  [[ "$SKIP" == *" $name "* ]] && { echo "  skip (helper): $name"; continue; }
  grep -qxF "$name" <<<"$EXISTING" && { echo "  skip (exists): $name"; continue; }
  TODO+=("$row")
done

# Count every child (existing + new) to size the VM box
total=$(( $(grep -c . <<<"$EXISTING") + ${#TODO[@]} ))
rows=$(( (total + COLS - 1) / COLS ))
WIDTH=$(( PAD_X * 2 + COLS * CELL_W ))
HEIGHT=$(( PAD_Y + rows * CELL_H + 20 ))
start=$(grep -c . <<<"$EXISTING")

echo "Will create ${#TODO[@]} node(s); VM box ${WIDTH}x${HEIGHT}"
[[ "$APPLY" == "1" ]] || echo "(dry run: set APPLY=1 to create)"

# --- Turn on container mode on the VM node ---
if [[ "$APPLY" == "1" && ${#TODO[@]} -gt 0 ]]; then
  curl -s -o /dev/null -w "  container mode on $PLABEL: HTTP %{http_code}\n" -X PATCH "$API/nodes/$PID" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --argjson w "$WIDTH" --argjson h "$HEIGHT" '{"container_mode":true,"width":$w,"height":$h}')"
fi

# --- Create the container nodes ---
i=$start
for row in "${TODO[@]}"; do
  IFS='|' read -r name image ports <<<"$row"
  pub="$(grep -oE ':[0-9]+(-[0-9]+)?->' <<<"$ports" | sed -E 's/^:(.*)->$/\1/' | sort -un | paste -sd, -)"
  x=$(( PAD_X + (i % COLS) * CELL_W ))
  y=$(( PAD_Y + (i / COLS) * CELL_H ))
  note="${NOTES[$name]:-}"

  body="$(jq -n \
    --arg lbl "$name" --arg pid "$PID" --arg design "$DESIGN" \
    --arg image "$image" --arg pub "${pub:-none published}" --arg note "$note" \
    --argjson x "$x" --argjson y "$y" '
    {
      "type": "docker_container", "label": $lbl, "parent_id": $pid,
      "pos_x": $x, "pos_y": $y,
      "notes": (if $note == "" then null else $note end),
      "properties": [
        {"key":"Ports", "value":$pub,   "icon":null, "visible":true},
        {"key":"Image", "value":$image, "icon":null, "visible":false}
      ]
    } + (if $design == "" then {} else {"design_id":$design} end)')"

  if [[ "$APPLY" == "1" ]]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' "$API/nodes" "${AUTH[@]}" \
      -H 'Content-Type: application/json' -d "$body")"
    echo "  create $name (ports: ${pub:-none}): HTTP $code"
  else
    echo "  would create $name (ports: ${pub:-none}) at $x,$y"
  fi
  i=$((i + 1))
done
```

### homelable-fix-layout.sh

Runs anywhere with `curl` and `jq` that can reach Homelable. Grows the Proxmox host box and lays out its guests around a large container-mode VM.

```bash
#!/usr/bin/env bash
# homelable-fix-layout.sh
# Grows the Proxmox host box and lays out its VMs/LXCs so a large container-mode
# VM box (for example one holding Docker containers) fits beside them.
#
# Needs: curl, jq
#
#   HL_URL=http://<homelable-ip>:3000 HL_USER=admin HL_PASS='...' HOST_IP=<docker-vm-ip> ./homelable-fix-layout.sh          dry run
#   APPLY=1 HL_URL=http://<homelable-ip>:3000 HL_USER=admin HL_PASS='...' HOST_IP=<docker-vm-ip> ./homelable-fix-layout.sh  apply
set -uo pipefail
HL_URL="${HL_URL:?set HL_URL}"; HL_USER="${HL_USER:?set HL_USER}"; HL_PASS="${HL_PASS:?set HL_PASS}"
HOST_IP="${HOST_IP:?set HOST_IP to the IP of the large VM}"; APPLY="${APPLY:-0}"
COLS="${COLS:-3}"; CELL_W=240; CELL_H=100; PAD=20; TOP=60
API="$HL_URL/api/v1"

TOKEN="$(curl -s "$API/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$HL_USER" --arg p "$HL_PASS" '{"username":$u,"password":$p}')" | jq -r '.access_token // empty')"
[[ -n "$TOKEN" ]] || { echo "Login failed"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")
NODES="$(curl -s "$API/nodes" "${AUTH[@]}")"

BIG="$(jq -c --arg ip "$HOST_IP" '[.[] | select(.type=="vm" and ((.ip // "") | split(",") | map(gsub("\\s";"")) | index($ip)))][0] // empty' <<<"$NODES")"
[[ -n "$BIG" ]] || { echo "No VM with IP $HOST_IP"; exit 1; }
BID="$(jq -r .id <<<"$BIG")"; HID="$(jq -r '.parent_id // empty' <<<"$BIG")"
[[ -n "$HID" ]] || { echo "That VM has no parent, nothing to fix"; exit 0; }
BW="$(jq -r '(.width // 960) | floor' <<<"$BIG")"; BH="$(jq -r '(.height // 490) | floor' <<<"$BIG")"
echo "Host box: $(jq -r --arg h "$HID" '.[] | select(.id==$h) | .label' <<<"$NODES") ($HID)"
echo "Big VM:   $(jq -r .label <<<"$BIG") ${BW}x${BH}"

mapfile -t OTHERS < <(jq -r --arg h "$HID" --arg b "$BID" \
  '.[] | select(.parent_id==$h and .id!=$b) | "\(.id)|\(.label)"' <<<"$NODES" | sort -t'|' -k2)
rows=$(( (${#OTHERS[@]} + COLS - 1) / COLS ))
COLX=$(( PAD + BW + 40 ))
HW=$(( COLX + COLS * CELL_W + PAD ))
GRID_H=$(( rows * CELL_H )); (( GRID_H > BH )) && INNER=$GRID_H || INNER=$BH
HH=$(( TOP + INNER + 30 ))
echo "Host box -> ${HW}x${HH}; ${#OTHERS[@]} other guests in $COLS columns"

patch() { # id json label
  if [[ "$APPLY" == "1" ]]; then
    curl -s -o /dev/null -w "  $3: HTTP %{http_code}\n" -X PATCH "$API/nodes/$1" "${AUTH[@]}" -H 'Content-Type: application/json' -d "$2"
  else
    echo "  would patch $3: $2"
  fi
}

patch "$HID" "$(jq -nc --argjson w "$HW" --argjson h "$HH" '{"container_mode":true,"width":$w,"height":$h}')" "host box"
patch "$BID" "$(jq -nc --argjson x "$PAD" --argjson y "$TOP" '{"pos_x":$x,"pos_y":$y}')" "$(jq -r .label <<<"$BIG")"
i=0
for row in "${OTHERS[@]}"; do
  id="${row%%|*}"; name="${row#*|}"
  x=$(( COLX + (i % COLS) * CELL_W )); y=$(( TOP + (i / COLS) * CELL_H ))
  patch "$id" "$(jq -nc --argjson x "$x" --argjson y "$y" '{"pos_x":$x,"pos_y":$y}')" "$name"
  i=$((i + 1))
done
[[ "$APPLY" == "1" ]] || echo "(dry run: set APPLY=1 to apply)"
```

---

## Files

- [Browse on GitHub](https://github.com/Zack-45D/45homelab/tree/main/docs/public/files/homelable)
- [Download All Files (ZIP)](/files/homelable/homelable-files.zip)
- [Homelable on GitHub](https://github.com/Pouzor/homelable)

---

## References

- [Homelable README](https://github.com/Pouzor/homelable)
- [Homelable installation docs](https://github.com/Pouzor/homelable/blob/main/INSTALLATION.md)
- [Homelable features](https://github.com/Pouzor/homelable/blob/main/FEATURES.md)
- [Homelable Proxmox import docs](https://github.com/Pouzor/homelable/blob/main/docs/proxmox-import.md)
- [Homelable REST API docs](https://github.com/Pouzor/homelable/blob/main/docs/api.md)
- [Proxmox community script: Homelable](https://community-scripts.org/scripts/homelable)
- [Proxmox VE: QEMU guest agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
- [Proxmox VE: user management and API tokens](https://pve.proxmox.com/wiki/User_Management)
