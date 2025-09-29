#!/bin/bash

# cfy - Cloudflare IP V2Ray/VLESS Node Generator
# Modified Version based on analysis
# Changes as per user requirements

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
    local missing=""
    for cmd in jq curl base64 mktemp shuf grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        echo -e "${YELLOW}Missing dependencies: $missing${NC}"
        echo "Please install them using: apt update && apt install -y jq curl coreutils grep sed base64"
        exit 1
    fi
}

# Function to generate random IP from CIDR
random_ip_from_cidr() {
    local cidr="$1"
    IFS='/' read ip mask <<< "$cidr"
    IFS='.' read a b c d <<< "$ip"
    local ipint=$((a * 16777216 + b * 65536 + c * 256 + d))
    local netmask=$((0xFFFFFFFF << (32 - mask) & 0xFFFFFFFF))
    local network=$((ipint & netmask))
    local broadcast=$((network | (0xFFFFFFFF ^ netmask)))
    local num_hosts=$((broadcast - network - 1))
    if (( num_hosts <= 0 )); then
        echo "Invalid CIDR: $cidr" >&2
        return 1
    fi
    local offset=$(( (RANDOM % num_hosts) + 1 ))
    local newint=$((network + offset))
    echo $((newint >> 24)).$(((newint >> 16) & 255)).$(((newint >> 8) & 255)).$((newint & 255))
}

# Get template
get_template() {
    template_file="/etc/sing-box/url.txt"
    if [ -s "$template_file" ]; then
        template=$(cat "$template_file")
    else
        echo -e "${YELLOW}No template file found at $template_file. Please provide a VMess template link.${NC}"
        read -p "Paste the template link (vmess://...): " template
        if [ -z "$template" ]; then
            echo -e "${RED}No template provided. Exiting.${NC}"
            exit 1
        fi
    fi
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

    # 1) Cloudflare 官方 (手动优选)
    echo -e "${GREEN}Generating from Cloudflare Official IPs...${NC}"
    local cidrs=$(curl -s https://www.cloudflare.com/ips-v4)
    if [ -z "$cidrs" ]; then
        echo -e "${RED}Failed to fetch official CIDRs.${NC}"
    else
        for i in {1..10}; do # Default 10 IPs
            local cidr=$(echo "$cidrs" | shuf -n 1)
            local ip=$(random_ip_from_cidr "$cidr")
            if [ -n "$ip" ]; then
                local ps="vpsus-CF$ip"
                local node=$(generate_node "$ip" "$ps")
                if [ -n "$node" ]; then
                    output+="$node\n"
                fi
            fi
        done
    fi

    # 2) 云优选
    echo -e "${GREEN}Generating from 云优选 IPs...${NC}"
    local html=$(curl -s https://api.uouin.com/cloudflare.html)
    if [ -z "$html" ]; then
        echo -e "${RED}Failed to fetch optimized IPs.${NC}"
    else
        local opt_lines=$(echo "$html" | grep -oE '- (电信|联通|移动|多线): [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sed 's/- //; s/: / /')
        if [ -z "$opt_lines" ]; then
            echo -e "${RED}Unable to parse optimized IPs.${NC}"
        else
            while read -r line; do
                local operator=$(echo "$line" | awk '{print $1}')
                local ip=$(echo "$line" | awk '{print $2}')
                local ps="vpsus-${operator}${ip}"
                local node=$(generate_node "$ip" "$ps")
                if [ -n "$node" ]; then
                    output+="$node\n"
                fi
            done <<< "$opt_lines"
        fi
    fi

    # 3) 自优选
    echo -e "${GREEN}Generating from 自优选 source...${NC}"
    local self_content=$(curl -s http://nas.848588.xyz:18080/output/abc/dy/cf.txt)
    if [ -z "$self_content" ]; then
        echo -e "${RED}Failed to fetch self-optimized source.${NC}"
    else
        local self_adds=$(echo "$self_content" | grep -v '^$' | grep -E '^[0-9a-zA-Z.:-]+$') # Filter valid IP/domain lines
        if [ -z "$self_adds" ]; then
            echo -e "${RED}No valid adds in self-optimized source.${NC}"
        else
            while read -r add; do
                local ps="vpsus-自选$add"
                local node=$(generate_node "$add" "$ps")
                if [ -n "$node" ]; then
                    output+="$node\n"
                fi
            done <<< "$self_adds"
        fi
    fi

    # Output and save
    if [ -n "$output" ]; then
        echo -e "${GREEN}Generated nodes:${NC}"
        echo -e "$output"
        echo -e "$output" > "$jd_file" # Overwrite jd.txt
        echo -e "${GREEN}Results saved to $(realpath "$jd_file")${NC}"
    else
        echo -e "${RED}No nodes generated.${NC}"
    fi
}

# Run
check_dependencies
get_template
generate_all_nodes
