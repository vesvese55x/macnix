#!/usr/bin/env python3
# MacNix Calamares Module — macOS VM Installation
# Runs a headless QEMU session to install macOS from recovery image
# Monitors progress and takes a clean-install snapshot when done
import os
import subprocess
import time
import signal
import json
import libcalamares

INSTALL_TIMEOUT = 7200  # 2 hours max
POLL_INTERVAL = 30      # seconds between progress checks
VM_DIR = "/var/lib/macnix/disks"
FW_DIR = "/var/lib/macnix/firmware"

def find_ovmf():
    """Locate OVMF firmware files."""
    for code in ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd",
                 "/usr/share/edk2/ovmf/OVMF_CODE.fd"]:
        if os.path.exists(code):
            vars_path = code.replace("CODE", "VARS")
            if os.path.exists(vars_path):
                return code, vars_path
    return None, None

def build_install_command():
    """Build the QEMU command for headless macOS installation."""
    macos_disk = os.path.join(VM_DIR, "macOS.qcow2")
    install_img = os.path.join(VM_DIR, "BaseSystem.img")
    ovmf_code, ovmf_vars = find_ovmf()
    
    # Find OpenCore image
    oc_img = None
    for p in [os.path.join(FW_DIR, "OpenCore/OpenCore.qcow2"),
              "/opt/macnix/osx-kvm/OpenCore/OpenCore.qcow2"]:
        if os.path.exists(p):
            oc_img = p
            break
    
    if not all([macos_disk, install_img, ovmf_code]):
        return None, "Missing required files for installation"
    
    # OSK key (publicly documented)
    osk = "ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
    
    cores = min(os.cpu_count() // 2, 8)
    if cores < 2:
        cores = 2
    
    ram_gb = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES') // (1024**3)
    vm_ram = min(ram_gb // 2, 16)
    if vm_ram < 4:
        vm_ram = 4
    
    cmd = [
        "qemu-system-x86_64",
        "-enable-kvm",
        "-machine", "q35,accel=kvm",
        "-cpu", "host,kvm=on,vendor=GenuineIntel,+kvm_pv_unhalt,+kvm_pv_eoi,+hypervisor,+invtsc",
        "-smp", f"cores={cores},threads=1,sockets=1",
        "-m", f"{vm_ram * 1024}",
        "-device", f"isa-applesmc,osk={osk}",
        "-smbios", "type=2,manufacturer=Apple Inc.,product=iMac19,1",
        "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf_code}",
        "-drive", f"if=pflash,format=raw,file={ovmf_vars}",
        "-device", "virtio-vga",
        "-display", "none",
        "-drive", f"id=MacHDD,if=none,file={macos_disk},format=qcow2",
        "-device", "virtio-blk-pci,drive=MacHDD",
        "-drive", f"id=InstallMedia,if=none,file={install_img},format=raw",
        "-device", "ide-hd,bus=sata.3,drive=InstallMedia",
        "-netdev", "user,id=net0",
        "-device", "virtio-net-pci,netdev=net0",
        "-device", "qemu-xhci",
        "-device", "usb-tablet",
        "-device", "usb-kbd",
        "-global", "nec-usb-xhci.msi=off",
        "-global", "ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off",
        "-serial", "mon:stdio",
        "-nographic",
    ]
    
    if oc_img:
        cmd.extend([
            "-drive", f"id=OpenCore,if=none,format=qcow2,file={oc_img}",
            "-device", "ide-hd,bus=sata.2,drive=OpenCore",
        ])
    
    return cmd, None

def check_disk_growing(disk_path, last_size):
    """Check if the macOS disk is growing (installation in progress)."""
    try:
        current = os.path.getsize(disk_path)
        return current, current > last_size
    except OSError:
        return last_size, False

def run():
    """Run headless macOS installation."""
    
    # Check for UI Test mode
    try:
        with open("/proc/cmdline", "r") as f:
            if "macnix.uitest=1" in f.read():
                libcalamares.utils.debug("UI Test Mode active — simulating macOS installation")
                for i in range(1, 21):
                    time.sleep(0.5)
                    libcalamares.job.setprogress(i / 20.0)
                return None
    except Exception:
        pass

    macos_disk = os.path.join(VM_DIR, "macOS.qcow2")
    
    # Check if already installed (disk > 5GB means macOS is likely installed)
    if os.path.exists(macos_disk):
        size_gb = os.path.getsize(macos_disk) / (1024**3)
        if size_gb > 5:
            libcalamares.utils.debug(f"macOS disk is {size_gb:.1f} GB — appears already installed")
            libcalamares.job.setprogress(1.0)
            return None
    
    cmd, error = build_install_command()
    if error:
        return ("Installation setup failed", error)
    
    libcalamares.utils.debug("Starting headless macOS installation...")
    libcalamares.utils.debug(f"This will take 30-90 minutes depending on internet speed")
    libcalamares.job.setprogress(0.05)
    
    # Launch QEMU
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL
        )
    except Exception as e:
        return ("Failed to start QEMU", str(e))
    
    # Monitor installation progress
    start_time = time.time()
    last_disk_size = 0
    stall_count = 0
    max_stalls = 20  # 20 * 30s = 10 min of no disk activity before timeout
    
    while proc.poll() is None:
        elapsed = time.time() - start_time
        
        if elapsed > INSTALL_TIMEOUT:
            proc.terminate()
            return ("Installation timed out", f"macOS installation exceeded {INSTALL_TIMEOUT//3600} hours")
        
        # Check disk growth as progress indicator
        current_size, growing = check_disk_growing(macos_disk, last_disk_size)
        
        if growing:
            stall_count = 0
            # Estimate progress: macOS install grows disk to ~25-30GB
            progress = min(0.95, 0.05 + (current_size / (30 * 1024**3)) * 0.9)
            libcalamares.job.setprogress(progress)
            libcalamares.utils.debug(
                f"Installing... disk: {current_size / (1024**3):.1f} GB, "
                f"elapsed: {elapsed/60:.0f} min"
            )
        else:
            stall_count += 1
            if stall_count > max_stalls and current_size > 5 * 1024**3:
                # Disk stopped growing and is >5GB — installation likely complete
                libcalamares.utils.debug("Disk growth stopped — installation appears complete")
                proc.terminate()
                break
        
        last_disk_size = current_size
        time.sleep(POLL_INTERVAL)
    
    # Take snapshot
    libcalamares.utils.debug("Taking clean-install snapshot...")
    subprocess.run([
        "qemu-img", "snapshot", "-c", "clean-install", macos_disk
    ], check=False)
    
    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug("macOS installation complete")
    return None
