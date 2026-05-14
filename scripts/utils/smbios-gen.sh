#!/usr/bin/env bash
# MacNix — SMBIOS Serial Number Generator
# Generates unique Apple-format serial numbers for OpenCore
# Uses macserial if available, otherwise generates compatible format

set -euo pipefail

MODEL="${1:-iMac19,1}"

generate_serial() {
    # Apple serials: 12 chars, format: PPP Y W SSS EEEE
    # PPP = factory, Y = year, W = week, SSS = unique, EEEE = model
    local factory="C02"
    local year_codes="CDFGHJKLMNPQRSTVWXYZ"
    local idx=$(( RANDOM % ${#year_codes} ))
    local year="${year_codes:$idx:1}"
    local week=$(printf "%01X" $(( RANDOM % 52 + 1 )))
    local unique=$(head -c3 /dev/urandom | xxd -p | tr '[:lower:]' '[:upper:]' | head -c3)
    
    # Model suffix based on SMBIOS
    local suffix
    case "$MODEL" in
        iMac19,1)     suffix="JV3F" ;;
        iMac19,2)     suffix="JV3G" ;;
        iMacPro1,1)   suffix="HX87" ;;
        MacPro7,1)    suffix="K7GF" ;;
        Macmini8,1)   suffix="JYHT" ;;
        *)            suffix=$(head -c4 /dev/urandom | xxd -p | tr '[:lower:]' '[:upper:]' | head -c4) ;;
    esac
    
    echo "${factory}${year}${week}${unique}${suffix}"
}

generate_mlb() {
    # MLB: 17 chars
    local prefix="C02"
    local body=$(head -c14 /dev/urandom | xxd -p | tr '[:lower:]' '[:upper:]' | head -c14)
    echo "${prefix}${body}"
}

generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()).upper())" 2>/dev/null || \
    cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]'
}

generate_rom() {
    head -c6 /dev/urandom | xxd -p
}

# Check if macserial is available
if command -v macserial &>/dev/null; then
    echo "Using macserial for generation"
    macserial --model "$MODEL" --generate --num 1
else
    SERIAL=$(generate_serial)
    MLB=$(generate_mlb)
    UUID=$(generate_uuid)
    ROM=$(generate_rom)
    
    cat <<EOF
{
  "model": "${MODEL}",
  "serial": "${SERIAL}",
  "mlb": "${MLB}",
  "uuid": "${UUID}",
  "rom": "${ROM}"
}
EOF
fi
