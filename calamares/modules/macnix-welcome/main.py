#!/usr/bin/env python3
# MacNix Calamares Module — Welcome & Requirements Check
# Validates hardware requirements before installation begins
import os
import subprocess
import libcalamares

def check_cpu_virt():
    """Check for VT-x/AMD-V support."""
    try:
        with open("/proc/cpuinfo") as f:
            cpuinfo = f.read()
        return "vmx" in cpuinfo or "svm" in cpuinfo
    except:
        return False

def check_ram():
    """Check RAM >= 16GB. Returns (total_gb, passes)."""
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    kb = int(line.split()[1])
                    gb = kb // (1024 * 1024)
                    return gb, gb >= 16
    except:
        pass
    return 0, False

def check_disk_space():
    """Check free disk space >= 150GB. Returns (free_gb, passes)."""
    try:
        st = os.statvfs("/")
        free_gb = (st.f_bavail * st.f_frsize) // (1024**3)
        return free_gb, free_gb >= 150
    except:
        return 0, False

def check_kvm():
    """Check /dev/kvm exists."""
    return os.path.exists("/dev/kvm")

def check_iommu():
    """Check if IOMMU groups exist."""
    iommu_path = "/sys/kernel/iommu_groups"
    if os.path.isdir(iommu_path):
        groups = os.listdir(iommu_path)
        return len(groups) > 0
    return False

def check_internet():
    """Basic internet connectivity check."""
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", "3", "1.1.1.1"],
            capture_output=True, timeout=5
        )
        return result.returncode == 0
    except:
        return False

def run():
    """Run all pre-flight checks."""
    results = []
    all_pass = True
    critical_fail = False
    
    # CPU virtualisation
    virt_ok = check_cpu_virt()
    results.append(("CPU Virtualisation (VT-x/AMD-V)", virt_ok, True))
    if not virt_ok:
        critical_fail = True
    
    # KVM
    kvm_ok = check_kvm()
    results.append(("/dev/kvm available", kvm_ok, True))
    if not kvm_ok:
        critical_fail = True
    
    # RAM
    ram_gb, ram_ok = check_ram()
    results.append((f"RAM: {ram_gb} GB (16 GB minimum)", ram_ok, True))
    if not ram_ok:
        critical_fail = True
    
    # Disk
    free_gb, disk_ok = check_disk_space()
    results.append((f"Disk: {free_gb} GB free (150 GB minimum)", disk_ok, False))
    if not disk_ok:
        all_pass = False
    
    # IOMMU (warning only — might not be enabled yet)
    iommu_ok = check_iommu()
    results.append(("IOMMU groups detected", iommu_ok, False))
    if not iommu_ok:
        all_pass = False
    
    # Internet
    inet_ok = check_internet()
    results.append(("Internet connection", inet_ok, True))
    if not inet_ok:
        critical_fail = True
    
    # Log results
    libcalamares.utils.debug("=== MacNix Pre-Flight Checks ===")
    for name, passed, required in results:
        status = "✓ PASS" if passed else ("✗ FAIL" if required else "⚠ WARN")
        libcalamares.utils.debug(f"  {status}: {name}")
    
    # Store results
    libcalamares.globalstorage.insert("macnix_preflight_passed", not critical_fail)
    libcalamares.globalstorage.insert("macnix_ram_gb", ram_gb)
    libcalamares.globalstorage.insert("macnix_disk_free_gb", free_gb)
    
    if critical_fail:
        failures = [name for name, passed, req in results if not passed and req]
        return (
            "Hardware requirements not met",
            "Failed checks:\n" + "\n".join(f"  • {f}" for f in failures) +
            "\n\nPlease check BIOS settings and ensure minimum hardware requirements are met."
        )
    
    return None
