#!/usr/bin/env bash
# MacNix - GPU Database
# Contains device ID lists for GPU classification

# Kepler device IDs (subset - key consumer/workstation cards)
KEPLER_IDS="1180 1183 1185 1187 1188 1189 118e 1193 0fc0 0fc1 0fc2 0fc6 0fd1 0fd2 0fd4 0fd5 0fe0 0fe1 0fe4 0fe9 0fea 0ffa 0ffe 1001 1004 1005 1007 1008 100a 100c 1280 1281 1282 1284 1286 1287"

is_kepler_gpu() {
    local id="${1,,}"
    [[ " $KEPLER_IDS " == *" $id "* ]]
}

get_nvidia_generation() {
    local device_id="${1,,}"
    if is_kepler_gpu "$device_id"; then echo "kepler"; return; fi
    local n=$((16#$device_id))
    if (( n >= 0x0F00 && n <= 0x13FF )); then echo "kepler"
    elif (( n >= 0x1340 && n <= 0x179F )); then echo "maxwell"
    elif (( n >= 0x1B00 && n <= 0x1DFF )); then echo "pascal"
    elif (( n >= 0x1E00 && n <= 0x21FF )); then echo "turing"
    elif (( n >= 0x2200 && n <= 0x25FF )); then echo "ampere"
    elif (( n >= 0x2600 && n <= 0x28FF )); then echo "ada"
    else echo "unknown"; fi
}

supports_gvtg() {
    local id="${1,,}"
    case "$id" in
        191?|192?|193?|59??|3e9?|9b??) return 0 ;;
        *) return 1 ;;
    esac
}
