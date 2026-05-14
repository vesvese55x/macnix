# MacNix

**A custom Debian 12 distribution that boots directly into macOS via QEMU/KVM with GPU passthrough.**

Insert USB → install → reboot → macOS desktop. Zero manual configuration.

---

## What This Does

MacNix is a purpose-built Linux distro that exists solely to run macOS in a hardware-accelerated virtual machine. From the user's perspective, they see a Mac — the Linux host is invisible.

### Key Features

- **Automatic GPU detection** — identifies your GPU and selects the optimal passthrough strategy
- **5-branch GPU routing** — AMD passthrough, NVIDIA Kepler + patcher, Intel GVT-g, software fallback, or single-GPU hooks
- **macOS from Apple CDN** — downloads directly from Apple's servers during installation
- **Looking Glass display** — sub-1ms frame relay, feels native
- **Boot to macOS in <45s** — from power button to login screen
- **Recovery escape** — Right Ctrl breaks to Linux TTY for maintenance

## GPU Compatibility

| Branch | GPU Type | Strategy | Performance |
|--------|----------|----------|-------------|
| **A** | AMD discrete (RX 580, 6700XT, etc.) | VFIO passthrough | 95–100% |
| **B** | NVIDIA Kepler (GTX 660–780 Ti, Titan) | VFIO + Kepler patcher | 85–95% |
| **C** | Intel iGPU (6th–10th gen) | GVT-g virtualisation | 60–80% |
| **D** | Modern NVIDIA (Maxwell+) | Software rendering | 15–30% |
| **E** | Single GPU (any brand) | Passthrough + hooks | Same as brand |

## Requirements

- **CPU**: Intel VT-x + VT-d or AMD-V + AMD-Vi (enabled in BIOS)
- **RAM**: 16 GB minimum (32 GB recommended)
- **Disk**: 150 GB free space
- **GPU**: See compatibility table above

## Project Structure

```
macnix/
├── scripts/          # Phase 1–7 scripts (build + runtime)
│   ├── phase1-setup.sh          # Build environment
│   ├── phase2-gpu-detect.sh     # GPU detection engine
│   ├── phase3-macos-fetch.sh    # macOS download
│   ├── phase4-qemu-config.sh    # QEMU + OpenCore
│   ├── phase5-gpu-passthrough.sh # GPU passthrough
│   ├── phase6-ux-setup.sh       # Looking Glass + UX
│   ├── phase7-build-iso.sh      # ISO build
│   ├── single-gpu-hooks/        # Branch E driver hooks
│   └── utils/                   # Shared functions + GPU DB
├── calamares/        # Installer modules + branding
├── config/           # Templates (GPU profile, QEMU overrides)
├── systemd/          # Service units (VM, Looking Glass, firstboot)
└── build/            # live-build workspace (generated)
```

## Building the ISO

```bash
# 1. Set up build environment (run on Debian 12)
sudo bash scripts/phase1-setup.sh

# 2. Build the ISO
sudo bash scripts/phase7-build-iso.sh

# 3. Flash to USB
sudo dd if=build/output/macnix-*.iso of=/dev/sdX bs=4M status=progress
```

## Development: Running Phases Individually

Each phase can be tested independently on a development machine:

```bash
sudo bash scripts/phase1-setup.sh     # Install deps
sudo bash scripts/phase2-gpu-detect.sh # Detect GPU → writes /etc/macnix/gpu-profile.json
sudo bash scripts/phase3-macos-fetch.sh # Download macOS
sudo bash scripts/phase4-qemu-config.sh # Generate QEMU launch script
sudo bash scripts/phase5-gpu-passthrough.sh # Configure passthrough
sudo bash scripts/phase6-ux-setup.sh   # Set up Looking Glass + UX
```

## Architecture

```
┌─────────────────────────────────────────┐
│           User sees: macOS              │
│    (Looking Glass fullscreen window)    │
├─────────────────────────────────────────┤
│         QEMU/KVM Virtual Machine        │
│  ┌─────────┐ ┌──────┐ ┌─────────────┐  │
│  │ OpenCore│ │macOS │ │ GPU (VFIO)  │  │
│  │   EFI   │ │ disk │ │ passthrough │  │
│  └─────────┘ └──────┘ └─────────────┘  │
├─────────────────────────────────────────┤
│         Debian 12 Host (headless)       │
│  systemd → QEMU → Looking Glass        │
└─────────────────────────────────────────┘
```

## Legal

macOS is downloaded directly from Apple's CDN (`swscan.apple.com`), which is the same source used by macOS Recovery Mode and the App Store. The AppleSMC OSK key used is publicly documented. This project does not distribute any Apple software.

## License

MIT
