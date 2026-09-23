# Tunnel Toggle

A one-click tray tool for managing **Google Cloud SQL Auth Proxy** and **SSH tunnels** — on both **macOS** (via a [SwiftBar](https://swiftbar.app) menu bar plugin) and **Linux** (via a system-tray indicator + systemd service). Ships with a `tunnel` CLI too.

## Features

- Start/stop Cloud SQL Proxy and SSH tunnels from your menu bar / system tray
- Color-coded status: all connected / partial / none
- Per-tunnel and bulk start/stop controls
- Copy connection strings to the clipboard
- Auto-refreshing status (every 5 seconds)
- A `tunnel` CLI for terminal-only workflows
- Configure any number of tunnels via a simple JSON file

## How it works

Each entry in `tunnels.json` maps a remote database (or SSH forward) to a local port. Tunnel Toggle launches `cloud-sql-proxy` (or `ssh -N`) per tunnel, tracks each process by PID, and reflects live status in a tray icon. The tray front-ends and the CLI all drive the same helper scripts under `lib/`, so status stays consistent however you interact with it.

## Platform support

| Platform | Front-end | Installer |
|----------|-----------|-----------|
| macOS    | SwiftBar menu bar plugin | `./install.sh` |
| Linux    | StatusNotifierItem tray daemon (Python/GTK) + systemd user service | `./install-linux.sh` |
| Any      | `tunnel` CLI | none — run it directly |

---

## Linux setup

### 1. Dependencies

The tray daemon is a small Python/GTK app that publishes a StatusNotifierItem. Install the runtime bits with your package manager:

```bash
# Arch
sudo pacman -S --needed jq python-gobject gtk3 libayatana-appindicator

# Debian / Ubuntu
sudo apt install jq python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1

# Fedora
sudo dnf install jq python3-gobject gtk3 libayatana-appindicator-gtk3
```

You also need [`cloud-sql-proxy`](https://cloud.google.com/sql/docs/mysql/sql-proxy) (v2) on your `PATH` for SQL tunnels, and the [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated with Application Default Credentials:

```bash
gcloud auth application-default login
```

> **Tray requirement:** the indicator needs an SNI-capable system tray. KDE Plasma shows it natively; GNOME needs the *AppIndicator and KStatusNotifierItem* extension; wlroots compositors (Sway, Hyprland) need a bar with an SNI tray module such as Waybar. No tray? Use the `tunnel` CLI instead — the daemon is optional.

### 2. Configure

```bash
cp tunnels.json.example tunnels.json
# edit tunnels.json with your tunnels (see Configuration below)
```

### 3. Install

```bash
./install-linux.sh
```

This validates your dependencies and config, then writes a `tunnel-tray.service` systemd **user** unit pointing at wherever you cloned the repo, and enables it. The tray icon appears immediately and starts on every login.

Useful commands:

```bash
systemctl --user status tunnel-tray.service     # is the tray running?
journalctl --user -u tunnel-tray.service -f     # tray logs
systemctl --user restart tunnel-tray.service    # after editing tunnels.json
```

Editing `tunnels.json` requires a tray restart (the menu is built at startup): `systemctl --user restart tunnel-tray.service`.

---

## macOS setup

Install the prerequisites via [Homebrew](https://brew.sh):

```bash
brew install jq
brew install cloud-sql-proxy   # for SQL tunnels
brew install --cask swiftbar
```

Authenticate ADC for SQL tunnels:

```bash
gcloud auth application-default login
```

Then:

```bash
cp tunnels.json.example tunnels.json
# edit tunnels.json with your tunnels
./install.sh
```

Launch SwiftBar and, when prompted, point its plugin folder at the location the installer reports. The Tunnel Toggle appears in your menu bar.

---

## Configuration

All tunnel definitions live in `tunnels.json` (gitignored, so your details stay local).

```json
{
  "proxy_binary": "/home/you/.local/bin/cloud-sql-proxy",
  "tunnels": [
    {
      "name": "dev",
      "label": "Dev",
      "instance": "my-project:us-central1:my-db-dev",
      "port": 3307
    }
  ],
  "ssh_tunnels": [
    {
      "name": "cortex",
      "label": "C",
      "forward": "-L 8420:127.0.0.1:8420",
      "host": "cortex@example.com",
      "opts": ""
    }
  ]
}
```

### SQL tunnel fields

| Field      | Required | Description                                                      |
|------------|----------|------------------------------------------------------------------|
| `name`     | Yes      | Short identifier (used in the CLI and filenames, e.g. `dev`)     |
| `instance` | Yes      | GCP connection string: `project:region:instance`                 |
| `port`     | Yes      | Local port to bind (e.g. `3307`)                                 |
| `label`    | No       | Display name in the tray (defaults to capitalized `name`)        |

### SSH tunnel fields

| Field     | Required | Description                                               |
|-----------|----------|-----------------------------------------------------------|
| `name`    | Yes      | Short identifier (e.g. `cortex`)                          |
| `forward` | Yes      | Forward spec: `-L local:remote:port` or `-R remote:local` |
| `host`    | Yes      | SSH target: `[user@]host`                                 |
| `label`   | No       | Display name in the tray (defaults to capitalized `name`) |
| `opts`    | No       | Extra SSH options (e.g. `"-p 2222 -i ~/.ssh/key"`)        |

The resulting SSH command is: `ssh -N ${opts} ${forward} ${host}`

### Top-level fields

| Field          | Required | Description                                                  |
|----------------|----------|--------------------------------------------------------------|
| `proxy_binary` | No       | Path to `cloud-sql-proxy` (auto-detected from `PATH` if omitted) |

> **Note:** the SQL proxy binds to `127.0.0.1`, so only this machine can reach it. Containers cannot reach it via `host.docker.internal`; switch `--address` in `lib/proxy-ctl.sh` back to `0.0.0.0` if one needs to.

## CLI

The `tunnel` script works everywhere, no tray required:

```bash
./tunnel status              # show all tunnel statuses (default)
./tunnel up [name|all]       # start tunnel(s)
./tunnel down [name|all]     # stop tunnel(s)
./tunnel restart [name|all]  # restart tunnel(s)
./tunnel logs <name>         # tail a tunnel's logs
```

Lower-level helpers (used by the tray) are available too:

```bash
./lib/proxy-ctl.sh start|stop|toggle|status|copy <name|all>   # SQL tunnels
./lib/ssh-ctl.sh   start|stop|toggle|status|copy <name|all>   # SSH tunnels
./lib/bulk-ctl.sh  start|stop                                 # everything
```

## Uninstall

- **macOS:** `./uninstall.sh` (stops tunnels, removes the SwiftBar symlink, cleans up state).
- **Linux:** `systemctl --user disable --now tunnel-tray.service && rm ~/.config/systemd/user/tunnel-tray.service`, then `./tunnel down all`.

## Troubleshooting

- **Tunnel won't start** — check logs at `~/.tunnel-toggle/sql/<name>.log` or `~/.tunnel-toggle/ssh/<name>.log`, or `./tunnel logs <name>`.
- **Port already in use** — `ss -tlnp | grep <port>` (Linux) or `lsof -i :<port>` (macOS).
- **SQL auth errors** — run `gcloud auth application-default login`.
- **Tray icon missing (Linux)** — confirm your desktop has an SNI tray (see the note above); check `systemctl --user status tunnel-tray.service`.
- **Menu is stale after a config change** — restart the tray: `systemctl --user restart tunnel-tray.service`.
- **SSH host key changed** — remove the old key from `~/.ssh/known_hosts`.
- **SSH key passphrase** — load the key into ssh-agent: `ssh-add ~/.ssh/your_key`.

## License

[MIT](LICENSE)
