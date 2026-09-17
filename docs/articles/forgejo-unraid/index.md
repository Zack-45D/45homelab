# Forgejo on Unraid

## YouTube Video

<!-- youtube:url -->
- [45Homelab Forgejo on Unraid Video](https://www.youtube.com/watch?...)
<!-- youtube:url:end -->

---

## What this page contains

This guide covers self-hosting [Forgejo](https://forgejo.org/) on Unraid via
Docker Compose, reachable privately over Tailscale with nothing forwarded to
the internet. It includes:

- Deploying Forgejo behind a Tailscale sidecar
- Fixing the SSH clone-URL vs. internal-bind-port split
- Migrating a real repository in from GitHub
- Setting up a Forgejo Actions runner and getting a genuine passing CI check
- An optional push mirror back to GitHub as a live backup
- Working the repo day to day beyond the web UI: `git`, `tea`, `lazygit`,
  GUI clients

Every step here was walked through live, including the parts that didn't
work the first try. Those are called out explicitly, since they're the
parts most guides skip and most people hit anyway.

**Prerequisites:**

- Unraid 7.x with Docker enabled (**Settings → Docker → Enable Docker: Yes**).
  If Apps only lets you install plugins and not containers, this is why.
- The **Compose Manager** plugin (Community Apps → search "Compose
  Manager"). Get **Compose Manager Plus**, the actively maintained fork —
  the older dcflachs version has been archived.
- A Tailscale account, with **HTTPS Certificates enabled for your tailnet**:
  admin console → **DNS → HTTPS Certificates → Enable**. Nothing prompts you
  for this, but without it Tailscale can't issue a working certificate and
  the private-access piece silently fails with a plain connection-refused
  error. Do this now, not after something doesn't work.
- (Optional, for the GitHub backup piece) a GitHub repo already created and
  left genuinely empty — no README, no license file.

> The Unraid **Tailscale** plugin is worth having separately for reaching
> the Unraid host itself (WebGUI, shares) over your tailnet, but it's not
> what this guide uses to expose Forgejo — that's the sidecar container
> below.

Also worth knowing up front: Forgejo doesn't publish to Docker Hub, and
Community Apps doesn't currently have a well-maintained "Forgejo" template
(only "ForgejoRunner", a different piece, covered further down). The only
real Forgejo image lives at `codeberg.org/forgejo/forgejo`. Docker Compose
is the reliable path in here, not a one-click Apps install.

---

## Deploy Forgejo with a Tailscale Sidecar

Unraid has a nice built-in "Use Tailscale" toggle on the Docker container
edit screen, but it only applies to containers created through Unraid's own
template system. Containers launched via Docker Compose don't get that
toggle — there's no Edit option for them in the GUI at all, only
Console/Stop/Pause/Restart/Logs/Remove. So instead of one container plus a
checkbox, this is two containers working together: Forgejo itself, and a
Tailscale sidecar sharing its network.

1. Generate a reusable Tailscale auth key: admin console → **Settings →
   Keys → Generate auth key**. Check **Reusable**, leave Ephemeral off.
2. Create the serve config Tailscale will use to proxy traffic:

   ```bash
   mkdir -p /mnt/user/appdata/forgejo-tailscale/state /mnt/user/appdata/forgejo-tailscale/config
   vim /mnt/user/appdata/forgejo-tailscale/config/serve.json
   ```

   ```json
   {
     "TCP": {
       "443": { "HTTPS": true }
     },
     "Web": {
       "${TS_CERT_DOMAIN}:443": {
         "Handlers": {
           "/": { "Proxy": "http://127.0.0.1:3000" }
         }
       }
     },
     "AllowFunnel": {
       "${TS_CERT_DOMAIN}:443": false
     }
   }
   ```

   `${TS_CERT_DOMAIN}` is a Tailscale placeholder, not a shell variable —
   leave it exactly as written.

3. Compose Manager → **Add New Stack**, project folder is fine, defaults
   elsewhere:

   ```yaml
   services:
     tailscale:
       image: tailscale/tailscale:latest
       container_name: forgejo-tailscale
       hostname: forgejo
       environment:
         - TS_AUTHKEY=tskey-auth-PASTE-YOURS-HERE
         - TS_STATE_DIR=/var/lib/tailscale
         - TS_SERVE_CONFIG=/config/serve.json
       volumes:
         - /mnt/user/appdata/forgejo-tailscale/state:/var/lib/tailscale
         - /mnt/user/appdata/forgejo-tailscale/config:/config
       cap_add:
         - NET_ADMIN
         - NET_RAW
       devices:
         - /dev/net/tun:/dev/net/tun
       restart: unless-stopped
       ports:
         - "3000:3000"
         - "222:22"

     forgejo:
       image: codeberg.org/forgejo/forgejo:16
       container_name: forgejo
       network_mode: "service:tailscale"
       depends_on:
         - tailscale
       environment:
         - USER_UID=1000
         - USER_GID=1000
         - TZ=America/Halifax
       restart: unless-stopped
       volumes:
         - /mnt/user/appdata/forgejo:/data
         - /etc/localtime:/etc/localtime:ro
   ```

A few things worth understanding about that file, since it looks unusual if
you haven't done this pattern before:

> **`forgejo` has no ports of its own.** It borrows the `tailscale`
> container's entire network stack via `network_mode: "service:tailscale"`,
> so the ports live on the `tailscale` service instead. `docker ps` will
> show all the port mappings sitting on `forgejo-tailscale`, not `forgejo` —
> that's expected, not a mistake.
>
> This is genuinely **two containers doing two jobs**, not one thing
> duplicated. Forgejo handles git and the web UI. The sidecar handles
> getting traffic to it, both the LAN ports and the tailnet proxy. Stop the
> sidecar and Forgejo loses all network access, LAN included, since it has
> none of its own.

Host port `222` still maps to container port `22` for the same reason as
always — Unraid's own SSH already owns host port 22.

> **If you only ever want this reachable over your tailnet**, drop the
> `ports:` block from the `tailscale` service entirely. The serve config
> still proxies to `127.0.0.1:3000` internally regardless of what's
> published to the LAN, so nothing about the tailnet access breaks — you
> just lose the LAN address as an option.

Bring the stack up.

---

## Run the Setup Wizard

Visit `http://<your-unraid-ip>:3000`. Two things matter here that aren't
obvious from the form itself:

1. **Leave "SSH server port" set to 22.** It's tempting to put 222 here
   since that's your external port, but this field also controls what port
   Forgejo's *internal* SSH server binds to. Set it to 222 and the server
   tries to listen on a port nothing forwards to internally, breaking SSH
   before it even starts. Leave it at 22 — the display-URL fix comes next.
2. **Expand "Administrator account settings" and create your account before
   clicking Install.** If you're also checking "Disable self-registration"
   (recommended for a private instance), skipping this step means there is
   no way to create an account afterward — the signup page will simply
   refuse you.

Everything else (database type, repo paths, domain) is fine left at its
auto-filled defaults.

---

## Fix the SSH Clone URL

After install, Forgejo will display SSH clone URLs using the *internal*
port from setup (22), which nobody outside the container can actually
reach. Fix the display without touching the actual bind:

```bash
vim /mnt/user/appdata/forgejo/gitea/conf/app.ini
```

Under `[server]`:

```ini
SSH_PORT = 222
SSH_LISTEN_PORT = 22
```

`SSH_PORT` is what gets displayed in clone URLs. `SSH_LISTEN_PORT` is what
the server actually binds to internally. They default to matching each
other, which is exactly the trap — split them explicitly. Restart the
container to apply.

---

## Confirm the Tailnet Side Is Working

Don't just assume it's live, check it:

```bash
docker exec forgejo-tailscale tailscale serve status
```

That should show your proxy configuration active. If it instead says "No
serve config", check the container's logs (`docker logs forgejo-tailscale`)
before doing anything else — the most common cause by far is the HTTPS
Certificates prerequisite from the top of this guide not actually being
enabled yet. Tailscale will say so explicitly in the log if that's the
problem.

Once it's active, visit `https://<hostname>.<your-tailnet-name>.ts.net`
from a device on your tailnet. Both that address and the LAN address keep
working side by side.

> Enabling HTTPS Certificates publishes your device and tailnet names (not
> IPs, not content) into the public Certificate Transparency ledger,
> permanently — that's how all publicly trusted TLS certificates work
> everywhere, not something specific to Tailscale. It doesn't grant anyone
> access; reaching the actual service still requires being an authorized
> device on your tailnet. Just pick device names you're fine with being
> technically public — generic names like `forgejo` are a non-issue.

---

## Migrate In a Real Repository

Forgejo calls this a **Migration**, not a fork (fork is for repos already
on the same instance).

1. **+** icon → **New Migration** → choose **GitHub**.
2. Paste the clone URL, e.g. `https://github.com/45Drives/monitoring-stack.git`.
3. Leave Access Token blank for public repos, add one only if GitHub starts
   rate-limiting you.
4. Decide **mirror or one-time copy**:
   - Check **"This repository will be a mirror"** if you want it to
     auto-stay current with upstream — read-only in practice, since a
     mirror gets overwritten on every sync.
   - Leave it unchecked for a repo you actually intend to edit locally —
     that gives you a full independent copy, free to diverge from upstream.
5. **Migrate Repository**.

---

## Push Mirror Back to GitHub (Optional)

The reverse direction from the migration above: Forgejo as the primary,
auto-backing up to a GitHub repo on every push.

1. Create a GitHub Personal Access Token with **repo** scope (or
   **public_repo** for a public repo), plus **workflow** scope if you'll
   ever push to a `.github/workflows` path through this.
2. In your Forgejo repo: **Settings → Repository → Mirror Settings**.
3. Enter the GitHub repo's URL as the Git Remote Repository URL.
4. Expand **Authorization** — GitHub username as the username, the token
   as the password.
5. Check **"Sync when new commits are pushed"**, so it mirrors immediately
   rather than waiting on the periodic interval.
6. **Add Push Mirror**.

> This force-pushes. If the GitHub repo already had a README or license
> file auto-created by GitHub, the first sync overwrites it. Starting from
> a genuinely empty GitHub repo avoids that surprise.

---

## Set Up a Runner and Get a Real, Passing CI Check

Forgejo hosts workflow files — a separate **Forgejo Runner** actually
executes them.

### Smoke-test the check before wiring it into CI

Don't skip this. Run the exact command your workflow will use, once, by
hand, against a real clone:

```bash
cd /tmp
git clone http://<your-unraid-ip>:3000/<you>/<repo>.git
docker run --rm -v /tmp/<repo>:/repo -w /repo python:3.12-slim \
  bash -c "pip install --break-system-packages -q ansible && ansible-playbook --syntax-check -i hosts deploy-monitoring.yml"
```

(That command is the Ansible-specific example from `monitoring-stack` —
adjust the check to whatever's actually true for your repo: a test command,
a lint, a build.)

This step exists because it caught a real problem the first time through
here: `ansible-core` alone doesn't include modules that got split into
separate collections (`firewalld` lives in `ansible.posix`). The full
`ansible` package bundles the common collections and avoided a
whack-a-mole of missing-collection errors role by role. Finding that out in
a disposable container took thirty seconds. Finding it out live in Actions
would not have been thirty seconds.

### Register the runner (current method)

Older guides show a `forgejo-runner register --token ...` command. That's
deprecated as of newer runner versions — don't use it, it fails with
`runner registration token not found`. The current method is config-file
based:

1. Wrench icon → **Site Administration → Actions → Runners → Create new
   Runner**. Copy the **UUID** and **Token** shown.
2. Generate the config file:

   ```bash
   docker run --rm data.forgejo.org/forgejo/runner:12 \
     forgejo-runner generate-config > /mnt/user/appdata/forgejo-runner/data/runner-config.yml
   ```

3. Edit it:

   ```bash
   vim /mnt/user/appdata/forgejo-runner/data/runner-config.yml
   ```

   Under the `runner:` section, add the labels this runner should accept:

   ```yaml
   runner:
     labels:
       - "docker:docker://python:3.12-slim"
   ```

   At the end of the file, add the connection block using your UUID and
   token:

   ```yaml
   server:
     connections:
       forgejo:
         url: http://<your-unraid-ip>:3000/
         uuid: <paste-uuid>
         token: <paste-token>
   ```

4. Run it as a service — no separate register step, the daemon connects
   using the config:

   ```yaml
   services:
     forgejo-runner:
       image: data.forgejo.org/forgejo/runner:12
       container_name: forgejo-runner
       user: "0:0"
       restart: unless-stopped
       volumes:
         - /mnt/user/appdata/forgejo-runner/data:/data
         - /var/run/docker.sock:/var/run/docker.sock
       command: forgejo-runner daemon --config /data/runner-config.yml
   ```

   `user: "0:0"` is needed on Unraid specifically, for host Docker socket
   access.

5. Check the Runners admin page — it should show **Online** once the
   daemon starts.

### Add the workflow

In your repo, `.forgejo/workflows/lint.yml`:

```yaml
name: Ansible Check
on: [push]
jobs:
  syntax-check:
    runs-on: docker
    steps:
      - name: Checkout
        run: |
          apt-get update -qq
          apt-get install -y -qq git
          git clone --depth 1 "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git" .
      - name: Install Ansible
        run: pip install --break-system-packages --quiet ansible
      - name: Syntax check
        run: ansible-playbook --syntax-check -i hosts deploy-monitoring.yml
      - name: YAML lint (informational only)
        continue-on-error: true
        run: |
          pip install --break-system-packages --quiet yamllint
          yamllint -d relaxed .
```

> This doesn't use `actions/checkout@v4`, the usual way to pull the repo
> in. That action is JavaScript — it needs Node.js to run, and a bare
> `python:3.12-slim` job container doesn't have it, so the step fails
> immediately with `exec: "node": executable file not found in $PATH`. This
> is a documented Forgejo Actions gotcha, not a bug — any JS-based action
> needs its runtime present in whatever container you're running on.
> Rather than pull Node.js into the image just to satisfy one step, a plain
> `git clone` using the runner's own `GITHUB_SERVER_URL`/`GITHUB_REPOSITORY`
> environment variables does the identical job with nothing extra
> installed. If you do want `actions/checkout` or other JS actions
> elsewhere, either pick a container image with Node already in it, or add
> an `apt-get install -y nodejs` step first.

Same Ansible install line already proven in the smoke test — nothing new
introduced there. Push, give the runner a minute to pick it up, and check
the Actions tab for a genuine passing run.

---

## Connect From Your Workstation

The web UI works fine, but here's how to actually work with repos day to
day.

**Plain `git`** needs nothing Forgejo-specific:

```bash
git clone http://<your-unraid-ip>:3000/<user>/<repo>.git
```

or over the tailnet, `https://forgejo.<your-tailnet-name>.ts.net/<user>/<repo>.git`.
For auth, either add an SSH key (Settings → SSH/GPG Keys in Forgejo, then
clone via `ssh://git@<your-unraid-ip>:222/<user>/<repo>.git`) or generate a
Personal Access Token (Settings → Applications) and use it as the password
the first time you're prompted.

> One easy trap when generating that token: picking an access scope like
> "All (public, private, and limited)" only decides *which repositories*
> the token can touch — it doesn't grant it any actual permissions on its
> own. Every permission category underneath (repository, issue, admin,
> etc.) defaults to "No access". You have to explicitly set **repository**
> to **Read and Write**, or pushes fail with a plain `Unauthorized` even
> though the token looks correctly scoped at a glance.

| Tool | What it's for | Notes |
|------|----------------|-------|
| [`tea`](https://gitea.com/gitea/tea) | Official Gitea/Forgejo CLI — issues, PRs, repos, without leaving the terminal | Prebuilt binaries at `dl.gitea.io/tea/`, or `brew install tea` / the `gitea-tea` AUR package |
| `lazygit` | Fast terminal UI for staging, diffing, committing | Completely host-agnostic — works the same regardless of git server |
| GitKraken, Sublime Merge | GUI clients | No Forgejo-specific integration — clone with the generic **Clone with URL** option, authenticate with SSH key or token as above |
| VS Code | Built-in Source Control panel | Nothing extra needed, same auth options apply |

```bash
tea login add --name=hl15 --url=http://<your-unraid-ip>:3000 --token=<your-token>
tea issues
tea pulls
tea repos list
```

### Git-over-SSH across the tailnet (optional)

The setup above gives you SSH over the LAN (port 222) and HTTPS-plus-token
over the tailnet. If you also want git-over-SSH reachable across the
tailnet — not just the LAN — that needs one addition to the sidecar's serve
config from earlier. Edit
`/mnt/user/appdata/forgejo-tailscale/config/serve.json` to add a TCP
forward for port 22 alongside the existing HTTPS block:

```json
{
  "TCP": {
    "22": { "TCPForward": "127.0.0.1:22" },
    "443": { "HTTPS": true }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://127.0.0.1:3000" } }
    }
  },
  "AllowFunnel": { "${TS_CERT_DOMAIN}:443": false }
}
```

Restart both containers together (see Worth Knowing below for why it has
to be both) to pick it up. SSH clone URLs then work the same way over the
tailnet, on port 22 directly:
`ssh://git@forgejo.<your-tailnet-name>.ts.net:22/<user>/<repo>.git`. For
most homelab use, the HTTPS-plus-token approach above is simpler, and most
people never need this.

---

## Worth Knowing

- **Restart the two containers together, not one at a time.** If
  `forgejo-tailscale` restarts without `forgejo` restarting alongside it
  (an Unraid reboot, an image update applied to just the sidecar),
  `forgejo` keeps holding a reference to the old, now-gone network
  namespace and effectively loses all network access, LAN included, even
  though it still shows as running. Symptoms look like everything's broken
  at once — LAN refuses to connect, the tailnet URL 502s — even though
  Tailscale itself is fine. The fix is `docker restart forgejo` after the
  sidecar comes back up, but the real fix is using Compose Manager's
  **Compose Restart** on the whole stack instead of restarting containers
  individually, since `depends_on` only controls start order on a fresh
  `up` — it doesn't rescue a dependent container when just one service
  gets bounced.
- Community App templates for Forgejo don't auto-update past major
  versions on purpose (no `latest` tag) — check the image tag
  periodically.
- Serve and Funnel don't add an authentication layer of their own —
  whatever Forgejo's own login enforces is the actual gate.
- Back up both `/mnt/user/appdata/forgejo` (the whole instance: repos,
  config, database) and `/mnt/user/appdata/forgejo-tailscale/state` (the
  sidecar's Tailscale identity — losing it just means re-authenticating as
  a "new" device, not data loss, but still worth keeping).
- Tailscale auth keys expire after 90 days by default even when marked
  reusable. Once the sidecar's joined your tailnet, find it in the admin
  console's machine list and disable key expiry for that specific device,
  otherwise it can silently drop off the tailnet on some future restart.
- If you rotate the runner token for any reason (e.g. it was shared
  somewhere it shouldn't have been), regenerate it from the Runners admin
  page and update `runner-config.yml` to match.

---

## Files

- [`serve.json`](/files/forgejo-unraid/serve.json) — the Tailscale serve
  config from the sidecar setup.
- [`serve-with-ssh.json`](/files/forgejo-unraid/serve-with-ssh.json) — the
  same config with the optional TCP forward for git-over-SSH across the
  tailnet.
- [`docker-compose.forgejo.yml`](/files/forgejo-unraid/docker-compose.forgejo.yml) —
  the Forgejo + Tailscale sidecar stack.
- [`docker-compose.runner.yml`](/files/forgejo-unraid/docker-compose.runner.yml) —
  the runner stack.
- [`runner-config-snippet.yml`](/files/forgejo-unraid/runner-config-snippet.yml) —
  the `runner:` and `server:` blocks to add to a generated runner config.
- [`lint.yml`](/files/forgejo-unraid/lint.yml) — the example CI workflow
  from the runner section.

> All downloadable files for this article live in
> `docs/public/files/forgejo-unraid/`.

---

## References

- [Forgejo](https://forgejo.org/)
- [Forgejo Docker install docs](https://forgejo.org/docs/latest/admin/installation-docker/)
- [Forgejo Actions docs](https://forgejo.org/docs/latest/user/actions/)
- [Tailscale — "Forge your own path" (Forgejo + Serve writeup)](https://tailscale.com/blog)
- [Tailscale — Enabling HTTPS](https://tailscale.com/kb/1153/enabling-https)
