# Ricoh SP 210 / SP 211 on a Raspberry Pi (CUPS print server)

Ricoh's Linux driver for the SP 210/211 (`rastertolilo`) is only available as
x86 binaries, so it does not run on ARM boards like the Raspberry Pi. The
open-source `ricoh-sp100` / `pstoricohddst-gdi` filter does **not** work for
the SP 211 either: the printer accepts the data and silently prints nothing.

This directory makes the official driver work on a Raspberry Pi by running the
x86_64 filter under **qemu-user**, with its libraries in a private sysroot
(`/opt/ricoh-x86`). The system's own packages are not modified.

Tested: Raspberry Pi 4, Raspberry Pi OS Lite 64-bit (Debian 13 "trixie"),
Ricoh SP 211 over USB. Printing works from Linux, Android (Default Print
Service / Mopria) and other devices on the LAN through CUPS/AirPrint.

## Install

On the Pi, with the printer plugged in over USB:

```sh
sudo apt install git
git clone https://github.com/AndiVlad/ricohsp210.git
cd ricohsp210 && git checkout raspberry-pi
sudo ./rpi/install-rpi.sh --queue --mask-colord
```

Options:

| Option | Effect |
|---|---|
| `--queue` | Detect a USB SP 210/211 and create a shared, default CUPS queue |
| `--mask-colord` | Disable `colord`; on a headless Pi it times out and delays every job by ~50 s |
| `--letter` | Use Letter instead of A4 as the default paper size |

Then open `http://<pi-hostname>.local:631` to manage the printer. To print
from other machines on the LAN, just add the printer they discover
automatically.

## The red (!) light / having to press the Start button

Ricoh's filter only writes paper size, tray and paper type into the job header
when these options are passed to it explicitly. CUPS normally does not pass
them, so the printer receives "unknown" values, lights the red **!** LED and
waits until you press the Start/Resume button.

The wrapper (`rastertolilo-wrapper.sh`, installed as
`/usr/lib/cups/filter/rastertolilo`) always prepends
`PageSize=A4 InputSlot=Tray1 MediaType=Plain1`. Options sent by the print job
come after them and still take priority.

## How it works

```
document -> CUPS (gstoraster, 8-bit gray, 600 dpi)
         -> /usr/lib/cups/filter/rastertolilo   (wrapper, adds defaults)
         -> qemu-x86_64 -L /opt/ricoh-x86 rastertolilo  (Ricoh's filter)
         -> usb backend -> printer
```

`install-rpi.sh` downloads the amd64 runtime libraries (`libc6`, `libstdc++6`,
`libcups2t64`, `libcupsimage2t64` and their dependencies) with
`apt-get download`, extracts them into `/opt/ricoh-x86` and removes the
temporary amd64 architecture from dpkg again. Installing them via multiarch
does not work on Raspberry Pi OS, because its patched `libc6` conflicts with
Debian's `libc6:amd64`.

## Troubleshooting

* Enable debug logs: `sudo cupsctl --debug-logging`, print, then
  `sudo grep -a 'Job' /var/log/cups/error_log | tail -50`.
* `lpstat -t` shows queue state; `lpinfo -v` should list
  `usb://RICOH/SP%20211?serial=...`.
* Check the filter runs:
  `qemu-x86_64 -L /opt/ricoh-x86 /opt/ricoh-x86/rastertolilo` should print
  `Welcome to GDI filter process!`.
