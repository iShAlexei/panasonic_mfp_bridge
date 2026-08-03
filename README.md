# Panasonic KX-MB1500 Network Bridge

Turn a USB-only Panasonic KX-MB1500/KX-MB1500RU multifunction device into a modern network printer and scanner.

## What it provides

- CUPS printing through the official Panasonic GDI filter
- IPP/AirPrint discovery through CUPS + Avahi
- SANE scanning through the official Panasonic `panamfs` backend
- eSCL/AirScan scanning through AirSane
- Tested architecture: Proxmox VM, Ubuntu Server 24.04 LTS, x86_64
- Clients: macOS and Windows printing/scanning; iPhone/iPad printing

## Important

Panasonic driver files are proprietary and are **not included**. Download the official x86_64 Linux printer and scanner driver archives yourself.

Expected archives:

```text
mccgdi-2.0.10-x86_64.tar.tar
panamfs-scan-1.3.1-x86_64.tar.tar
```

## Proxmox USB passthrough

Pass the complete USB device to the VM by Vendor/Product ID:

```text
04da:0f0b Panasonic KX-MB1500RU
```

In Proxmox: VM → Hardware → Add → USB Device → Use USB Vendor/Device ID.

Inside Ubuntu, verify:

```bash
lsusb | grep 04da:0f0b
```

## Installation

```bash
git clone YOUR_REPOSITORY_URL
cd panasonic-mfp-bridge
chmod +x install.sh uninstall.sh scripts/*.sh
sudo ./install.sh \
  --printer-driver ~/drivers/mccgdi-2.0.10-x86_64.tar.tar \
  --scanner-driver ~/drivers/panamfs-scan-1.3.1-x86_64.tar.tar
```

The installer will:

1. Install Ubuntu dependencies.
2. Extract only the required Panasonic printer files.
3. Add the Ghostscript compatibility symlink required by the old GDI filter.
4. Create the CUPS queue and configure A4/automatic scaling.
5. Install the Panasonic SANE backend.
6. Add a persistent udev rule for scanner access.
7. Build and install AirSane.
8. Enable CUPS, Avahi and AirSane services.

## Diagnostics

```bash
sudo ./scripts/doctor.sh
```

Manual checks:

```bash
lpstat -t
sudo -u saned scanimage -L
systemctl status cups avahi-daemon airsaned
avahi-browse -rt _ipp._tcp
avahi-browse -rt _uscan._tcp
```

AirSane web interface:

```text
http://SERVER_IP:8090/
```

## Client setup

### macOS

The printer should appear automatically as AirPrint. The scanner should appear in Image Capture.

### Windows

Add the printer as an IPP/network printer. The scanner should appear in Windows Scan on current Windows 10/11 systems.

### iPhone/iPad

AirPrint works for printing. The built-in “Scan Documents” command uses the camera, not a network scanner. Third-party eSCL app compatibility varies.

## Why the compatibility fixes are needed

The official printer filter searches for `libgs.so` in legacy paths such as `/usr/local/lib`. Ubuntu 24.04 stores Ghostscript in a multiarch directory. The installer creates a compatibility symlink.

The official scanner backend uses the legacy `libusb-0.1.so.4` ABI. Ubuntu 24.04 still provides it in the `libusb-0.1-4` compatibility package.

## Uninstall

```bash
sudo ./uninstall.sh
```

The script removes files and queues installed by this project. It intentionally leaves the compiled AirSane installation in place to avoid removing files that may be used by other scanners.

## Security notes

- CUPS and AirSane are intended for a trusted home LAN.
- AirSane does not provide authentication or encrypted transport.
- Do not expose ports 631 or 8090 directly to the public internet.

## License

The scripts and documentation in this repository are MIT licensed. Panasonic drivers remain subject to Panasonic's own license and are not redistributed here. AirSane is a separate GPL-licensed project.
