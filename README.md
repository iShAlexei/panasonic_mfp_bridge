# Panasonic USB MFP Network Bridge

Use a compatible USB-only Panasonic KX-MB series multifunction device as a
network printer and scanner through a small Ubuntu Server 24.04 x86_64 machine
or VM. The official Panasonic driver packages used by this project support
multiple models in the series; verify that your model is listed by Panasonic
before installation.

The bridge keeps Panasonic's original Linux GDI printer filter and `panamfs`
SANE backend on the server. Clients use standard network protocols and do not
need the legacy Panasonic driver:

```text
Printing:
macOS / Windows -> IPP/AirPrint -> CUPS -> Panasonic GDI filter -> USB

Scanning:
macOS / Windows -> eSCL/AirScan -> AirSane -> SANE panamfs -> USB
```

## What the installer configures

- the official Panasonic x86_64 printer and scanner drivers;
- a local CUPS queue using Panasonic's `L_H0JDGCZAZ` GDI filter;
- A4 as the server queue default;
- the compatibility link required by the old filter to find modern
  Ghostscript;
- CUPS printer sharing and its native DNS-SD/Bonjour publication;
- USB permissions for the `saned` account;
- AirSane, built from its upstream Git repository, for eSCL/AirScan;
- diagnostic scripts and persistent installation logs;
- automatic disabling of `cups-browsed` to prevent unwanted
  `implicitclass` queues on the bridge server.

The project deliberately does **not** install a custom Avahi printer service or
a PostScript normalization wrapper. CUPS publishes the real printer queue,
UUID, formats and capabilities itself.

## Requirements

- Ubuntu Server 24.04 on x86_64;
- root access through `sudo`;
- a compatible Panasonic multifunction device connected to the server and
  visible in `lsusb`;
- the bridge and client devices on the same local network/VLAN, with multicast
  DNS and the required CUPS/AirSane traffic allowed;
- Internet access during installation, or local copies of both official
  Panasonic driver archives.

The installer rejects non-x86_64 systems because the supplied Panasonic
drivers are x86_64 binaries. Ubuntu versions other than 24.04 produce a warning
and have not been validated by this project.

## Potentially compatible Panasonic models

The bridge downloads Panasonic's official `mccgdi 2.0.10` printer driver and
`panamfs 1.3.1` scanner driver. Panasonic lists the following device families
for **both** packages:

- KX-MC6000 series
- DP-MC210 series
- KX-MB3000 series
- DP-MB300 series
- KX-MB2000 series
- KX-MB2060 series
- KX-MB1500 series
- KX-MB2200 series
- KX-MB2500 series
- DP-MB250 series
- DP-MB310 series
- KX-MB2090 series
- KX-MB1600 series
- KX-MB2100 series
- KX-MB2571 series
- DP-MB251 series
- DP-MB311 series
- DP-MB500 series

Sources: Panasonic's official
[`mccgdi 2.0.10` printer-driver guide](https://www.psn-web.net/cs/support/fax/common/file/Linux_PrnDriver/Driver_Install_files/Ubuntu_ENG_010.pdf)
and
[`panamfs 1.3.1` scanner-driver guide](https://www.psn-web.net/cs/support/fax/common/file/Linux_ScanDriver/ScannerDriver_Ubuntu_ENG_011.pdf).

This is an **upstream driver compatibility list**, not a claim that every model
works with the repository unchanged. The complete CUPS -> AirPrint and SANE ->
AirSane bridge has so far been validated only with the original test device.
For another model, check that the downloaded archives contain its PPD/backend,
then adapt and test the model-specific USB ID, CUPS device URI, PPD path, queue
description, scanner detection and udev rule. Panasonic's original documents
name older Ubuntu releases; compatibility with Ubuntu Server 24.04 comes from
this project's additional fixes and must be verified per model.

### VM and Proxmox preparation

Pass the **complete USB device**, not only one USB interface, through to the
Ubuntu VM. Find its USB vendor and product ID before running the installer:

```bash
lsusb | grep -i panasonic
```

The output contains an identifier in `VENDOR_ID:PRODUCT_ID` form. Use the ID
reported for your own device wherever USB passthrough or a model-specific
configuration requires it. If no Panasonic device is shown, fix USB
passthrough first.

> **Current script defaults:** the repository was initially validated with a
> KX-MB1500-series device. Some scripts still use that model's queue, driver
> paths, USB identification and display names as defaults. Supporting another
> model may require updating those model-specific values before running the
> installer; detecting a Panasonic device in `lsusb` alone does not guarantee
> that the unmodified scripts support it.

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/iShAlexei/panasonic_mfp_bridge.git
cd panasonic_mfp_bridge
chmod +x install.sh uninstall.sh scripts/*.sh
sudo ./install.sh
```

With no driver options, the installer interactively asks whether to download
the drivers or use local archives.

### Automatic driver download

```bash
sudo ./install.sh --download-drivers
```

The proprietary archives are downloaded from Panasonic and cached under:

```text
/var/lib/panasonic-mfp-bridge/drivers/
```

Panasonic's CDN can stall after approximately 16 KiB on some network paths.
The installer detects an incomplete or stalled normal transfer and retries it
with validated HTTP Range requests in 16 KiB chunks.

### Local driver archives

```bash
sudo ./install.sh \
  --printer-driver /path/to/mccgdi-2.0.10-x86_64.tar.gz \
  --scanner-driver /path/to/panamfs-scan-1.3.1-x86_64.tar.gz
```

Both archives must be supplied together. Panasonic owns these proprietary
drivers, so they are intentionally not included in this repository.

### Installer options

```text
--download-drivers       Download both drivers from Panasonic
--printer-driver PATH    Use a local printer-driver archive
--scanner-driver PATH    Use a local scanner-driver archive
--queue-name NAME        CUPS queue name (default: Panasonic_KX_MB1500)
--no-airprint            Do not publish the printer through CUPS
--no-airsane             Do not install AirSane/eSCL
--airsane-ref REF        AirSane Git ref, tag or commit (default: master)
-h, --help               Show installer help
```

For a reproducible deployment, pass a tested AirSane tag or commit with
`--airsane-ref` instead of following `master`.

## Installation stages and safety checks

The installer performs six stages:

1. installs Ubuntu dependencies and starts CUPS/Avahi;
2. installs the Panasonic printer driver and creates the local USB queue;
3. submits a local test page;
4. enables CUPS sharing and verifies the `_ipp._tcp` or `_ipps._tcp` record;
5. installs the Panasonic scanner backend and USB permissions;
6. installs and starts AirSane.

Network printer sharing is not enabled until CUPS accepts the local smoke test
without stopping the queue. After that test, the installer waits for CUPS to
settle. AirPrint configuration also retries `lpadmin` up to ten times when CUPS
briefly returns `Service Unavailable`.

Physically confirm that the local test page printed correctly. A successfully
submitted CUPS job cannot prove that paper actually came out of the printer.

When installation finishes, perform the requested full reboot:

```bash
sudo reboot
```

After startup, allow roughly 20–30 seconds for CUPS, Avahi and AirSane before
testing clients.

## Add the printer on macOS

### Important: create an AirPrint queue

On some macOS versions, adding the discovered printer directly from
**System Settings -> Printers & Scanners** creates this incorrect queue type:

```text
Generic PostScript Printer
```

With the legacy Panasonic GDI filter, jobs from that queue may print extremely
small in the upper-left corner of an A4 page.

Use this tested method instead:

1. Open any PDF in Preview.
2. Select **File -> Print**.
3. Open the printer list.
4. Select the discovered Panasonic network printer, not an existing Generic
   PostScript queue.
5. Let macOS create the printer.
6. Open **System Settings -> Printers & Scanners** and inspect its type.

The working queue should appear as AirPrint or similar to:

```text
Panasonic KX-MB1500series GDI-AirPrint
```

It must not be `Generic PostScript Printer`. If the wrong queue already exists,
remove it and repeat the steps through Preview's print dialog.

A Bonjour URI generated by CUPS is expected to look like this:

```text
dnssd://..._ipps._tcp.local./?uuid=...
```

`_ipps._tcp` and the UUID are valid. Do not replace the record with a manually
written Avahi `_ipp._tcp` service.

## Add the printer on Windows

First allow Windows to discover the printer on the local network and add the
IPP/AirPrint device it finds. If automatic discovery is unavailable, use the
CUPS queue URL, replacing the hostname and queue name as needed:

```text
http://SERVER_HOSTNAME:631/printers/Panasonic_KX_MB1500
```

The Panasonic Linux GDI driver stays on the Ubuntu bridge; do not attempt to
install that Linux package on Windows. Print a simple A4 document after adding
the queue.

## Add the scanner

AirSane publishes the scanner through standard eSCL/AirScan discovery. On
macOS, open **Image Capture** and select the discovered Panasonic scanner. On
Windows, open a compatible scanning application such as **Windows Scan** and
select the discovered network scanner.

If discovery fails, verify that the client and bridge are on the same local
network and that multicast DNS is not blocked. Then run the server diagnostics
below.

## Verification and diagnostics

Run the complete diagnostic check after reboot:

```bash
sudo ./scripts/doctor.sh Panasonic_KX_MB1500
```

Exit status `0` means every check passed, `1` means at least one required check
failed, and `2` means only warnings were found.

Individual tests:

```bash
sudo ./scripts/test-printer.sh Panasonic_KX_MB1500
sudo ./scripts/test-scanner.sh
```

The scanner test writes `/tmp/panasonic-scan-test.png` by default. An optional
output path may be supplied as its first argument.

Inspect services and discovery records:

```bash
lpstat -t
sudo -u saned scanimage -L
systemctl status cups avahi-daemon airsaned --no-pager
avahi-browse -rt _ipp._tcp
avahi-browse -rt _ipps._tcp
avahi-browse -rt _uscan._tcp
```

Installation logs are stored at:

```text
/var/log/panasonic-mfp-bridge/install.log
```

The installer also stores its state and file backups under:

```text
/var/lib/panasonic-mfp-bridge/
```

## Compatibility notes

### Panasonic GDI filter and Ghostscript

The legacy filter searches fixed, old locations for `libgs.so`. The installer
locates Ubuntu's current library and creates:

```text
/usr/local/lib/libgs.so -> current Ubuntu libgs.so
```

The original `L_H0JDGCZAZ` CUPS filter remains in the print path. The project
does not add PS-to-PDF or PostScript normalization wrappers; those experiments
addressed the symptom of an incorrect macOS client queue, not the cause.

### Panasonic scanner and libusb

The `panamfs` backend requires the legacy `libusb-0.1-4` ABI package. The
installer also creates a model-specific udev rule, assigns access to the
`scanner` group and adds the `saned` account to that group. For a different
device, the rule must use the `VENDOR_ID` and `PRODUCT_ID` reported by `lsusb`.

## Troubleshooting

### Page prints very small in the upper-left corner on macOS

Check the printer **Type** in macOS. If it is `Generic PostScript Printer`,
remove that client queue and add the discovered printer through Preview's
**File -> Print** dialog. Do not change the server's Panasonic filter.

### `lpadmin: Service Unavailable`

The current installer waits for CUPS after the local print test and retries the
sharing operation. If all retries still fail, inspect:

```bash
systemctl status cups --no-pager
journalctl -u cups -n 100 --no-pager
tail -n 100 /var/log/panasonic-mfp-bridge/install.log
```

### Driver download stalls near 16 KiB

Wait for the automatic Range fallback. It retrieves the archive in 16 KiB
chunks and verifies every returned chunk and the completed tar archive. For a
fully offline installation, download both official archives elsewhere and use
the local-driver options.

### USB device is not found

Confirm the cable, printer power and VM USB passthrough:

```bash
lsusb | grep -i panasonic
```

If needed, first run plain `lsusb` and identify the device by its manufacturer
or model description. For a VM, reconnect or reassign the complete Panasonic
USB device and reboot the guest if necessary.

### Scanner is visible to root but not to AirSane

Check access as the actual service user:

```bash
sudo -u saned scanimage -L
ls -l /dev/bus/usb/*/*
systemctl status airsaned --no-pager
```

Replugging the USB device or rebooting may be necessary immediately after the
udev rule and group membership are installed.

## Uninstall

```bash
sudo ./uninstall.sh
```

This disables AirSane and removes the bridge CUPS queue, its udev rule and the
Ghostscript compatibility link. It intentionally does not promise to remove
every file installed by Panasonic's proprietary installers; use the vendor
`uninstall-driver` scripts if complete driver removal is required.

## Project status

The current configuration is a tested working baseline for Ubuntu Server 24.04
x86_64 and Panasonic KX-MB-series hardware supported by the selected official
driver packages. Models other than the original test device, other
architectures and other Ubuntu releases should be treated as unvalidated until
their model-specific script values and full print/scan path have been tested.

For a clean-VM release checklist, see [`docs/CLEAN-VM-TEST.md`](docs/CLEAN-VM-TEST.md).

## Acknowledgements

This repository was developed and documented with the assistance of
[OpenAI Codex](https://openai.com/codex/), which helped analyze the legacy
Panasonic drivers, diagnose CUPS/AirPrint and AirSane integration issues, and
refine the installation and troubleshooting workflow.
