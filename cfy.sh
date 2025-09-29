#!/bin/bash

# cfy - Cloudflare IP V2Ray/VLESS Node Generator
# Modified Version based on analysis
# Changes as per user requirements
# Fixed: Template validation, 云优选 parsing with corrected awk columns, random IP calculation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
    local missing=""
    for cmd in jq curl base64 shuf grep sed awk realpath; do
        if ! command -v "$cmd" &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        echo -e "${YELLOW}Missing dependencies: $missing${NC}"
        echo "Please install them using: apt update && apt install -y jq curl coreutils grep sed gawk realpath"
        exit 1
    fi
}

# Function to generate random IP from CIDR
random_ip_from_cidr() {
    local cidr="$1"
    IFS='/' read -r ip mask <<< "$cidr"
    IFS='.' read -r a b c d <<< "$ip"
    local ipint=$((a * 16777216 + b * 65536 + c * 256 + d))
    local shift=$((32 - mask))
    local netmask=$(((0xFFFFFFFF << shift) & 0xFFFFFFFF))
    local network=$((ipint & netmask))
    local host_bits=$(((1 << shift) - 1))
    local broadcast=$((network | host_bits))
    local num_hosts=$((host_bits - 1))
    if (( num_hosts <= 0 )); then
        echo "Invalid CIDR: $cidr" >&2
        return 1
    fi
    local offset=$((1 + (RANDOM % num_hosts)))
    local newint=$((network + offset))
    printf "%d.%d.%d.%d\n" $((newint >> 24)) $(((newint >> 16) & 255)) $(((newint >> 8) & 255)) $((newint & 255))
}

# Get template with validation
get_template() {
    local valid_template=""
    template_file="/etc/sing-box/url.txt"
    if [ -s "$template_file" ]; then
        valid_template=$(grep -m1 'vmess://' "$template_file" 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi
    while [ -z "$valid_template" ]; do
        echo -e "${YELLOW}No valid VMess template found. Please provide a VMess template link.${NC}"
        read -p "Paste the template link (vmess://...): " valid_template
    done
    # Validate
    local base64_part="${valid_template#vmess://}"
    local decoded=$(echo "$base64_part" | base64 -d 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$decoded" ]; then
        echo -e "${RED}Invalid template: base64 decode failed.${NC}"
        valid_template=""
        continue
    fi
    local test_json=$(echo "$decoded" | jq . 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Invalid template: not valid JSON.${NC}"
        valid_template=""
        continue
    fi
    template="$valid_template"
}

# Generate node from template
generate_node() {
    local add="$1"
    local ps="$2"
    local base64_part="${template#vmess://}"
    local decoded=$(echo "$base64_part" | base64 -d 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Invalid base64 in template.${NC}" >&2
        return 1
    fi
    local new_json=$(echo "$decoded" | jq --arg add "$add" --arg ps "$ps" '.add = $add | .ps = $ps' 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Invalid JSON in template.${NC}" >&2
        return 1
    fi
    local new_base64=$(echo "$new_json" | base64 -w 0)
    echo "vmess://$new_base64"
}

# Main generation logic
generate_all_nodes() {
    local output=""
    local jd_file="$(pwd)/jd.txt"

    # 1) Cloudflare 官方 (手动优选) - 10 IPs
    echo -e "${GREEN}Generating from Cloudflare Official IPs...${NC}"
    local cidrs=$(curl -s https://www.cloudflare.com/ips-v4)
    if [ -z "$cidrs" ]; then
        echo -e "${YELLOW}Failed to fetch official CIDRs.${NC}"
    else
        local num_generated=0
        while [ $num_generated -lt 10 ]; do
            local cidr=$(echo "$cidrs" | shuf -n 1)
            local ip=$(random_ip_from_cidr "$cidr")
            if [ -n "$ip" ]; then
                local ps="vpsus-CF[$ip]"
                local node=$(generate_node "$ip" "$ps")
                if [ -n "$node" ]; then
                    output+="$node"$'\n'
                    ((num_generated++))
                fi
            fi
        done
        if [ $num_generated -eq 0 ]; then
            echo -e "${YELLOW}No official IPs generated.${NC}"
        else
            echo -e "${GREEN}Generated $num_generated official nodes.${NC}"
        fi
    fi

    # 2) 云优选 - parse table with awk, corrected columns
    echo -e "${GREEN}Generating from 云优选 IPs...${NC}"
    local html=$(curl -s https://api.uouin.com/cloudflare.html)
    if [ -z "$html" ]; then
        echo -e "${YELLOW}Failed to fetch optimized IPs.${NC}"
    else
        local opt_lines=$(echo "$html" | awk 'BEGIN {FS="|"} NR>1 { gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $4); if ($3 ~ /^(电信|联通|移动|多线|IPV6)$/) print $3 " " $4 }')
        if [ -z "$opt_lines" ]; then
            echo -e "${YELLOW}Unable to parse optimized IPs.${NC}"
        else
            local count=0
            while IFS= read -r line; do
                local operator=$(echo "$line" | awk '{print $1}')
                local ip=$(echo "$line" | awk '{print $2}')
                if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    local ps="vpsus-${operator}[$ip]"
                    local node=$(generate_node "$ip" "$ps")
                    if [ -n "$node" ]; then
                        output+="$node"$'\n'
                        ((count++))
                    fi
                fi
            done <<< "$opt_lines"
            echo -e "${GREEN}Generated $count optimized nodes.${NC}"
        fi
    fi

    # 3) 自优选
    echo -e "${GREEN}Generating from 自优选 source...${NC}"
    local self_content=$(curl -s http://nas.848588.xyz:18080/output/abc/dy/cf.txt)
    if [ -z "$self_content" ]; then
        echo -e "${YELLOW}Failed to fetch self-optimized source.${NC}"
    else
        local self_adds=$(echo "$self_content" | grep -v '^$' | grep -E '^[0-9a-zA-Z.-]+(\.[0-9a-zA-Z.-]+)*(:[0-9]+)?$' | head -50) # Filter valid IP/domain, limit 50
        if [ -z "$self_adds" ]; then
            echo -e "${YELLOW}No valid adds in self-optimized source.${NC}"
        else
            local count=0
            while IFS= read -r add; do
                local ps="vpsus-自选[$add]"
                local node=$(generate_node "$add" "$ps")
                if [ -n "$node" ]; then
                    output+="$node"$'\n'
                    ((count++))
                fi
            done <<< "$self_adds"
            echo -e "${GREEN}Generated $count self-optimized nodes.${NC}"
        fi
    fi

    # Output and save
    if [ -n "$output" ]; then
        echo -e "${GREEN}Generated nodes:${NC}"
        echo -e "$output"
        printf '%s\n' "$output" > "$jd_file" # Overwrite jd.txt properly
        echo -e "${GREEN}Results saved to $(realpath "$jd_file")${NC}"
    else
        echo -e "${RED}No nodes generated.${NC}"
    fi
}

# Run
check_dependencies
get_template
generate_all_nodes
