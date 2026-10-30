# yihack-tng

A stability-focused fork of [roleoroleo/yi-hack-MStar](https://github.com/roleoroleo/yi-hack-MStar) for Yi cameras based on the MStar platform.

The original project is an excellent local-firmware replacement for Yi/MStar cameras. `yihack-tng` keeps that foundation and concentrates on the failure modes that matter when the camera is feeding an NVR or Frigate continuously: RTSP watchdog false restarts, stuck listeners, stale library paths, and frame loss caused by a too-small camera-side FIFO.

## What it is

MStar Yi cameras run a closed media pipeline (`rmm`, `h264grabber`, `rRTSPServer`) on very small hardware. The firmware provides local RTSP, a web UI, SSH, ONVIF, FTP and optional MQTT without requiring the vendor cloud.

This fork is aimed at continuous local recording rather than cloud/app use. It does not replace the closed MStar media pipeline, and it does not claim that a buffer can make a lossy Wi-Fi link lossless.

## Changes in this fork

### RTSP watchdog

- Added a PID lock so duplicate `wd.sh` instances cannot race each other.
- Fixed `RTSP_ALT=no`: it is now treated as the standard `rRTSPServer` path instead of falling into the go2rtc branch and restarting RTSP every 10 seconds.
- Added recovery for a listener stuck in `SYN_RECV` with no established client.
- Added `/home/ms` to `LD_LIBRARY_PATH` so watchdog restarts do not fail with missing `libOMX_AVQE_A.so`.
- Reused one `netstat` and one `top` result per check instead of spawning several `top` processes every 10 seconds.
- Logs watchdog activity to `/tmp/wd.log` instead of discarding it.

### Frame buffering

The H.264 path is:

```text
camera shared frame buffer -> h264grabber -> FIFO -> rRTSPServer -> RTSP client
```

The old grabber used the Linux default 64 KB FIFO. This fork raises the camera FIFO limit to 4 MiB and configures both `h264grabber` and `h264grabber2` to use it. At typical HD frame sizes this holds several seconds of frames and absorbs short RTSP/network stalls.

A buffer cannot recover frames that the camera encoder has already lost or frames lost during a long Wi-Fi outage. It also cannot repair a corrupt source stream.

### Build/release

- Cross-compiles cleanly with the MStar build image in the upstream documentation.
- A GitHub Actions workflow builds the patched `h264grabber`/`h264grabber2` binaries on tags and publishes a release tarball.

## Status

Verified on a Yi `y203c` (MStar) camera being used as a Frigate source. The camera’s own encoder and Wi-Fi link remain the limiting factors; the watchdog and FIFO changes improve recovery and jitter tolerance, not the physical link.

## Installation

### Full firmware

The complete firmware build requires the original MStar `home` and `rootfs` partitions under `stock_firmware/y203c/`; those proprietary images are not included here. Follow the upstream installation and manual-upgrade documentation.

### Binary patch

The release tarball contains:

```text
h264grabber
h264grabber2
```

On a camera running the matching MStar firmware:

```sh
# back up first
cp /home/yi-hack/bin/h264grabber  /home/yi-hack/bin/h264grabber.bak
cp /home/yi-hack/bin/h264grabber2 /home/yi-hack/bin/h264grabber2.bak 2>/dev/null || true

# install the patched binaries
cp h264grabber  /home/yi-hack/bin/h264grabber
cp h264grabber2 /home/yi-hack/bin/h264grabber2

# allow the 4 MiB pipe
echo 4194304 > /proc/sys/fs/pipe-max-size

# restart RTSP
killall -q h264grabber h264grabber_h rRTSPServer
```

The full firmware also applies the pipe limit at boot from `script/system.sh`. For a binary-only update, add this line to the camera’s startup script if you want it to persist across reboots:

```sh
[ -w /proc/sys/fs/pipe-max-size ] && echo 4194304 > /proc/sys/fs/pipe-max-size 2>/dev/null
```

## Build

The upstream build image is used for cross-compilation:

```sh
podman run --rm --network none --entrypoint /bin/bash \
  -v "$PWD:/build:Z" -w /build \
  docker.io/borodiliz/yi-hack:latest \
  -lc './scripts/compile.sh h264grabber'
```

Output:

```text
build/home/yi-hack/bin/h264grabber
build/home/yi-hack/bin/h264grabber2
```

A full build additionally needs the submodules and stock partitions:

```sh
git submodule update --init
# populate stock_firmware/y203c/ with the original partition files
./scripts/init_sysroot.all.sh
./scripts/compile.sh
./scripts/pack_fw.all.sh
```

## Supported cameras

Support follows the upstream MStar project. This fork has been exercised on `y203c`; other models inherit upstream support and should be treated as experimental.

Do not flash a build for a different model or serial prefix.

## Credits

This project stands on the work of the yi-hack community:

- **roleoroleo** — [yi-hack-MStar](https://github.com/roleoroleo/yi-hack-MStar), the direct upstream of this fork
- **TheCrypt0** — [yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4), the foundation for the MStar port
- **andy2301** — early RTSP implementation ideas
- **borodiliz** — [yi-hack build image](https://hub.docker.com/r/borodiliz/yi-hack)
- **Live555** — RTSP/RTP server framework used by `rRTSPServer`
- Everyone who contributed to the earlier `yi-hack` projects and the Home Assistant/Frigate communities

The watchdog, FIFO and release-workflow changes in this fork are maintained by `bongomanuk`.

## License

GPLv3. See [LICENSE](LICENSE).

## Disclaimer

**NOBODY BUT YOU IS RESPONSIBLE FOR ANY USE OR DAMAGE THIS SOFTWARE MAY CAUSE. THIS IS INTENDED FOR EDUCATIONAL PURPOSES ONLY. USE AT YOUR OWN RISK.**
