#!/bin/bash
# Build patched sftp-server for Termux proot-distro (Debian arm64)
# Patch: platform_disable_tracing(1) -> platform_disable_tracing(0)
# to allow sftp to work inside Termux/proot environments

set -e

OPENSSH_VERSION="9.9p2"
OPENSSH_TARBALL="openssh-${OPENSSH_VERSION}.tar.gz"
OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${OPENSSH_TARBALL}"
BUILD_DIR="$HOME/openssh-build"

echo "=== Install build dependencies ==="
apt-get update -qq
apt-get install -y \
    build-essential wget \
    libssl-dev zlib1g-dev \
    libpam0g-dev libselinux1-dev \
    2>/dev/null || true

echo "=== Download OpenSSH ${OPENSSH_VERSION} ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "$OPENSSH_TARBALL" ]; then
    wget -q "$OPENSSH_URL" -O "$OPENSSH_TARBALL"
fi

echo "=== Extract ==="
tar xzf "$OPENSSH_TARBALL"
cd "openssh-${OPENSSH_VERSION}"

echo "=== Apply patch: platform_disable_tracing(1) -> platform_disable_tracing(0) ==="
if grep -q 'platform_disable_tracing(1)' sftp-server.c; then
    sed -i 's/platform_disable_tracing(1)/platform_disable_tracing(0)/' sftp-server.c
    echo "Patch applied successfully."
    grep -n 'platform_disable_tracing' sftp-server.c
else
    echo "WARNING: pattern not found in sftp-server.c, checking what's there..."
    grep -n 'platform_disable_tracing\|disable_tracing' sftp-server.c || true
    # Try patching anyway (some versions use different arg)
    sed -i 's/platform_disable_tracing([^)]*)/platform_disable_tracing(0)/' sftp-server.c
fi

echo "=== Configure ==="
./configure \
    --prefix=/usr \
    --sysconfdir=/etc/ssh \
    --with-ssl-dir=/usr \
    --with-pam \
    --disable-strip \
    2>&1 | tail -5

echo "=== Build sftp-server only ==="
make sftp-server 2>&1 | tail -10

echo ""
echo "=== Build complete! ==="
SFTP_BIN="$(pwd)/sftp-server"
echo "Binary: $SFTP_BIN"
ls -lh "$SFTP_BIN"
file "$SFTP_BIN"

echo ""
echo "=== Install ==="
echo "Copy to standard location:"
echo "  cp $SFTP_BIN /usr/lib/openssh/sftp-server"
echo ""
echo "Or update sshd_config to point to custom path:"
echo "  Subsystem sftp $SFTP_BIN"
echo ""

read -p "Auto-install to /usr/lib/openssh/sftp-server? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    cp "$SFTP_BIN" /usr/lib/openssh/sftp-server
    echo "Installed."
    ls -lh /usr/lib/openssh/sftp-server
fi

echo ""
echo "=== Verify sshd_config Subsystem line ==="
grep -i 'subsystem.*sftp' /etc/ssh/sshd_config 2>/dev/null || echo "(no sshd_config found yet)"