# yihack-tng

**A stability-first firmware fork for MStar-based Yi cameras that feed local NVRs and Frigate.**

`yihack-tng` starts from [roleoroleo/yi-hack-MStar](https://github.com/roleoroleo/yi-hack-MStar), but it is not a rebrand or a feature-parity clone. It is a small, opinionated maintenance fork for one job: keeping an old MStar camera streaming continuously to a local recorder without unnecessary restarts, hidden frame loss, or fragile release handling.

The camera hardware is still the camera hardware. This project does not replace the closed `rmm` media pipeline, does not add cloud services, and does not claim that software can make a marginal Wi-Fi link lossless.

## Why this fork exists

This fork started for a simple reason: I got annoyed with weird dropouts and instability in Frigate. The camera would look fine in its own app, then Frigate would show gaps, restarts, or corrupt frames with no obvious cause.

A camera that looks fine in a vendor app can still be a poor NVR source. The failure modes are usually not dramatic:

- the RTSP watchdog treats a healthy but idle-ish stream as locked and restarts it;
- a watchdog restart loses `LD_LIBRARY_PATH` and cannot start the RTSP server again;
- duplicate watchdogs race each other;
- the H.264 grabber fills a small FIFO, blocks, and the camera’s shared frame ring overwrites frames;
- the result is a stream that “works” but drops frames at unpredictable intervals.

`yihack-tng` addresses those specific paths and keeps the rest of the upstream firmware familiar.

## Design goals

- **Continuous local streaming first.** The target workload is Frigate/NVR, not phone-app viewing.
- **No forced quality reduction.** Resolution is a user choice, not a hidden stability hack.
- **Predictable recovery.** Restart RTSP only when it is actually stuck.
- **Visible diagnostics.** Watchdog decisions go to `/tmp/wd.log`, not `/dev/null`.
- **Reversible changes.** Binary releases are small and can be backed up before deployment.

## What is different from upstream

| Area | Upstream MStar behaviour | yihack-tng |
| --- | --- | --- |
| RTSP watchdog selection | Anything other than `standard`/`alternative` falls into the go2rtc branch | `standard`, `no`, empty and unknown values safely use the standard `rRTSPServer` path |
| Duplicate watchdogs | Multiple `wd.sh` processes can run | PID lock prevents a second instance |
| Stuck listener | A listener in `SYN_RECV` with no established client may never recover | Three consecutive checks with `SYN_RECV` and no `ESTABLISHED` trigger a clean RTSP restart |
| Stale RTSP session | The listener and TCP connection stay up, but the server stops forwarding frames | Three checks with no RTSP I/O progress while a client is connected restart the RTSP pipeline |
| Restart environment | `service.sh` restarts can miss `/home/ms` and fail on `libOMX_AVQE_A.so` | The RTSP start path exports the required library directories |
| Watchdog CPU cost | Several `top` invocations per check | One `netstat` and one `top` result are reused per check |
| Frame buffering | Default 64 KB FIFO in the standard grabber | 4 MiB FIFO in both grabber variants, with the camera pipe limit raised at boot and at runtime |
| Release process | No binary release workflow in this fork | Tag-driven GitHub Actions build and release of the patched grabber |

## The RTSP path

```text
camera sensor / encoder
        |
        v
  fshare frame buffer
        |
        v
   h264grabber  ---- FIFO (/tmp/h264_high_fifo) ---->  rRTSPServer  ---->  Frigate/NVR
```

The buffer is deliberately on the camera side of that path. It absorbs short stalls between the encoder and the RTSP server. It cannot recover frames that the encoder never produced, frames lost by the camera’s Wi-Fi stack, or a decoder failure downstream.

### Buffer sizing

Linux imposes a per-pipe maximum (`/proc/sys/fs/pipe-max-size`). On the tested `y203c` camera this defaulted to 1 MB, smaller than the 4 MiB target. `yihack-tng` therefore:

1. raises the pipe maximum at startup from `script/system.sh`;
2. opens the grabber FIFO with `F_SETPIPE_SZ` set to 4 MiB;
3. uses the same limit in both `h264grabber` and `h264grabber2`.

For a binary-only update, the startup line must be added manually or the pipe maximum will prevent the larger FIFO from being allocated.

## Compatibility

The upstream project supports several Yi/MStar models selected by serial prefix and stock firmware version. This fork inherits that model support, but only `y203c` has been explicitly exercised with the watchdog and FIFO changes.

Treat other models as upstream-supported but not yet validated with this fork’s binary patch. Do not flash a build intended for a different model or serial prefix.

## Installation

### Full firmware

A complete firmware build still needs the original MStar `home` and `rootfs` partitions in `stock_firmware/<model>/`. Those proprietary images are not part of this repository. Use the upstream installation and manual-upgrade procedure, then apply this fork’s source changes.

### Binary patch

The release asset contains the patched binaries and watchdog scripts:

```text
h264grabber
h264grabber2
wd.sh
service.sh
system.sh
```

On a compatible camera:

```sh
cp /home/yi-hack/bin/h264grabber  /home/yi-hack/bin/h264grabber.bak
cp /home/yi-hack/bin/h264grabber2 /home/yi-hack/bin/h264grabber2.bak 2>/dev/null || true

cp h264grabber  /home/yi-hack/bin/h264grabber
cp h264grabber2 /home/yi-hack/bin/h264grabber2
chmod 755 /home/yi-hack/bin/h264grabber /home/yi-hack/bin/h264grabber2

echo 4194304 > /proc/sys/fs/pipe-max-size

# optional watchdog/startup scripts from the same release
cp /home/yi-hack/script/wd.sh      /home/yi-hack/script/wd.sh.bak
cp /home/yi-hack/script/service.sh /home/yi-hack/script/service.sh.bak
cp /home/yi-hack/script/system.sh  /home/yi-hack/script/system.sh.bak
cp wd.sh      /home/yi-hack/script/wd.sh
cp service.sh /home/yi-hack/script/service.sh
cp system.sh  /home/yi-hack/script/system.sh

killall -q h264grabber h264grabber_h rRTSPServer
```

To persist the pipe limit across reboots, add this to the camera’s `script/system.sh`:

```sh
[ -w /proc/sys/fs/pipe-max-size ] && echo 4194304 > /proc/sys/fs/pipe-max-size 2>/dev/null
```

## Build

The upstream MStar build image is used directly; Docker compatibility is not required:

```sh
podman run --rm --network none --entrypoint /bin/bash \
  -v "$PWD:/build:Z" -w /build \
  docker.io/borodiliz/yi-hack:latest \
  -lc './scripts/compile.sh h264grabber'
```

Outputs:

```text
build/home/yi-hack/bin/h264grabber
build/home/yi-hack/bin/h264grabber2
```

A full firmware build additionally requires the submodules and stock partitions:

```sh
git submodule update --init
# populate stock_firmware/y203c/ with the original partition files
./scripts/init_sysroot.all.sh
./scripts/compile.sh
./scripts/pack_fw.all.sh
```

## Releases

The workflow in `.github/workflows/build-release.yml` builds the patched grabber on a tag and attaches:

```text
yihack-tng-<tag>.tar.gz
```

Release assets are binary and script patches, not complete firmware images. This is intentional: the stock partitions cannot be redistributed with the source. The current release is [`v0.5.8-tng.3`](https://github.com/bongomanuk/yihack-tng/releases/tag/v0.5.8-tng.3).

## Builds and testing

GitHub Actions can build the package on a tag; the workflow currently compiles `h264grabber`/`h264grabber2` and packages the RTSP scripts. It can be extended to produce packages for other MStar models, but each model needs its own firmware/scripts and validation.

The maintainer does not have access to hardware to test builds. Releases are compiled and packaged automatically, but are not hardware-validated; test on a spare camera before deploying.

## Credits

`yihack-tng` is built on work by:

- **[roleoroleo](https://github.com/roleoroleo)** — [yi-hack-MStar](https://github.com/roleoroleo/yi-hack-MStar), the upstream project this fork follows
- **[TheCrypt0](https://github.com/TheCrypt0)** — [yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4), the foundation for the MStar port
- **andy2301** — early RTSP implementation ideas
- **[borodiliz](https://hub.docker.com/r/borodiliz/yi-hack)** — the MStar build image used for reproducible cross-compilation
- **Live555** — the RTSP/RTP framework behind `rRTSPServer`
- **The wider yi-hack and Home Assistant/Frigate communities** — documentation, testing, and reverse-engineering work that made these cameras usable locally

The `yihack-tng` watchdog, FIFO, documentation, and release-workflow changes are maintained by [bongomanuk](https://github.com/bongomanuk).

## License

GPLv3. See [LICENSE](LICENSE).

## Disclaimer

**NOBODY BUT YOU IS RESPONSIBLE FOR ANY USE OR DAMAGE THIS SOFTWARE MAY CAUSE. THIS IS INTENDED FOR EDUCATIONAL PURPOSES ONLY. USE AT YOUR OWN RISK.**
