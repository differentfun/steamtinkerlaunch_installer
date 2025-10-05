# SteamTinkerLaunch Installer (Apt-based)

This repository contains a self-contained Bash installer for [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) on Debian/Ubuntu and other apt-based distributions.

The installer will:

- Install required build/runtime dependencies via `apt-get`.
- Download and build a recent version of [Yad](https://github.com/v1cont/yad) from source (ensuring at least `7.2`).
- Symlink `yad` into `/usr/local/bin` and `/usr/bin` if needed.
- Clone the SteamTinkerLaunch repository and run `make install` with the chosen prefix.
- Register STL as a Steam compatibility tool for the calling user.

A single installer script is provided:

- `install_steamtinkerlaunch.sh`: Installer with English output and usage.

## Requirements

- Root privileges: run directly as root or via `pkexec` (the script elevates using `pkexec` when available).
- Apt-based distribution (Debian, Ubuntu, Linux Mint, etc.).
- Internet connection (downloads Yad sources and SteamTinkerLaunch).

## Quick Start

Run the installer:

```bash
chmod +x ./install_steamtinkerlaunch.sh
./install_steamtinkerlaunch.sh
```

Alternatively, using `pkexec` (GUI prompt for credentials):

```bash
pkexec bash ./install_steamtinkerlaunch.sh
```

After installation, restart Steam. If you installed as root, you may need to run the registration step as your user:

```bash
steamtinkerlaunch compat add
```

## Options

Options

- `--prefix DIR`: Install prefix for SteamTinkerLaunch (default: `/usr/local`).
- `--branch NAME`: Git branch or tag of SteamTinkerLaunch to install (default: `master`).
- `--yad-prefix DIR`: Install prefix for Yad (default: same as `--prefix`).
- `--yad-version VER`: Yad version to install (default: latest release). Accepts plain versions (e.g., `12.1`) or GitHub tag style (e.g., `v12.1`).
- `-h`, `--help`: Show usage and exit.

### Examples

Install with defaults (prefix `/usr/local`, STL `master`, latest Yad):

```bash
./install_steamtinkerlaunch.sh
```

Install STL to a custom prefix with a specific branch, and put Yad under a separate prefix:

```bash
./install_steamtinkerlaunch.sh \
  --prefix /opt/stl \
  --branch v12.10 \
  --yad-prefix /opt/yad \
  --yad-version 12.1
```

## What the script does

1. Installs required packages via `apt-get` (e.g., build tools, GTK3 dev libs).
2. Removes the system `yad` package (if present) to avoid conflicts.
3. Downloads the requested Yad release from GitHub and builds it from source.
4. Symlinks `yad` to `/usr/local/bin` and `/usr/bin` if necessary.
5. Verifies the Yad version is `>= 7.2`.
6. Clones SteamTinkerLaunch and runs `make install` with the selected `PREFIX`.
7. Registers STL as a Steam compatibility tool for the non-root calling user.

## Notes and Caveats

- The script removes the distro `yad` package (`apt-get purge yad`) if installed, replacing it with a source-built Yad. This is intentional to ensure a recent enough version. Reinstall your distro `yad` if you prefer to revert.
- The installer targets apt-based distros. For other distributions, adapt the dependency installation step accordingly.
- The script creates symlinks for `yad` in `/usr/local/bin` and `/usr/bin` to ensure it is found by dependent tools.
- If you ran the installer entirely as `root`, you may need to run `steamtinkerlaunch compat add` as your regular user to complete registration.

## Uninstall

This repo does not include an automated uninstall. To undo changes manually:

- Remove SteamTinkerLaunch files under your chosen `PREFIX` (default `/usr/local`).
- Remove `yad` from the chosen `YAD_PREFIX` and restore your system `yad` via `apt-get install yad` if desired.
- Remove any symlinks created at `/usr/local/bin/yad` and `/usr/bin/yad` if they are no longer needed.

## License

See `LICENSE.md` in this repository. SteamTinkerLaunch is licensed and maintained upstream at its own repository; consult its license for details.

## Credits

- [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) by @sonic2kk
- [Yad](https://github.com/v1cont/yad) by @v1cont
