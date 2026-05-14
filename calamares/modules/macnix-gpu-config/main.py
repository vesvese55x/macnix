#!/usr/bin/env python3
# MacNix Calamares Module — GPU Configuration
# Reads GPU profile and applies passthrough config (Phase 5 logic)
import os
import subprocess
import json
import libcalamares

def run():
    """Apply GPU passthrough configuration based on detected branch."""
    profile_path = libcalamares.globalstorage.value("macnix_gpu_profile")
    if not profile_path or not os.path.exists(profile_path):
        profile_path = "/etc/macnix/gpu-profile.json"
    
    if not os.path.exists(profile_path):
        return ("GPU profile not found", "Run GPU detection first")
    
    with open(profile_path) as f:
        profile = json.load(f)
    
    branch = profile["branch"]
    cpu_vendor = profile.get("cpu_vendor", "intel")
    
    libcalamares.utils.debug(f"Configuring GPU: Branch {branch}")
    libcalamares.job.setprogress(0.1)
    
    # Get the install root (chroot target)
    root = libcalamares.globalstorage.value("rootMountPoint") or ""
    
    # 1. IOMMU kernel parameters
    grub_file = os.path.join(root, "etc/default/grub")
    if os.path.exists(grub_file):
        with open(grub_file) as f:
            grub = f.read()
        
        iommu_param = "intel_iommu=on" if cpu_vendor == "intel" else "amd_iommu=on"
        for param in [iommu_param, "iommu=pt"]:
            if param not in grub:
                grub = grub.replace(
                    'GRUB_CMDLINE_LINUX_DEFAULT="',
                    f'GRUB_CMDLINE_LINUX_DEFAULT="{param} '
                )
        
        # Zero timeout for seamless boot
        import re
        grub = re.sub(r'GRUB_TIMEOUT=\d+', 'GRUB_TIMEOUT=0', grub)
        
        with open(grub_file, "w") as f:
            f.write(grub)
    
    libcalamares.job.setprogress(0.3)
    
    # 2. Branch-specific VFIO config
    if branch in ("A", "B", "E"):
        target_gpu = profile["gpus"][profile["target_gpu_idx"]]
        vid_did = f"{target_gpu['vid']}:{target_gpu['did']}"
        
        # vfio-pci module options
        vfio_conf = os.path.join(root, "etc/modprobe.d/macnix-vfio.conf")
        os.makedirs(os.path.dirname(vfio_conf), exist_ok=True)
        
        softdep = ""
        if target_gpu["vendor"] == "amd":
            softdep = "softdep amdgpu pre: vfio-pci\nsoftdep radeon pre: vfio-pci"
        elif target_gpu["vendor"] == "nvidia":
            softdep = "softdep nouveau pre: vfio-pci\nsoftdep nvidia pre: vfio-pci"
        
        with open(vfio_conf, "w") as f:
            f.write(f"options vfio-pci ids={vid_did}\n{softdep}\n")
        
        # Modules to load at boot
        modules_conf = os.path.join(root, "etc/modules-load.d/macnix-vfio.conf")
        with open(modules_conf, "w") as f:
            f.write("vfio\nvfio_iommu_type1\nvfio_pci\n")
    
    libcalamares.job.setprogress(0.5)
    
    # 3. KVM module config
    kvm_conf = os.path.join(root, "etc/modprobe.d/macnix-kvm.conf")
    os.makedirs(os.path.dirname(kvm_conf), exist_ok=True)
    with open(kvm_conf, "w") as f:
        f.write("options kvm ignore_msrs=1\noptions kvm report_ignored_msrs=0\n")
    
    libcalamares.job.setprogress(0.7)
    
    # 4. Copy scripts to installed system
    scripts_src = "/opt/macnix/scripts"
    scripts_dst = os.path.join(root, "opt/macnix/scripts")
    if os.path.exists(scripts_src):
        os.makedirs(scripts_dst, exist_ok=True)
        subprocess.run(["cp", "-r", scripts_src + "/", scripts_dst + "/"],
                      check=False)
    
    # 5. Copy single-GPU hooks if Branch E
    if branch == "E":
        hooks_src = "/opt/macnix/hooks"
        hooks_dst = os.path.join(root, "opt/macnix/hooks")
        if os.path.exists(hooks_src):
            os.makedirs(hooks_dst, exist_ok=True)
            subprocess.run(["cp", "-r", hooks_src + "/", hooks_dst + "/"],
                          check=False)
    
    libcalamares.job.setprogress(0.9)
    
    # 6. Update initramfs in chroot
    if root:
        subprocess.run(
            ["chroot", root, "update-initramfs", "-u", "-k", "all"],
            check=False
        )
        subprocess.run(
            ["chroot", root, "update-grub"],
            check=False
        )
    
    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug(f"GPU configuration complete (Branch {branch})")
    return None
