# Methodology and threat model

## What I set out to do
Start from a retail Yandex Station Lite with no special access, and end up understanding its
software well enough to control it locally. All on my own device and network.

## Threat model
I assume control of the local router and one machine on the same LAN. No opening the case, no
JTAG or serial soldering, no flashing foreign firmware. The thing that makes root possible is
that the firmware still trusts eMudhra CA certificates whose keys leaked, so a local machine
can present a certificate the speaker accepts for `quasar.yandex.net`. Everything is
reversible: the DNS redirect and the fake server come down at the end, and the speaker goes
back to talking to the real cloud.

## The steps
1. Get root: redirect the Quasar hostnames to a local server, answer the config request with
   `remoteActivation` on, and offer one OTA so an old factory build can finish setup. (01)
2. Recon: hardware, partitions, filesystem, local and cloud endpoints. (02)
3. Reverse `maind` in IDA. (03)
4. Telemetry and privacy. (04)
5. Audio and LED. (05)
6. glagol, the LAN control protocol. (06)

## Two tracks, merged
This repo brings together two efforts on the same unit: the rooting itself (01, plus the
dossier) and the post-root reverse engineering (03–06). Read it start to finish and it's one
story: get in, understand it, control it.

## Constraints worth knowing
The operator machine was sandboxed in places (no sudo, Docker or pty), and the speaker is a
stripped BusyBox/armhf box with no on-device debugger. So most of the analysis happened on
the host, after pulling files off the device.
