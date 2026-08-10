# Panasonic KX-MB1500 MFP Bridge

Turn a USB-only Panasonic KX-MB1500/KX-MB1500RU into a network printer and
scanner using Ubuntu Server 24.04 x86_64.

## Architecture

Printing:

`macOS / Windows -> CUPS DNS-SD (IPP/IPPS) -> Panasonic GDI filter -> USB`

Scanning:

`macOS / Windows -> eSCL/AirScan -> AirSane -> SANE panamfs -> USB`

The project intentionally **does not** create a custom Avahi printer service.
CUPS publishes the real queue itself, including its UUID and capabilities.

## Requirements

- Ubuntu Server 24.04 x86_64
- Panasonic KX-MB1500 visible inside the VM as USB `04da:0f0b`
- Official Panasonic Linux printer archive:
  `mccgdi-2.0.10-x86_64...`
- Official Panasonic Linux scanner archive:
  `panamfs-scan-1.3.1-x86_64...`

The Panasonic archives are proprietary and are not included.

## Install

```bash
chmod +x install.sh uninstall.sh scripts/*.sh

sudo ./install.sh \
  --printer-driver ~/drivers/mccgdi-2.0.10-x86_64.tar.tar \
  --scanner-driver ~/drivers/panamfs-scan-1.3.1-x86_64.tar.tar
```

The installer deliberately tests **local printing before enabling network
sharing**. If the Panasonic GDI filter fails, the installer stops there.

## Important macOS note

A discovered CUPS queue can legitimately appear as:

```text
dnssd://..._ipps._tcp.local./?uuid=...
```

Do not treat `_ipps._tcp` as an error and do not replace the CUPS record with a
hand-written `_ipp._tcp` Avahi service.

## Manual checks

```bash
sudo ./scripts/test-printer.sh Panasonic_KX_MB1500
sudo ./scripts/test-scanner.sh
sudo ./scripts/doctor.sh Panasonic_KX_MB1500
```

Printer discovery:

```bash
avahi-browse -rt _ipp._tcp
avahi-browse -rt _ipps._tcp
```

Scanner discovery:

```bash
avahi-browse -rt _uscan._tcp
```

## Known compatibility fixes

### Panasonic GDI / Ghostscript

The legacy filter searches old fixed locations for `libgs.so`. The installer
creates:

```text
/usr/local/lib/libgs.so -> current Ubuntu libgs.so
```

### Panasonic scanner / libusb

The `panamfs` backend needs the legacy ABI package:

```text
libusb-0.1-4
```

The scanner is exposed to the `saned` service user through a udev rule for
USB ID `04da:0f0b`.

## AirSane

AirSane is built from the upstream Git repository. You may select a ref:

```bash
sudo ./install.sh ... --airsane-ref <tag-or-commit>
```

For a reproducible public release, pin this to a tested AirSane tag/commit
after clean-VM validation.

## Status

This is a clean-install release candidate. Test it on a disposable VM/snapshot
before publishing it as a stable release.
