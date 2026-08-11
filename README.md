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
- Internet access for automatic driver download, or local copies of the
  official Panasonic Linux printer/scanner archives

The Panasonic archives are proprietary and are not included in this repository.
The installer can download them directly from Panasonic after asking the user.

## Install

Interactive installation:

```bash
chmod +x install.sh uninstall.sh scripts/*.sh
sudo ./install.sh
```

The installer asks whether to download the official Panasonic drivers or use
local archives.

Non-interactive download:

```bash
sudo ./install.sh --download-drivers
```

Local archives:

```bash
sudo ./install.sh \
  --printer-driver ~/drivers/mccgdi-2.0.10-x86_64.tar.gz \
  --scanner-driver ~/drivers/panamfs-scan-1.3.1-x86_64.tar.gz
```

The Panasonic download server/CDN can stall after roughly 16 KiB on some
networks. The installer first attempts a normal download and automatically
falls back to HTTP Range requests in 16 KiB chunks if necessary.

The installer tests **local printing before enabling network sharing**. If the
Panasonic GDI filter fails, installation stops before publishing the printer.

After installation, perform the requested full reboot before final client tests.

## macOS: important AirPrint setup

On some macOS versions, adding the discovered printer directly from
**System Settings -> Printers & Scanners** creates it as:

```text
Generic PostScript Printer
```

With this legacy Panasonic GDI printer, that client queue can produce a page
printed at a very small scale in the upper-left corner.

### Recommended macOS setup

1. Open any PDF in Preview.
2. Choose **File -> Print**.
3. Open the printer list.
4. Select the discovered Panasonic network printer (not an already-created
   Generic PostScript queue).
5. Let macOS add the discovered AirPrint printer.
6. Open **System Settings -> Printers & Scanners**.
7. Verify that its type is similar to:

```text
Panasonic KX-MB1500series GDI-AirPrint
```

and **not**:

```text
Generic PostScript Printer
```

If a Generic PostScript queue was already created, remove that queue and add
it again through the print dialog as described above.

A CUPS-generated Bonjour URI such as the following is normal:

```text
dnssd://..._ipps._tcp.local./?uuid=...
```

Do not treat `_ipps._tcp` as an error and do not replace the CUPS record with a
hand-written Avahi `_ipp._tcp` service.

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

The project uses Panasonic's original `L_H0JDGCZAZ` CUPS filter directly. It
does not install a PostScript normalization wrapper.

### Panasonic scanner / libusb

The `panamfs` backend needs the legacy ABI package:

```text
libusb-0.1-4
```

The scanner is exposed to the `saned` service user through a udev rule for USB
ID `04da:0f0b`.

## AirSane

AirSane is built from its upstream Git repository. You may select a ref:

```bash
sudo ./install.sh ... --airsane-ref <tag-or-commit>
```

For a reproducible public release, pin this to a tested AirSane tag/commit
after clean-VM validation.

## Troubleshooting: tiny page in upper-left corner on macOS

First check the **Type** shown for the printer in macOS. If it says
`Generic PostScript Printer`, this is a client-side queue selection issue, not
a reason to replace the Panasonic server filter. Remove the Generic PostScript
queue and add the discovered printer through Preview's print dialog so macOS
creates the AirPrint queue.

## Status

Release candidate. Validate once more on a clean Ubuntu Server 24.04 VM before
publishing as stable.
