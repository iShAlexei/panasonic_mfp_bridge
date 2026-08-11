# Clean VM validation checklist

Use a new Ubuntu Server 24.04 x86_64 VM and pass the complete Panasonic USB
device (`04da:0f0b`) through from Proxmox.

Before installation:

```bash
lsusb
sudo lsusb -v -d 04da:0f0b
```

Expected interfaces include both:

- Imaging / Still Image Capture
- Printer

Run the installer. Stop and investigate if the local printer smoke test fails.

After installation verify:

```bash
lpstat -t
lpoptions -p Panasonic_KX_MB1500
sudo -u saned scanimage -L
systemctl status airsaned --no-pager
avahi-browse -rt _ipp._tcp
avahi-browse -rt _ipps._tcp
avahi-browse -rt _uscan._tcp
```

Then test, in this order:

1. Local CUPS test print.
2. macOS Bonjour/AirPrint print.
3. Windows IPP print.
4. macOS Image Capture scan.
5. Windows Scan scan.

Record the exact macOS `lpstat -v` URI. A CUPS-generated `_ipps._tcp` URI
containing `?uuid=...` is expected and valid.

## macOS queue verification

When testing macOS, verify the installed client queue type. The successful
baseline is `Panasonic KX-MB1500series GDI-AirPrint` (or an AirPrint queue), not
`Generic PostScript Printer`. If System Settings creates the Generic PostScript
queue, remove it and add the discovered printer from Preview -> File -> Print.
