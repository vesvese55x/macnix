#!/usr/bin/env python3
# MacNix Calamares Module — GPU Detection
# Runs Phase 2 GPU detection logic and presents results to user
import os
import subprocess
import json
import libcalamares

# macOS version recommendation matrix
MACOS_RECOMMENDATIONS = {
    # (vendor, series) -> (macos_version, reason)
    ("amd", "rx500"):   ("sequoia", "Full Metal support, mature drivers"),
    ("amd", "rx5000"):  ("sequoia", "Native Navi 10 support"),
    ("amd", "rx6000"):  ("sonoma",  "Best tested, very stable"),
    ("amd", "rx7000"):  ("sonoma",  "Newer Navi 3x, needs WhateverGreen"),
    ("amd", "vega"):    ("sequoia", "Vega architecture fully supported"),
    ("amd", "generic"): ("sonoma",  "AMD GPU with Metal support"),
    ("nvidia", "kepler"): ("monterey", "Last macOS with NVIDIA web drivers"),
    ("nvidia", "generic"): ("monterey", "Modern NVIDIA has no macOS support"),
    ("intel", "generic"):  ("sonoma",   "WhateverGreen iGPU patches"),
    ("none", "none"):      ("ventura",  "Lightest for software rendering"),
}

BRANCH_INFO = {
    "A": {"desc": "AMD VFIO Passthrough",       "perf": "95-100%"},
    "B": {"desc": "NVIDIA Kepler VFIO (ROM)",    "perf": "85-95%"},
    "C": {"desc": "Intel iGPU (GVT-g/SR-IOV)",   "perf": "60-80%"},
    "D": {"desc": "Software Rendering",          "perf": "15-30%"},
    "E": {"desc": "Single-GPU Passthrough",      "perf": "95-100%"},
}


def detect_gpu_series(lspci_line):
    """Detect AMD GPU series from lspci output line."""
    line_lower = lspci_line.lower()
    if "navi 10" in line_lower or "5600" in line_lower or "5700" in line_lower:
        return "rx5000"
    if "navi 2" in line_lower or "6600" in line_lower or "6700" in line_lower or "6800" in line_lower or "6900" in line_lower:
        return "rx6000"
    if "navi 3" in line_lower or "7600" in line_lower or "7700" in line_lower or "7800" in line_lower or "7900" in line_lower:
        return "rx7000"
    if "ellesmere" in line_lower or "polaris" in line_lower or "rx 5" in line_lower:
        return "rx500"
    if "vega" in line_lower:
        return "vega"
    return "generic"


def detect_nvidia_series(lspci_line):
    """Detect if NVIDIA GPU is Kepler (last macOS-supported generation)."""
    line_lower = lspci_line.lower()
    kepler_ids = ["gk104", "gk106", "gk107", "gk110", "gk208",
                  "gtx 6", "gtx 7", "gt 7", "gt 6"]
    for kid in kepler_ids:
        if kid in line_lower:
            return "kepler"
    return "generic"


def pretty_branch(branch, desc, perf, warnings):
    """Format branch info for display."""
    lines = [
        f"GPU Strategy: Branch {branch}",
        f"Method: {desc}",
        f"Expected Performance: {perf}",
    ]
    if warnings:
        lines.append(f"\n⚠️  {warnings}")
    return "\n".join(lines)


def run():
    """Main Calamares entry point."""
    script = "/opt/macnix/scripts/phase2-gpu-detect.sh"
    profile_path = "/etc/macnix/gpu-profile.json"

    os.makedirs("/etc/macnix", exist_ok=True)

    libcalamares.utils.debug("Running GPU detection...")

    try:
        result = subprocess.run(
            ["bash", script, profile_path],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            libcalamares.utils.warning(f"GPU detect stderr: {result.stderr}")
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        # Script not installed yet — run inline detection
        libcalamares.utils.debug(f"Running inline GPU detection (reason: {e})")
        result = subprocess.run(
            ["lspci", "-nn"],
            capture_output=True, text=True
        )
        output = result.stdout
        lines = output.splitlines()

        # Parse GPU devices
        gpus = []
        for line in lines:
            if "VGA" in line or "3D controller" in line or "Display controller" in line:
                gpu = {"line": line, "vid": "", "did": ""}
                # Extract vendor:device IDs like [1002:67df]
                import re
                match = re.search(r'\[([0-9a-f]{4}):([0-9a-f]{4})\]', line, re.I)
                if match:
                    gpu["vid"] = match.group(1)
                    gpu["did"] = match.group(2)

                if "1002" in line:
                    gpu["vendor"] = "amd"
                    gpu["series"] = detect_gpu_series(line)
                elif "10de" in line:
                    gpu["vendor"] = "nvidia"
                    gpu["series"] = detect_nvidia_series(line)
                elif "8086" in line:
                    gpu["vendor"] = "intel"
                    gpu["series"] = "generic"
                else:
                    gpu["vendor"] = "unknown"
                    gpu["series"] = "generic"
                gpus.append(gpu)

        # Determine branch and target GPU
        branch = "D"
        desc = "Software Rendering"
        perf = "15-30%"
        warnings = ""
        target_gpu_idx = 0
        macos_target = "ventura"

        amd_gpus = [i for i, g in enumerate(gpus) if g["vendor"] == "amd"]
        nvidia_gpus = [i for i, g in enumerate(gpus) if g["vendor"] == "nvidia"]
        intel_gpus = [i for i, g in enumerate(gpus) if g["vendor"] == "intel"]

        if amd_gpus:
            target_gpu_idx = amd_gpus[0]
            gpu = gpus[target_gpu_idx]
            if len(gpus) > 1:
                branch = "A"
            else:
                branch = "E"
                warnings = "Single-GPU mode: Linux display stops when macOS starts"
            info = BRANCH_INFO[branch]
            desc = info["desc"]
            perf = info["perf"]
            rec = MACOS_RECOMMENDATIONS.get(("amd", gpu["series"]),
                                             MACOS_RECOMMENDATIONS[("amd", "generic")])
            macos_target = rec[0]
        elif nvidia_gpus:
            target_gpu_idx = nvidia_gpus[0]
            gpu = gpus[target_gpu_idx]
            series = gpu["series"]
            if series == "kepler":
                if len(gpus) > 1:
                    branch = "B"
                else:
                    branch = "E"
                info = BRANCH_INFO[branch]
                desc = info["desc"]
                perf = info["perf"]
            else:
                branch = "D"
                desc = "Software Fallback (modern NVIDIA)"
                perf = "15-30%"
                warnings = "Modern NVIDIA GPUs have no macOS driver support"
            rec = MACOS_RECOMMENDATIONS.get(("nvidia", series),
                                             MACOS_RECOMMENDATIONS[("nvidia", "generic")])
            macos_target = rec[0]
        elif intel_gpus:
            target_gpu_idx = intel_gpus[0]
            branch = "C"
            info = BRANCH_INFO["C"]
            desc = info["desc"]
            perf = info["perf"]
            rec = MACOS_RECOMMENDATIONS[("intel", "generic")]
            macos_target = rec[0]
        else:
            rec = MACOS_RECOMMENDATIONS[("none", "none")]
            macos_target = rec[0]

        # Detect CPU vendor
        try:
            with open("/proc/cpuinfo") as f:
                cpuinfo = f.read()
            cpu_vendor = "amd" if "AuthenticAMD" in cpuinfo else "intel"
        except Exception:
            cpu_vendor = "intel"

        # Get total RAM
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal"):
                        ram_kb = int(line.split()[1])
                        total_ram_gb = ram_kb // (1024 * 1024)
                        break
        except Exception:
            total_ram_gb = 16

        profile = {
            "branch": branch,
            "branch_desc": desc,
            "perf_range": perf,
            "warnings": warnings,
            "macos_target": macos_target,
            "gpu_count": len(gpus),
            "gpus": gpus,
            "target_gpu_idx": target_gpu_idx,
            "cpu_vendor": cpu_vendor,
            "total_ram_gb": total_ram_gb,
        }
        with open(profile_path, "w") as f:
            json.dump(profile, f, indent=2)

    # Read the profile
    try:
        with open(profile_path) as f:
            profile = json.load(f)
    except Exception as e:
        return (f"GPU detection failed: {e}", f"Could not read {profile_path}")

    # Store in global storage for other modules
    libcalamares.globalstorage.insert("macnix_gpu_profile", profile_path)
    libcalamares.globalstorage.insert("macnix_branch", profile["branch"])
    libcalamares.globalstorage.insert("macnix_macos_target",
                                      profile.get("macos_target", "sonoma"))

    # Progress message for the install slideshow
    branch = profile["branch"]
    macos_target = str(profile.get("macos_target", "sonoma")).capitalize()
    perf = profile.get("perf_range", "")
    branch_desc = profile.get("branch_desc", "")

    libcalamares.utils.debug(
        f"MacNix GPU Profiler: Branch {branch} ({branch_desc}), "
        f"Target: macOS {macos_target}, Performance: {perf}"
    )

    # Log results
    libcalamares.utils.debug(
        pretty_branch(
            profile["branch"],
            profile.get("branch_desc", ""),
            profile.get("perf_range", ""),
            profile.get("warnings", "")
        )
    )

    return None  # Success
