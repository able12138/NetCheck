# NetCheck

> **A native macOS network diagnostics app built for the Chinese mainland network environment.** On-device speed test · domestic node benchmark · LAN device discovery · Wi-Fi analysis · network diagnostics — all in one window. Everything is measured locally, with **zero telemetry and no data upload**.

<p align="center">
  <img src="screenshots/00-home.png" width="820" alt="Home: one-click checkup and network score">
</p>

---

## Why this exists

Speed-test apps built abroad have three painful mismatches in mainland China. This project targets exactly those:

| Pain point | How NetCheck handles it |
|---|---|
| Foreign speed-test apps only have overseas servers, so you end up measuring "the speed of your VPN", not your actual broadband | Ships **16 domestic nodes** (cloud-vendor mirrors + university/education-network mirrors + Ookla Shanghai Telecom), each probed first and then benchmarked with timed multi-connection downloads. Failures are **honestly attributed** (WAF block / redirect / anti-bot challenge page / node unreachable / extremely slow) instead of being reported as "your network is broken" |
| Speed test only — no LAN or Wi-Fi insight | Built-in **LAN device discovery** (ARP + ICMP + reverse DNS + port fingerprinting + mDNS, with the IEEE 54,204-entry vendor database for offline identification) and **Wi-Fi analysis** (signal / noise / SNR / channel congestion / neighbours / security) |
| The legacy `airport` command no longer works on macOS 15, so many older tools can't even scan Wi-Fi | Talks directly to **CoreWLAN**, so signal, channel, bandwidth and noise are all readable |

It also fixes a common "inherited misjudgement" found in similar tools: **without location permission, macOS only lets an app reliably tell "open network" from "WEP"** — NetCheck never misreports a secured network as open, and honestly labels everything else as "encrypted · location permission required".

## Features

<p align="center">
  <img src="screenshots/01-speedtest.png" width="400" alt="Speed test">
  <img src="screenshots/05-diagnostics.png" width="400" alt="Diagnostics">
</p>

| Page | What it does |
|---|---|
| **Home · one-click checkup** | Circular health score (0–100, weighted across seven factors; **untested items never inflate the score**) plus a single button that walks through wireless link → channel environment → public egress → latency → upload/download, ending with a list of things worth improving |
| **Speed test** | Real upload/download, latency, jitter, public egress IP. Three selectable engines (domestic multi-connection / Ookla node / Apple's `networkQuality`), live rate, stop anytime (⌘.), one-click copyable report |
| **Node benchmark** | All 16 domestic nodes in one go (3 concurrent), auto-sorted with the fastest highlighted; every failed node gets an **actionable, accurate reason** |
| **LAN devices** | ARP + ICMP liveness + reverse DNS + 28 port fingerprints + mDNS discovery, identifying device type and vendor (a /24 scan finishes in 3.2 s) |
| **Wi-Fi analysis** | Signal / noise / SNR / channel / width / PHY / security, plus a quality score, live signal chart, 2.4 GHz & 5 GHz channel-occupancy maps and plain-language Chinese advice |
| **Network diagnostics** | Gateway / DNS / proxy / tunnel detection, public egress lookup through domestic endpoints (multi-egress aware) and a 10-target domestic latency matrix |
| **Menu-bar live rate** | Always-visible `↓x.x ↑x.x` sampled once a second from the default interface — real traffic, without running a speed test |

<p align="center">
  <img src="screenshots/04-wifi.png" width="400" alt="Wi-Fi analysis">
  <img src="screenshots/03-lan.png" width="400" alt="LAN device discovery">
</p>

## Build & run

**Requirements**: macOS 13+ (verified on 15.8) and **Xcode Command Line Tools** (for `swiftc`; a full Xcode installation is *not* needed).

```bash
git clone https://github.com/able12138/NetCheck.git
cd NetCheck
./build.sh              # produces build/网络体检.app
open "build/网络体检.app"

# Optional: install into /Applications
cp -R "build/网络体检.app" /Applications/
```

`./build.sh --universal` cross-compiles both slices and `lipo`s them into a single Intel + Apple Silicon binary — this works from either architecture.

**Optional dependencies** (the app degrades gracefully without them):

| Dependency | Used for | Install |
|---|---|---|
| `speedtest` (speedtest-go) | Ookla node benchmarking and the upload-test channel | Grab the `Darwin_x86_64` / `Darwin_arm64` build from [speedtest-go releases](https://github.com/showwin/speedtest-go/releases) and put it in `/usr/local/bin` |
| `fping` | Faster LAN liveness probing (falls back to the system `ping`) | `brew install fping` |
| `curl` | Node probing and test-file validation | Preinstalled on macOS |

## Built-in verification tools

Every claim this project makes comes with a script you can re-run — the numbers are not just written down in a document:

| Tool | Purpose |
|---|---|
| `./tools/selftest.sh` | CLI self-test: actually exercises the Wi-Fi / node / LAN / diagnostics engines |
| `./tools/nodetest.sh [seconds]` | Full node re-verification: runs all 16 nodes and prints status, speed and a **failure-attribution summary** |
| `./tools/perfcheck.sh` | Responsiveness measurement: main-thread queueing delay and speed-test callback rate (i.e. "is the UI janky?") |
| `./tools/uishot.sh <dir>` | Off-screen render of all six pages to PNG via `ImageRenderer` — **no screen-recording permission required** |
| `./tools/update-oui.sh` | Download and merge the latest IEEE OUI vendor data |

## Measured results (reproducible)

- **Speed test**: 37–46 Mbps down / 23–35 Mbps up, 24 ms latency (domestic telecom broadband; cross-checked between Tencent Cloud and Ookla Shanghai Telecom)
- **Node availability**: a stable **7–8 of 16** domestic nodes are usable (Tencent Cloud, Ookla Shanghai Telecom, Tsinghua TUNA, HUST, QLU, BFSU, NetEase)
- **LAN**: auto-detects the subnet, finds 12 devices in 3.2 s and identifies their vendors
- **Wi-Fi**: 802.11ac / 5 GHz / 80 MHz / 585 Mbps negotiated rate, signal −47 dBm, noise −93 dBm, SNR 46 dB
- **Responsiveness**: worst main-thread queueing during a Wi-Fi scan **1670 ms → 0 ms**; speed-test progress callbacks **53.5/s → 4.2/s**

> Full per-item measurements, the node failure-attribution table and design trade-offs are documented in **[使用说明.md](使用说明.md)** (section 10 covers node-test failure attribution; the document is in Chinese).

## Privacy

- **Every measurement happens on your machine.** The app never reports anything to a server operated by this project. The only requests it makes are: ① public speed-test sources (domestic mirror sites hosting large ISO files, or Ookla nodes); ② public IP-geolocation endpoints (`cip.cc`, `ip.3322.net`, `myip.ipip.net`, `api.ipify.org`).
- **No analytics, no tracking, no account system.**
- All screenshots and sample data in this repository are **synthetic or documentation values**: IPs use the RFC 5737 documentation ranges (`203.0.113.x` / `198.51.100.x`), and Wi-Fi names and MAC addresses are fictitious (vendor OUI prefixes are kept so the vendor-identification feature can be demonstrated).
- The app reads your Wi-Fi name and LAN device information for **local display only**; none of it ever leaves the machine.

## Known limitations

- **Wi-Fi name (SSID/BSSID) and exact security type**: since macOS 14 these require **location permission**. Without it the app shows "name hidden" and can only reliably distinguish open / WEP / encrypted.
- **Upload test**: there is no public upload-test endpoint in mainland China, so this relies on the Ookla (Shanghai Telecom) channel. When it falls back to Cloudflare the result is labelled "cross-border, for reference only", because it understates domestic upload capacity.
- **Mirror-node availability fluctuates heavily**: the same node can differ by two orders of magnitude between runs (Tsinghua TUNA has measured anywhere from 0.06 to 42 Mbps). To judge your real broadband capability, look at **Tencent Cloud** and **Ookla Shanghai Telecom**.
- The app **never** modifies system settings and offers no unverifiable "network optimisation / one-click boost" features.

## Implementation notes

- **Pure Swift + SwiftUI, compiled directly with `swiftc`** — no Xcode project file, no Electron/Tauri. A single `build.sh` produces the `.app`.
- **Wi-Fi**: CoreWLAN (`CWWiFiClient`) native scanning; `airport` is dead on macOS 15.
- **Speed test**: concurrent `URLSession` downloads with timed sampling; automatically falls back to whole-file download when Range requests are unsupported.
- **Node probing**: a single `curl` call returns the final (redirected) URL, status code, bytes actually received and response headers at once — enough to distinguish a WAF block (`418` + `X-Hwwaf-Attack-Id`), an anti-bot challenge (`cerberus-sec: CHALLENGE`), an HTML page served instead of a file, a redirect loop, and a plain unreachable node.
- **Responsiveness**: CoreWLAN calls and subprocesses are moved off the main thread, progress callbacks are rate-limited, and jank is quantified with a main-thread delay probe instead of being guessed at.

## Development environment

Developed and verified on: macOS 15.8.1 · Intel i9-9980HK / 32 GB · swiftc 6.2.4 (Command Line Tools, no Xcode). Both Intel and Apple Silicon are supported; `build.sh` reads the host architecture by default and `--universal` produces a fat binary.

## Third-party data and credits

- **IEEE OUI data** (`resources/ieee-oui.txt`): taken from IEEE's publicly published OUI registry to identify network-interface and device vendors offline; refresh it with `./tools/update-oui.sh`. Copyright remains with IEEE.
- **Speed-test sources**: public mirror sites (Tencent Cloud, Tsinghua TUNA, HUST, QLU, BFSU, NetEase…) and public Ookla nodes. The app only downloads public large files for measurement and stores none of the content.
- Interaction conventions follow the general practice of comparable macOS network tools; **no third-party code was copied**.

## License

[MIT](LICENSE) © 2026 able12138
