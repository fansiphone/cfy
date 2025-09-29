#!/bin/bash

# cfy - Cloudflare IP V2Ray/VLESS Node Generator
# Modified based on https://github.com/byJoey/cfy
# Modifications: Added self-optimized source; Custom naming; Save all nodes to jd.txt (overwrite)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
    local missing=()
    local cmds=(jq curl base64 shuf grep sed awk realpath)
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
        echo "Please install them using: apt update && apt install -y jq curl coreutils grep sed gawk realpath"
        exit 1
    fi
}

# Function to generate random IP from CIDR (IPv4 only)
random_ip_from_cidr() {
    local cidr="$1"
    IFS='/' read -r ip mask <<< "$cidr"
    IFS='.' read -r a b c d <<< "$ip"
    local ipint=$((a * 16777216 + b * 65536 + c * 256 + d))
    local shift=$((32 - mask))
    local netmask=$(((0xFFFFFFFF << shift) & 0xFFFFFFFF))
    local network=$((ipint & netmask))
    local host_bits=$(((1 << shift) - 1))
    local num_hosts=$((host_bits - 1))
    if (( num_hosts <= 0 )); then
        return 1
    fi
    local offset=$((1 + (RANDOM % num_hosts)))
    local newint=$((network + offset))
    printf "%d.%d.%d.%d" $((newint >> 24)) $(((newint >> 16) & 255)) $(((newint >> 8) & 255)) $((newint & 255))
}

# Get template from /etc/sing-box/url.txt (first vmess:// line)
get_template() {
    local template_file="/etc/sing-box/url.txt"
    if [ -s "$template_file" ]; then
        template=$(grep -m1 '^vmess://' "$template_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    if [ -z "$template" ] || [[ ! "$template" =~ ^vmess:// ]]; then
        echo -e "${YELLOW}No valid VMess template found at $template_file. Please provide one.${NC}"
        read -p "Paste the template link (vmess://...): " template
        template=$(echo "$template" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$template" ] || [[ ! "$template" =~ ^vmess:// ]]; then
            echo -e "${RED}Invalid template provided. Exiting.${NC}"
            exit 1
        fi
    fi
    # Validate
    local base64_part="${template#vmess://}"
    if ! echo "$base64_part" | base64 -d >/dev/null 2>&1; then
        echo -e "${RED}Invalid base64 in template. Exiting.${NC}"
        exit 1
    fi
    if ! echo "$base64_part" | base64 -d | jq . >/dev/null 2>&1; then
        echo -e "${RED}Invalid JSON in template. Exiting.${NC}"
        exit 1
    fi
}

# Generate node: only modify ps and add, keep everything else unchanged
generate_node() {
    local add="$1"
    local ps="$2"
    local base64_part="${template#vmess://}"
    local decoded=$(echo "$base64_part" | base64 -d)
    local new_json=$(echo "$decoded" | jq --arg add "$add" --arg ps "$ps" '.add = $add | .ps = $ps')
    local new_base64=$(echo "$new_json" | base64 -w 0)
    echo "vmess://$new_base64"
}

# Main generation logic
generate_all_nodes() {
    local output=""
    local jd_file="$(pwd)/jd.txt"

    # 1) Cloudflare 官方 - IPv4 only, generate 10 random IPs
    echo -e "${GREEN}Generating from Cloudflare Official IPs...${NC}"
    local cidrs=$(curl -s https://www.cloudflare.com/ips-v4)
    local num_generated=0
    if [ -n "$cidrs" ]; then
        cidrs=$(echo "$cidrs" | tr ' ' '\n')
        for i in $(seq 1 20); do  # Max attempts to get 10
            if [ $num_generated -ge 10 ]; then
                break
            fi
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
        echo -e "${GREEN}Generated $num_generated official nodes.${NC}"
    else
        echo -e "${YELLOW}Failed to fetch official CIDRs.${NC}"
    fi

    # 2) 云优选 - IPv4 only, parse HTML table
    echo -e "${GREEN}Generating from 云优选 IPs...${NC}"
    local html=$(curl -s https://api.uouin.com/cloudflare.html)
    local count=0
    if [ -n "$html" ]; then
        # Parse table for operator and IP
        local opt_lines=$(echo "$html" | awk -F'|' '/电信|联通|移动|多线/ {for(i=1;i<=NF;i++) gsub(/^[ \t]+|[ \t]+$/, "", $i); if($3 ~ /^(电信|联通|移动|多线)$/ && $4 ~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) print $3 " " $4}')
        if [ -n "$opt_lines" ]; then
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
        else
            echo -e "${YELLOW}Unable to parse optimized IPs.${NC}"
        fi
    else
        echo -e "${YELLOW}Failed to fetch optimized IPs.${NC}"
    fi

    # 3) 自优选 - From custom txt, each line as IP or domain
    echo -e "${GREEN}Generating from 自优选 source...${NC}"
    local self_content=$(curl -s http://nas.848588.xyz:18080/output/abc/dy/cf.txt)
    local self_count=0
    if [ -n "$self_content" ]; then
        local self_adds=$(echo "$self_content" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | head -50)
        if [ -n "$self_adds" ]; then
            while IFS= read -r add; do
                local ps="vpsus-自选[$add]"
                local node=$(generate_node "$add" "$ps")
                if [ -n "$node" ]; then
                    output+="$node"$'\n'
                    ((self_count++))
                fi
            done <<< "$self_adds"
            echo -e "${GREEN}Generated $self_count self-optimized nodes.${NC}"
        else
            echo -e "${YELLOW}No valid adds in self-optimized source.${NC}"
        fi
    else
        echo -e "${YELLOW}Failed to fetch self-optimized source.${NC}"
    fi

    # Output and save to jd.txt (overwrite)
    if [ -n "$output" ]; then
        echo -e "${GREEN}All generated nodes:${NC}"
        echo -e "$output"
        echo "$output" > "$jd_file"
        if command -v realpath >/dev/null 2>&1; then
            echo -e "${GREEN}Results saved to $(realpath "$jd_file")${NC}"
        else
            echo -e "${GREEN}Results saved to $jd_file${NC}"
        fi
    else
        echo -e "${RED}No nodes generated.${NC}"
    fi
}

# Header
echo "=================================================="
echo " 节点优选生成器 (cfy) - Modified"
echo " (适配老王的4合一sing-box)"
echo ""
echo " 作者: byJoey (modified)"
echo "=================================================="

# Run main
check_dependencies
get_template
generate_all_nodes
