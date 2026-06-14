#!/usr/bin/env python3
# MacNix Calamares Module — GPU Configuration
# Reads GPU profile and applies passthrough config (Phase 5 logic)
import os
import re
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

    branch = profile.get("branch", "D")
    cpu_vendor = profile.get("cpu_vendor", "intel")
    gpus = profile.get("gpus", [])
    target_gpu_idx = profile.get("target_gpu_idx", 0)

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

        # Ensure GRUB_CMDLINE_LINUX_DEFAULT exists
        if 'GRUB_CMDLINE_LINUX_DEFAULT=' not in grub:
            grub += '\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n'

        for param in [iommu_param, "iommu=pt"]:
            if param not in grub:
                grub = grub.replace(
                    'GRUB_CMDLINE_LINUX_DEFAULT="',
                    f'GRUB_CMDLINE_LINUX_DEFAULT="{param} '
                )

        # Plymouth theme for Apple boot
        if "plymouth.theme=macnix" not in grub:
            grub = grub.replace(
                'GRUB_CMDLINE_LINUX_DEFAULT="',
                'GRUB_CMDLINE_LINUX_DEFAULT="splash plymouth.theme=macnix '
            )

        # Zero timeout for seamless boot
        grub = re.sub(r'GRUB_TIMEOUT=\d+', 'GRUB_TIMEOUT=0', grub)

        # Hide GRUB menu
        if 'GRUB_TIMEOUT_STYLE=' not in grub:
            grub += '\nGRUB_TIMEOUT_STYLE=hidden\n'
        else:
            grub = re.sub(r'GRUB_TIMEOUT_STYLE=\w+', 'GRUB_TIMEOUT_STYLE=hidden', grub)

        with open(grub_file, "w") as f:
            f.write(grub)

    libcalamares.job.setprogress(0.3)

    # 2. Branch-specific VFIO config
    if branch in ("A", "B", "E") and gpus and target_gpu_idx < len(gpus):
        target_gpu = gpus[target_gpu_idx]
        vid = target_gpu.get("vid", "")
        did = target_gpu.get("did", "")

        if vid and did:
            vid_did = f"{vid}:{did}"

            # vfio-pci module options
            vfio_conf = os.path.join(root, "etc/modprobe.d/macnix-vfio.conf")
            os.makedirs(os.path.dirname(vfio_conf), exist_ok=True)

            softdep = ""
            vendor = target_gpu.get("vendor", "")
            if vendor == "amd":
                softdep = "softdep amdgpu pre: vfio-pci\nsoftdep radeon pre: vfio-pci"
            elif vendor == "nvidia":
                softdep = "softdep nouveau pre: vfio-pci\nsoftdep nvidia pre: vfio-pci"

            with open(vfio_conf, "w") as f:
                f.write(f"options vfio-pci ids={vid_did}\n{softdep}\n")

            # Modules to load at boot
            modules_conf = os.path.join(root, "etc/modules-load.d/macnix-vfio.conf")
            os.makedirs(os.path.dirname(modules_conf), exist_ok=True)
            with open(modules_conf, "w") as f:
                f.write("vfio\nvfio_iommu_type1\nvfio_pci\n")
        else:
            libcalamares.utils.warning(
                f"GPU at index {target_gpu_idx} has no vid/did — skipping VFIO config"
            )

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

    # Copy systemd services
    svc_src = "/opt/macnix/systemd"
    svc_dst = os.path.join(root, "etc/systemd/system")
    if os.path.exists(svc_src):
        os.makedirs(svc_dst, exist_ok=True)
        for svc_file in os.listdir(svc_src):
            if svc_file.endswith(".service"):
                subprocess.run(
                    ["cp", os.path.join(svc_src, svc_file), svc_dst],
                    check=False
                )

    # Copy Plymouth theme
    plymouth_src = "/opt/macnix/plymouth/macnix"
    plymouth_dst = os.path.join(root, "usr/share/plymouth/themes/macnix")
    if os.path.exists(plymouth_src):
        os.makedirs(plymouth_dst, exist_ok=True)
        subprocess.run(["cp", "-r", plymouth_src + "/", plymouth_dst + "/"],
                        check=False)

    # 5. Copy single-GPU hooks if Branch E
    if branch == "E":
        hooks_src = "/opt/macnix/hooks"
        hooks_dst = os.path.join(root, "opt/macnix/hooks")
        if os.path.exists(hooks_src):
            os.makedirs(hooks_dst, exist_ok=True)
            subprocess.run(["cp", "-r", hooks_src + "/", hooks_dst + "/"],
                            check=False)

    libcalamares.job.setprogress(0.85)

    # 6. Enable firstboot setup assistant
    firstboot_svc = os.path.join(root, "etc/systemd/system/macnix-firstboot.service")
    with open(firstboot_svc, "w") as f:
        f.write("""[Unit]
Description=MacNix First Boot Setup Assistant
After=multi-user.target network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/macnix/.firstboot-done

[Service]
Type=oneshot
ExecStart=/opt/macnix/scripts/macnix-setup-assistant.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
""")

    # Enable the firstboot service via symlink
    wants_dir = os.path.join(root, "etc/systemd/system/multi-user.target.wants")
    os.makedirs(wants_dir, exist_ok=True)
    symlink_path = os.path.join(wants_dir, "macnix-firstboot.service")
    try:
        os.symlink("/etc/systemd/system/macnix-firstboot.service", symlink_path)
    except FileExistsError:
        pass

    libcalamares.job.setprogress(0.9)

    # 7. Update initramfs and GRUB in chroot
    if root:
        subprocess.run(
            ["chroot", root, "update-initramfs", "-u", "-k", "all"],
            check=False
        )
        subprocess.run(
            ["chroot", root, "update-grub"],
            check=False
        )

        # Set Plymouth default theme
        subprocess.run(
            ["chroot", root, "plymouth-set-default-theme", "-R", "macnix"],
            check=False
        )

    libcalamares.job.setprogress(1.0)
    libcalamares.utils.debug(f"GPU configuration complete (Branch {branch})")
    return None
