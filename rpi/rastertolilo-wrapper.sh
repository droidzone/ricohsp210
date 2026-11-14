#!/bin/sh
# CUPS filter wrapper: runs Ricoh's official x86_64 SP 210/211 filter
# (rastertolilo) under qemu-user on ARM boards such as the Raspberry Pi.
#
# Installed as /usr/lib/cups/filter/rastertolilo by install-rpi.sh.
#
# Ricoh's filter only writes paper size / tray / paper type into the job
# header when these options are passed explicitly. CUPS normally does not pass
# them, so the printer gets "unknown" values, lights the red (!) LED and waits
# for the Start/Resume button. We prepend sane defaults; options coming from
# the job are appended after them and therefore take priority.
#
# CUPS filter arguments: job user title copies options [file]

R=/opt/ricoh-x86
DEFAULTS="${RICOH_DEFAULT_OPTIONS:-PageSize=A4 InputSlot=Tray1 MediaType=Plain1}"
OPTS="$DEFAULTS $5"
QEMU="/usr/bin/qemu-x86_64 -L $R -E LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu"

if [ $# -ge 6 ]; then
  exec $QEMU $R/rastertolilo "$1" "$2" "$3" "$4" "$OPTS" "$6"
else
  exec $QEMU $R/rastertolilo "$1" "$2" "$3" "$4" "$OPTS"
fi
