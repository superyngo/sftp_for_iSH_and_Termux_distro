# patched-sftp-server

> Build a patched `sftp-server` binary for restricted environments (iSH / Termux proot-distro)

[中文版請見下方 ↓](#中文)

---

## Background

[iSH](https://ish.app/) (iOS) and [Termux](https://termux.dev/) proot-distro (Android) are popular Linux shell environments on mobile devices. Both allow running an OpenSSH `sshd` daemon, enabling remote access via SSH. However, **SFTP does not work out of the box** in these environments.

### Root Cause

When an SFTP session is established, `sshd` spawns `sftp-server`. Near startup, `sftp-server` calls:

```c
platform_disable_tracing(1);  /* strict */
```

This function calls `prctl(PR_SET_DUMPABLE, 0)` under the hood to prevent `/proc/self/mem` from being accessible — a security hardening measure. On a normal Linux kernel this is harmless, but iSH and Termux proot environments do not fully implement this `prctl` call, causing `sftp-server` to exit immediately with status `255`.

The client sees the connection drop right after authentication, with no useful error message.

### Fix

Change the argument from `1` (strict) to `0` (disabled) in `sftp-server.c`:

```c
/* before */
platform_disable_tracing(1);

/* after */
platform_disable_tracing(0);
```

Then rebuild `sftp-server` and replace the default binary. SSH itself is unaffected.

---

## Targets

| Binary | Architecture | libc | For |
|--------|-------------|------|-----|
| `sftp-server-arm64-static` | aarch64 | musl (static) | Termux proot-distro (Debian/Ubuntu on Android) |
| `sftp-server-i386-static` | i686 | musl (static) | iSH (Alpine x86 on iOS/iPadOS) |

Both binaries are **statically linked** — no dependency on the host shared libraries.

---

## Usage

### GitHub Actions (Recommended)

The included workflow builds both binaries in the cloud without needing to compile on-device.

1. Fork or clone this repo
2. Go to **Actions → Build patched sftp-server → Run workflow**
3. Enter the desired OpenSSH version (default: `9.9p2`)
4. Download artifacts when the run completes:
   - `sftp-server-arm64-static` for Termux
   - `sftp-server-i386-static` for iSH

### For Termux (Android, arm64)

```sh
# Transfer the binary to your device (e.g. via scp or adb)
# Then inside proot-distro Debian:
cp sftp-server-arm64-static /usr/local/bin/sftp-server
chmod +x /usr/local/bin/sftp-server

# Edit sshd_config
echo 'Subsystem sftp /usr/local/bin/sftp-server' >> /etc/ssh/sshd_config

# Restart sshd
pkill sshd; /usr/sbin/sshd
```

### For iSH (iOS/iPadOS, i386)

```sh
# Transfer the binary into iSH (e.g. via SSH/SCP from another machine)
cp sftp-server-i386-static /usr/local/bin/sftp-server
chmod +x /usr/local/bin/sftp-server

# Edit sshd_config
vi /etc/ssh/sshd_config
# Change or add:
#   Subsystem sftp /usr/local/bin/sftp-server

# Restart sshd (close and reopen iSH, or:)
kill $(cat /var/run/sshd.pid) && /usr/sbin/sshd
```

### Build Locally

```sh
chmod +x build_sftp_server.sh   # Termux arm64
chmod +x build_sftp_ish.sh      # iSH i386
bash build_sftp_server.sh
```

> **Note:** Running `./configure` inside proot or iSH is slow due to emulation/proot overhead. Each of the hundreds of feature-detection test compilations incurs additional fork/exec cost. Using the GitHub Actions workflow is strongly recommended.

---

## Files

| File | Description |
|------|-------------|
| `.github/workflows/build-sftp-server.yml` | CI workflow (builds arm64 + i386 static binaries) |
| `build_sftp_server.sh` | Local build script for Termux proot-distro (arm64) |
| `build_sftp_ish.sh` | Local build script for iSH (i386) |

---

## References

- [iSH issue #2075 — ssh does work, but sftp not working](https://github.com/ish-app/ish/issues/2075)
- [OpenSSH Portable source](https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
- [iSH App](https://ish.app/)
- [Termux](https://termux.dev/)
- [proot-distro](https://github.com/termux/proot-distro)
- [`prctl(2)` — Linux man page](https://man7.org/linux/man-pages/man2/prctl.2.html)
- [musl.cc cross-compilation toolchains](https://musl.cc/)

---

## License

Build scripts are released under the MIT License. OpenSSH is distributed under its own [BSD-style license](https://www.openssh.com/portable.html).

---
---

<a name="中文"></a>

# patched-sftp-server（中文）

> 為受限環境（iSH / Termux proot-distro）編譯修補版 `sftp-server` binary

---

## 背景

[iSH](https://ish.app/)（iOS）與 [Termux](https://termux.dev/) proot-distro（Android）是手機上常用的 Linux shell 環境，兩者都能執行 OpenSSH `sshd` daemon，支援遠端 SSH 連線。但在這些環境中，**SFTP 預設無法正常運作**。

### 根本原因

建立 SFTP 連線時，`sshd` 會啟動 `sftp-server` 子程序。在啟動初期，`sftp-server` 會呼叫：

```c
platform_disable_tracing(1);  /* strict */
```

這個函式底層呼叫 `prctl(PR_SET_DUMPABLE, 0)`，目的是防止 `/proc/self/mem` 被存取（安全強化措施）。在正常 Linux kernel 上這不會有問題，但 iSH 與 Termux proot 環境並未完整實作這個 `prctl` 呼叫，導致 `sftp-server` 在啟動後立即以 exit status `255` 結束。

客戶端的現象是：認證成功後連線立刻斷開，且沒有任何有用的錯誤訊息。

### 修復方式

將 `sftp-server.c` 中的參數從 `1`（strict）改為 `0`（disabled）：

```c
/* 修改前 */
platform_disable_tracing(1);

/* 修改後 */
platform_disable_tracing(0);
```

重新編譯 `sftp-server` 並替換預設的 binary 即可。SSH 本身不受影響。

---

## 目標平台

| Binary | 架構 | libc | 用途 |
|--------|------|------|------|
| `sftp-server-arm64-static` | aarch64 | musl（靜態） | Termux proot-distro（Android 上的 Debian/Ubuntu） |
| `sftp-server-i386-static` | i686 | musl（靜態） | iSH（iOS/iPadOS 上的 Alpine x86） |

兩個 binary 均為**靜態連結**，不依賴主機的 shared library。

---

## 使用方式

### GitHub Actions（推薦）

內附的 workflow 可在雲端自動編譯兩個平台的 binary，不需要在裝置上本地編譯。

1. Fork 或 clone 這個 repo
2. 前往 **Actions → Build patched sftp-server → Run workflow**
3. 輸入想要的 OpenSSH 版本（預設：`9.9p2`）
4. 執行完成後下載 artifact：
   - `sftp-server-arm64-static`：給 Termux 使用
   - `sftp-server-i386-static`：給 iSH 使用

### Termux 安裝（Android，arm64）

```sh
# 將 binary 傳入裝置（例如透過 scp 或 adb）
# 然後在 proot-distro Debian 內執行：
cp sftp-server-arm64-static /usr/local/bin/sftp-server
chmod +x /usr/local/bin/sftp-server

# 編輯 sshd_config
echo 'Subsystem sftp /usr/local/bin/sftp-server' >> /etc/ssh/sshd_config

# 重啟 sshd
pkill sshd; /usr/sbin/sshd
```

### iSH 安裝（iOS/iPadOS，i386）

```sh
# 將 binary 傳入 iSH（例如從其他機器透過 SSH/SCP）
cp sftp-server-i386-static /usr/local/bin/sftp-server
chmod +x /usr/local/bin/sftp-server

# 編輯 sshd_config
vi /etc/ssh/sshd_config
# 修改或新增：
#   Subsystem sftp /usr/local/bin/sftp-server

# 重啟 sshd（關閉再開啟 iSH，或執行：）
kill $(cat /var/run/sshd.pid) && /usr/sbin/sshd
```

### 本地編譯

```sh
chmod +x build_sftp_server.sh   # Termux arm64
chmod +x build_sftp_ish.sh      # iSH i386
bash build_sftp_server.sh
```

> **注意：** 在 proot 或 iSH 環境內執行 `./configure` 速度很慢。configure 需要進行數百個 feature detection 小編譯，每次都要 fork/exec 一個 gcc 子程序，在模擬/proot 環境下每次呼叫都有額外 overhead，累積起來非常耗時。**強烈建議使用 GitHub Actions workflow**。

---

## 檔案說明

| 檔案 | 說明 |
|------|------|
| `.github/workflows/build-sftp-server.yml` | CI workflow（編譯 arm64 + i386 靜態 binary） |
| `build_sftp_server.sh` | Termux proot-distro（arm64）本地編譯腳本 |
| `build_sftp_ish.sh` | iSH（i386）本地編譯腳本 |

---

## 參考資料

- [iSH issue #2075 — ssh does work, but sftp not working](https://github.com/ish-app/ish/issues/2075)
- [OpenSSH Portable 原始碼下載](https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
- [iSH App 官網](https://ish.app/)
- [Termux 官網](https://termux.dev/)
- [proot-distro](https://github.com/termux/proot-distro)
- [`prctl(2)` — Linux man page](https://man7.org/linux/man-pages/man2/prctl.2.html)
- [musl.cc 跨平台工具鏈](https://musl.cc/)

---

## 授權

Build scripts 以 MIT License 授權。OpenSSH 本身依其 [BSD-style license](https://www.openssh.com/portable.html) 發佈。