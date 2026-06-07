#!/usr/bin/env python3
# MacNix Calamares Module — macOS Fetch
# Downloads macOS recovery image from Apple CDN with progress tracking
import os
import subprocess
import json
import time
import libcalamares

def run():
    """Download macOS recovery image."""
    
    # Check for UI Test mode
    try:
        with open("/proc/cmdline", "r") as f:
            if "macnix.uitest=1" in f.read():
                libcalamares.utils.debug("UI Test Mode active — simulating macOS download")
                for i in range(1, 11):
                    time.sleep(0.5)
                    libcalamares.job.setprogress(i / 10.0)
                return None
    except Exception:
        pass

    profile_path = libcalamares.globalstorage.value("macnix_gpu_profile")
    macos_target = libcalamares.globalstorage.value("macnix_macos_target") or "sonoma"
    
    vm_dir = "/var/lib/macnix/disks"
    os.makedirs(vm_dir, exist_ok=True)
    
    # Check if already downloaded
    dmg_path = os.path.join(vm_dir, "BaseSystem.dmg")
    img_path = os.path.join(vm_dir, "BaseSystem.img")
    disk_path = os.path.join(vm_dir, "macOS.qcow2")
    
    if os.path.exists(img_path) and os.path.exists(disk_path):
        libcalamares.utils.debug("macOS images already present — skipping download")
        libcalamares.job.setprogress(1.0)
        return None
    
    # Map target to fetch script selection
    sel_map = {"monterey": "3", "ventura": "2", "sonoma": "1", "sequoia": "1"}
    selection = sel_map.get(macos_target, "1")
    
    # Find fetch script
    fetch_script = None
    for path in ["/opt/macnix/osx-kvm/fetch-macOS-v2.py",
                 "/var/lib/macnix/osx-kvm/fetch-macOS-v2.py"]:
        if os.path.exists(path):
            fetch_script = path
            break
    
    if not fetch_script:
        return ("macOS fetch script not found", "OSX-KVM not installed correctly")
    
    # Download
    libcalamares.utils.debug(f"Downloading macOS {macos_target}...")
    libcalamares.job.setprogress(0.1)
    
    work_dir = os.path.join(vm_dir, "fetch-work")
    os.makedirs(work_dir, exist_ok=True)
    
    try:
        proc = subprocess.run(
            ["python3", fetch_script],
            input=selection + "\n",
            capture_output=True, text=True,
            timeout=3600,  # 1 hour max
            cwd=work_dir
        )
        if proc.returncode != 0:
            libcalamares.utils.warning(f"Fetch error: {proc.stderr}")
    except subprocess.TimeoutExpired:
        return ("Download timed out", "macOS download took longer than 1 hour")
    
    libcalamares.job.setprogress(0.5)
    
    # Find and move DMG
    for f in os.listdir(work_dir):
        if f.endswith(".dmg"):
            os.rename(os.path.join(work_dir, f), dmg_path)
            break
    
    if not os.path.exists(dmg_path):
        return ("Download failed", "BaseSystem.dmg not found after download")
    
    # Verify size
    size = os.path.getsize(dmg_path)
    if size < 50_000_000:
        return ("Download corrupt", f"BaseSystem.dmg too small ({size} bytes)")
    
    libcalamares.job.setprogress(0.6)
    
    # Convert DMG to IMG
    libcalamares.utils.debug("Converting DMG to raw image...")
    subprocess.run(["dmg2img", dmg_path, img_path], check=True)
    
    libcalamares.job.setprogress(0.8)
    
    # Create QCOW2 disk
    libcalamares.utils.debug("Creating 80GB system disk...")
    subprocess.run(
        ["qemu-img", "create", "-f", "qcow2", disk_path, "80G"],
        check=True
    )
    
    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug("macOS acquisition complete")
    return None
