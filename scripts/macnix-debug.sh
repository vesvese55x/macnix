#!/usr/bin/env bash
# MacNix Debug & Recovery Menu
# Can be launched from the TTY or host terminal

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}               MacNix Debug Menu                  ${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) View VM Status & Logs"
    echo "  2) View GPU Passthrough Status"
    echo "  3) Restart macOS VM"
    echo "  4) Restart Looking Glass Display"
    echo "  5) Edit VM Configuration"
    echo "  6) Re-run First Boot Setup"
    echo "  7) Return to Desktop / Display Manager"
    echo "  8) Exit Debug Menu"
    echo ""
    echo -e "${CYAN}Shortcut reminder: Right Ctrl + F2 drops to this TTY${NC}"
    echo ""
    read -p "Select an option [1-8]: " choice

    case $choice in
        1)
            echo -e "\n${BOLD}VM Status:${NC}"
            systemctl status macnix-vm.service --no-pager || true
            echo -e "\n${BOLD}Recent VM Logs:${NC}"
            journalctl -u macnix-vm.service -n 20 --no-pager
            read -p "Press Enter to return..."
            ;;
        2)
            echo -e "\n${BOLD}GPU Passthrough Status:${NC}"
            lspci -nnk | grep -iE 'vga|3d|display' -A 3
            echo -e "\n${BOLD}VFIO Devices:${NC}"
            ls -l /dev/vfio/ || echo "No VFIO devices active."
            read -p "Press Enter to return..."
            ;;
        3)
            echo -e "\nRestarting macOS VM..."
            sudo systemctl restart macnix-vm.service
            echo -e "${GREEN}VM Restarted.${NC}"
            sleep 2
            ;;
        4)
            echo -e "\nRestarting Looking Glass..."
            sudo systemctl restart macnix-looking-glass.service
            echo -e "${GREEN}Display Restarted.${NC}"
            sleep 2
            ;;
        5)
            sudo nano /etc/macnix/vm.conf
            ;;
        6)
            echo -e "\nRe-running hardware setup..."
            sudo rm -f /etc/macnix/.firstboot-done
            sudo systemctl restart macnix-firstboot.service
            echo -e "${GREEN}Setup complete.${NC}"
            sleep 2
            ;;
        7)
            echo -e "\nRestarting Display Manager..."
            for dm in gdm3 sddm lightdm; do
                if systemctl is-enabled "$dm" &>/dev/null; then
                    sudo systemctl restart "$dm"
                    break
                fi
            done
            ;;
        8)
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            sleep 1
            ;;
    esac
    show_menu
}

# Ensure root privileges for systemctl commands if needed
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Warning: Some options require root privileges.${NC}"
fi

show_menu
