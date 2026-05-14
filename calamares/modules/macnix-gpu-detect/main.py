#!/usr/bin/env python3
# MacNix Calamares Module — GPU Detection
# Runs Phase 2 GPU detection logic and presents results to user
import os
import subprocess
import json
import libcalamares

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
    # Run the GPU detection script
    script = "/opt/macnix/scripts/phase2-gpu-detect.sh"
    profile_path = "/etc/macnix/gpu-profile.json"
    
    # Ensure target directory exists
    os.makedirs("/etc/macnix", exist_ok=True)
    
    libcalamares.utils.debug("Running GPU detection...")
    
    try:
        result = subprocess.run(
            ["bash", script, profile_path],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            libcalamares.utils.warning(f"GPU detect stderr: {result.stderr}")
    except FileNotFoundError:
        # Script not installed yet — run inline detection
        libcalamares.utils.debug("Running inline GPU detection")
        result = subprocess.run(
            ["lspci", "-nn"],
            capture_output=True, text=True
        )
        # Minimal inline detection
        output = result.stdout
        has_amd = "1002" in output and ("VGA" in output or "3D" in output)
        has_nvidia = "10de" in output
        has_intel = "8086" in output and "VGA" in output
        
        branch = "D"
        desc = "Software Rendering"
        perf = "15-30%"
        warnings = ""
        
        if has_amd:
            branch, desc, perf = "A", "AMD VFIO Passthrough", "95-100%"
        elif has_nvidia:
            branch, desc, perf = "D", "Software Fallback (modern NVIDIA)", "15-30%"
            warnings = "Modern NVIDIA GPUs have no macOS driver support"
        elif has_intel:
            branch, desc, perf = "C", "Intel iGPU GVT-g", "60-80%"
        
        profile = {
            "branch": branch, "branch_desc": desc,
            "perf_range": perf, "warnings": warnings,
            "macos_target": "sonoma", "gpu_count": 1,
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
    libcalamares.globalstorage.insert("macnix_macos_target", profile.get("macos_target", "sonoma"))
    
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
