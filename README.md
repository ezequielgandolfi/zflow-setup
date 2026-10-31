# zflow setup

Installs [zflow](https://github.com/ezequielgandolfi/zflow), a visual automation builder, as a service on Linux.
The [releases](https://github.com/ezequielgandolfi/zflow-setup/releases) of this repository are zflow's releases.

## Requirements

- Debian, Ubuntu or Raspberry Pi OS, 64-bit (x86_64 or aarch64), with systemd
- Root access (sudo)
- Internet access while installing and updating (GitHub, nodejs.org and the npm registry)

The installer brings its own Node.js; it doesn't touch a Node.js you already have.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ezequielgandolfi/zflow-setup/main/install.sh | sudo bash
```

Then open `http://<this machine>:4000`. Options go after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/ezequielgandolfi/zflow-setup/main/install.sh | sudo bash -s -- --port 8080
```

| Option              | Does                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `--version <x.y.z>` | Installs that release instead of the latest                                        |
| `--port <port>`     | The Studio's port (default 4000), only on the first install                        |
| `--host <address>`  | The Studio's address (default 0.0.0.0, every interface), only on the first install |
| `--file <tarball>`  | Installs a release tarball from disk                                               |
| `--uninstall`       | Removes zflow, keeping its data                                                    |
| `--purge`           | With `--uninstall`, also deletes the data and settings                             |

Running the installer again reinstalls over the current copy and keeps the data and settings.

The Studio has no login yet: anyone who can reach the port can use it. Keep it on a trusted network, or set
`HOST=127.0.0.1` and put it behind a reverse proxy.

## Update

On the Studio's Admin page, open **Updates**, check for updates and install the new version. From a terminal:

```sh
sudo zflow update            # the latest release
sudo zflow update 1.4.0      # a given release
```

Before switching, the updater backs up the database. If the new version doesn't start, it goes back to the previous
version and restores the backup.

## Manage

```sh
zflow status
zflow logs            # or: zflow logs engine | zflow logs studio
sudo zflow restart
sudo zflow uninstall  # add --purge to delete the data too
```

## Where things are

| Path                     | Holds                                                                         |
| ------------------------ | ----------------------------------------------------------------------------- |
| `/etc/zflow/zflow.env`   | Settings (ports, addresses, `PLUGINS_DIR`); `sudo zflow restart` applies them |
| `/var/lib/zflow`         | Data: the database, installed plugins, plugin files                           |
| `/var/lib/zflow/backups` | Database backups taken before the last updates                                |
| `/opt/zflow`             | The installed releases (`current` is the running one) and Node.js             |

zflow runs as the `zflow` user in two services, `zflow-engine` and `zflow-studio`, grouped by `zflow.target`. The
user is in the `dialout` group, so it can use serial devices such as Zigbee adapters.
