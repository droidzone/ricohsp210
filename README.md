# ricohsp210
Linux drivers for Ricoh SP210
============================

These are official drivers for Ricoh SP210 printer that have not been openly released by Ricoh, but has been provided to partners. These should work on Ubuntu 16.10+.

Install with:

sudo dpkg -i SP-210211-series-Printer-0.03.deb

Raspberry Pi / ARM (CUPS print server)
--------------------------------------

The `.deb` above only contains x86 binaries, so it does not work on a
Raspberry Pi. The [`rpi/`](rpi/) directory runs the same official filter under
qemu-user and also fixes the red (!) light / "press Start to print" problem:

    sudo ./rpi/install-rpi.sh --queue --mask-colord

See [rpi/README.md](rpi/README.md) for details. Tested with a Ricoh SP 211 on a
Raspberry Pi 4 running Raspberry Pi OS Lite 64-bit (Debian 13).
