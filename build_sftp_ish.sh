#!/bin/bash
# Build patched sftp-server for iSH (Alpine Linux x86/i386)
#
# iSH emulates x86 (i386) on iOS/iPadOS.
# We need a STATIC i386 binary that runs on Alpine musl libc.
#
# Run this script on:
#   - x86_64 Linux (native cross-compile, recommended)
#   - arm64 Linux / macOS (needs multilib or Docker)
#   - OR run directly inside iSH itself (slowest but simplest)
#
# Patch: platform_disable_tracing(1) -> platform_disable_tracing(0)
# This prevents sftp-server from calling prctl(PR_SET_DUMPABLE,0)
# which iSH does not implement, causing sftp-server to crash with
# exit status 255.

set -e

OPENSSH_VERSION="9.9p2"
OPENSSH_TARBALL="openssh-${OPENSSH_VERSION}.tar.gz"
OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${OPENSSH_TARBALL}"
BUILD_DIR="$HOME/openssh-ish-build"

# ── Detect build environment ──────────────────────────────────────────────────

ARCH=$(uname -m)
IS_ISH=false
if [ -f /etc/alpine-release ] && [ "$ARCH" = "i686" -o "$ARCH" = "i386" ]; then
    IS_ISH=true
fi

echo "=== Build environment: $(uname -a) ==="
echo "=== Target: i386 static (for iSH / Alpine x86) ==="
echo ""

# ── Install dependencies ───────────────────────────────────────────────────────

if $IS_ISH; then
    echo "=== Running inside iSH — native build ==="
    echo "=== Install dependencies (Alpine) ==="
    apk add --no-cache build-base openssl-dev openssl-libs-static \
        zlib-dev zlib-static linux-headers wget

    CFLAGS="-static"
    LDFLAGS="-static"
    CC="gcc"
    HOST_TRIPLE=""

elif [ -f /etc/alpine-release ]; then
    echo "=== Alpine x86_64 — cross to i386 ==="
    apk add --no-cache build-base gcc-multilib openssl-dev openssl-libs-static \
        zlib-dev zlib-static linux-headers wget
    CFLAGS="-m32 -static"
    LDFLAGS="-m32 -static"
    CC="gcc"
    HOST_TRIPLE="--host=i686-linux-musl"

elif command -v apt-get &>/dev/null; then
    echo "=== Debian/Ubuntu — install i386 cross toolchain ==="
    apt-get update -qq
    dpkg --add-architecture i386 2>/dev/null || true
    apt-get install -y \
        build-essential gcc-multilib \
        libssl-dev libssl-dev:i386 \
        zlib1g-dev zlib1g-dev:i386 \
        wget 2>/dev/null || \
    apt-get install -y build-essential gcc-multilib wget \
        libssl-dev zlib1g-dev
    CFLAGS="-m32 -static"
    LDFLAGS="-m32 -static"
    CC="gcc"
    HOST_TRIPLE="--host=i686-linux-gnu"

else
    echo "ERROR: Unsupported host. Run inside iSH directly, or use Alpine/Debian."
    echo ""
    echo "Alternatively, build inside iSH with:"
    echo "  apk add build-base openssl-dev openssl-libs-static zlib-dev zlib-static wget"
    echo "  bash build_sftp_ish.sh"
    exit 1
fi

# ── Download & extract ─────────────────────────────────────────────────────────

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f "$OPENSSH_TARBALL" ]; then
    echo "=== Download OpenSSH ${OPENSSH_VERSION} ==="
    wget -q --show-progress "$OPENSSH_URL" -O "$OPENSSH_TARBALL"
fi

echo "=== Extract ==="
rm -rf "openssh-${OPENSSH_VERSION}"
tar xzf "$OPENSSH_TARBALL"
cd "openssh-${OPENSSH_VERSION}"

# ── Apply patch ────────────────────────────────────────────────────────────────

echo "=== Apply patch: platform_disable_tracing(1) -> platform_disable_tracing(0) ==="
if grep -q 'platform_disable_tracing(1)' sftp-server.c; then
    sed -i 's/platform_disable_tracing(1)/platform_disable_tracing(0)/' sftp-server.c
    echo "Patch applied:"
    grep -n 'platform_disable_tracing' sftp-server.c
else
    echo "Pattern not found — trying generic patch..."
    sed -i 's/platform_disable_tracing([^)]*)/platform_disable_tracing(0)/g' sftp-server.c
    grep -n 'platform_disable_tracing' sftp-server.c || echo "(no match found, may already be 0)"
fi

# ── Configure ──────────────────────────────────────────────────────────────────

echo "=== Configure (static i386) ==="

# On Alpine/musl, --without-shadow avoids shadow.h issues
# --without-pam avoids PAM library dependency
# --without-selinux and --without-audit for minimal static build
./configure \
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    $HOST_TRIPLE \
    --prefix=/usr \
    --sysconfdir=/etc/ssh \
    --without-pam \
    --without-selinux \
    --without-audit \
    --without-shadow \
    --with-ssl-dir=/usr \
    --disable-strip \
    2>&1 | grep -E '(checking|error|warning|configure:)' | tail -20

echo ""

# ── Build ──────────────────────────────────────────────────────────────────────

echo "=== Build sftp-server ==="
make sftp-server 2>&1 | tail -15

# ── Verify ────────────────────────────────────────────────────────────────────

SFTP_BIN="$(pwd)/sftp-server"
echo ""
echo "=== Build complete! ==="
ls -lh "$SFTP_BIN"
file "$SFTP_BIN"

# Check it's actually static
if file "$SFTP_BIN" | grep -q "statically linked"; then
    echo "✓ Statically linked"
else
    echo "⚠ NOT statically linked — may not work in iSH without libs"
fi

# Check architecture
if file "$SFTP_BIN" | grep -qE "80386|i386|32-bit"; then
    echo "✓ i386/x86 binary"
else
    echo "⚠ Architecture may not be i386 — check output above"
fi

# ── Install instructions ───────────────────────────────────────────────────────

echo ""
echo "=== iSH install instructions ==="
echo ""
echo "1. Transfer sftp-server to iSH (e.g. via SSH/SCP):"
echo "   scp $SFTP_BIN root@<ish-ip>:/usr/local/bin/sftp-server"
echo ""
echo "2. Inside iSH:"
echo "   chmod +x /usr/local/bin/sftp-server"
echo ""
echo "3. Edit /etc/ssh/sshd_config inside iSH:"
echo "   Subsystem sftp /usr/local/bin/sftp-server"
echo ""
echo "4. Restart sshd inside iSH:"
echo "   kill \$(cat /var/run/sshd.pid) && /usr/sbin/sshd"
echo ""

# ── Optional: copy to output dir if in container/Claude environment ───────────
if [ -d /mnt/user-data/outputs ]; then
    cp "$SFTP_BIN" /mnt/user-data/outputs/sftp-server-ish
    echo "Binary also copied to /mnt/user-data/outputs/sftp-server-ish"
fi