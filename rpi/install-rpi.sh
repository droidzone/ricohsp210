#!/bin/sh
# Install the Ricoh SP 210/211 driver on a Raspberry Pi (or any ARM Debian /
# Raspberry Pi OS box) and optionally create a shared CUPS print queue.
#
# Ricoh only ships x86 binaries, so the x86_64 filter runs under qemu-user with
# a private amd64 sysroot in /opt/ricoh-x86. Nothing amd64 is installed into
# the system itself (multiarch libc6 conflicts with Raspberry Pi OS's libc6).
#
# Usage (from the repository root):
#   sudo ./rpi/install-rpi.sh            # install driver only
#   sudo ./rpi/install-rpi.sh --queue    # also add a shared queue for a USB SP 210/211
#   sudo ./rpi/install-rpi.sh --queue --mask-colord
#
# Tested: Raspberry Pi 4, Raspberry Pi OS Lite 64-bit (Debian 13 trixie), SP 211.
set -eu

QUEUE=0
MASK_COLORD=0
PAPER=A4
for a in "$@"; do
  case "$a" in
    --queue) QUEUE=1 ;;
    --mask-colord) MASK_COLORD=1 ;;
    --letter) PAPER=Letter ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
DEB="$REPO/SP-210211-series-Printer-0.03.deb"
DEST=/opt/ricoh-x86
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -f "$DEB" ] || { echo "Missing $DEB" >&2; exit 1; }

echo ">> Installing CUPS, Ghostscript and qemu-user"
APT="apt-get -o DPkg::Lock::Timeout=600"
$APT update -qq
DEBIAN_FRONTEND=noninteractive $APT install -y -qq cups cups-bsd avahi-daemon ghostscript qemu-user binutils >/dev/null

echo ">> Extracting Ricoh driver"
mkdir -p "$WORK/deb"
( cd "$WORK/deb" && ar x "$DEB" && tar xzf data.tar.gz )

echo ">> Downloading amd64 runtime libraries (download only, not installed)"
ADDED_ARCH=0
if ! dpkg --print-foreign-architectures | grep -qx amd64; then
  dpkg --add-architecture amd64
  ADDED_ARCH=1
fi
$APT update -qq || true
mkdir -p "$WORK/debs"
PKGS=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances \
        libcups2t64:amd64 libcupsimage2t64:amd64 libstdc++6:amd64 libgcc-s1:amd64 libc6:amd64 \
      | grep -E '^[a-z0-9].*:amd64$' | sort -u)
( cd "$WORK/debs" && chown _apt "$WORK/debs" 2>/dev/null; apt-get download $PKGS >/dev/null )
if [ "$ADDED_ARCH" = 1 ]; then
  dpkg --remove-architecture amd64
  $APT update -qq || true
fi

echo ">> Building sysroot in $DEST"
rm -rf "$DEST.new"
mkdir -p "$DEST.new"
for d in "$WORK"/debs/*.deb; do dpkg-deb -x "$d" "$DEST.new"; done
ln -sfn usr/lib64 "$DEST.new/lib64"
ln -sfn usr/lib "$DEST.new/lib"
install -m 755 "$WORK/deb/tmp/x86_64/rastertolilo" "$DEST.new/rastertolilo"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old.$(date +%s)"
mv "$DEST.new" "$DEST"
chown -R root:root "$DEST"

echo ">> Installing CUPS filter wrapper and PPDs"
sed "s/PageSize=A4/PageSize=$PAPER/" "$HERE/rastertolilo-wrapper.sh" > /usr/lib/cups/filter/rastertolilo
chmod 755 /usr/lib/cups/filter/rastertolilo
mkdir -p /usr/share/cups/model/ricoh
install -m 644 "$WORK"/deb/usr/share/cups/model/ricoh/RICOH-SP-21*.ppd /usr/share/cups/model/ricoh/

echo ">> Self-test: running the filter under qemu"
# Without input the Ricoh filter prints its banner and then crashes; that is
# expected, we only check that it starts under qemu.
SELFTEST=$(sh -c "/usr/bin/qemu-x86_64 -L '$DEST' -E LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu \
     '$DEST/rastertolilo' 1 test test 1 '' </dev/null >/dev/null" 2>&1 || true)
if echo "$SELFTEST" | grep -q "GDI filter"; then
  echo "   OK"
else
  echo "   WARNING: filter did not start under qemu" >&2
fi

if [ "$MASK_COLORD" = 1 ]; then
  echo ">> Masking colord (it can delay every job by ~50 s on headless systems)"
  systemctl mask colord >/dev/null 2>&1 || true
fi

if [ "$QUEUE" = 1 ]; then
  echo ">> Looking for a USB Ricoh SP 210/211"
  URI=$(lpinfo -v 2>/dev/null | awk '/usb:\/\/RICOH\/SP%2021[01]/ {print $2; exit}')
  if [ -z "$URI" ]; then
    echo "   No SP 210/211 found on USB; add the queue later via http://<pi>:631" >&2
  else
    MODEL=$(echo "$URI" | sed -n 's|.*SP%20\(21[01]\).*|\1|p')
    QNAME="Ricoh_SP$MODEL"
    lpadmin -p "$QNAME" -D "Ricoh SP $MODEL" -v "$URI" \
      -m "ricoh/RICOH-SP-$MODEL.ppd" \
      -o printer-is-shared=true -o PageSize=$PAPER -o MediaType=Plain1 -E
    lpadmin -d "$QNAME"
    cupsctl --share-printers --remote-any
    echo "   Queue $QNAME created and shared ($URI)"
  fi
fi

echo ">> Done."
