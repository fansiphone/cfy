#!/bin/bash

INSTALL_PATH="/usr/local/bin/cfy"

if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装 [cfy 节点优选生成器]..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 安装需要管理员权限。请使用 'curl ... | sudo bash' 或 'sudo bash <(curl ...)' 命令来运行。"
        exit 1
    fi
    
    echo "正在将脚本写入到 $INSTALL_PATH..."
    
    # 智能判断执行模式
    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" || "$(basename "$0")" == "-bash" ]]; then
        # 管道模式: curl ... | bash
        # 脚本内容在标准输入 (fd/0)
        if ! cat /proc/self/fd/0 > "$INSTALL_PATH"; then
            echo "❌ 写入脚本失败 (管道模式)，请重试。"
            exit 1
        fi
    else
        # 文件模式: bash cfy.sh 或 bash <(curl ...)"
        # 脚本内容在 $0 所指向的文件路径
        if ! cp "$0" "$INSTALL_PATH"; then
            echo "❌ 复制脚本失败 (文件模式)，请重试。"
            exit 1
        fi
    fi

    if [ $? -eq 0 ]; then
        chmod +x "$INSTALL_PATH"
        echo "✅ 安装成功! 您现在可以随时随地运行 'cfy' 命令。"
        echo "---"
        echo "首次运行..."
        exec "$INSTALL_PATH"
    else
        echo "❌ 安装后赋权失败, 请检查权限。"
        exit 1
    fi
    exit 0
fi

# --- 主程序从这里开始 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_deps() {
    for cmd in jq curl base64 grep sed mktemp shuf; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误: 命令 '$cmd' 未找到. 请先安装它.${NC}"
            exit 1
        fi
    done
}

get_all_optimized_ips() {
    local url_v4="https://www.wetest.vip/page/cloudflare/address_v4.html"
    local url_v6="https://www.wetest.vip/page/cloudfront/address_v6.html"
    local self_select_url="http://nas.848588.xyz:18080/output/abc/dy/cf.txt"
    
    echo -e "${YELLOW}请选择 IP 地址来源:${NC}"
    echo "  1) Cloudflare 官方 (手动优选)"
    echo "  2) 云优选"
    echo "  3) 自优选模式"
    
    local ip_source_choice
    local use_optimized_ips=false
    local use_self_select=false
    
    while true; do
        read -p "请输入选项编号 (1-3): " ip_source_choice
        if [[ "$ip_source_choice" == "1" ]]; then
            break
        elif [[ "$ip_source_choice" == "2" ]]; then
            use_optimized_ips=true
            break
        elif [[ "$ip_source_choice" == "3" ]]; then
            use_self_select=true
            break
        else
            echo -e "${RED}无效的输入, 请重试.${NC}"
        fi
    done
    
    if $use_self_select; then
        echo -e "${YELLOW}正在从自选链接获取 IP 地址...${NC}"
        ips=$(curl -s "$self_select_url")
        if [ -z "$ips" ]; then
            echo -e "${RED}无法从自选链接获取 IP 地址.${NC}"
            return 1
        fi
        
        # 处理获取的数据，每行一个
        mapfile -t ip_list <<< "$ips"
        # 创建等长的isp_list数组，填充"自选"
        isp_list=()
        for ((i=0; i<${#ip_list[@]}; i++)); do
            isp_list+=("自选")
        done
        
        echo -e "${GREEN}成功获取 ${#ip_list[@]} 个自选 IP 地址.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}正在合并获取所有优选 IP (IPv4 & IPv6)...${NC}"
    
    local paired_data_file
    paired_data_file=$(mktemp)
    trap 'rm -f "$paired_data_file"' EXIT

    parse_url() {
        local url="$1"
        local type_desc="$2"
        echo -e "  -> 正在获取 ${type_desc} 列表..."
        local html_content=$(curl -s "$url")
        if [ -z "$html_content" ]; then
            echo -e "${RED}  -> 获取 ${type_desc} 列表失败!${NC}"
            return
        fi
        local table_rows=$(echo "$html_content" | tr -d '\n\r' | sed 's/<tr>/\n&/g' | grep '^<tr>')
        local ips=$(echo "$table_rows" | sed -n 's/.*data-label=\"优选地址\">$$[^<]*$$<.*/\1/p')
        local isps=$(echo "$table_rows" | sed -n 's/.*data-label=\"线路名称\">$$[^<]*$$<.*/\1/p')
        paste -d' ' <(echo "$ips") <(echo "$isps") >> "$paired_data_file"
    }

    if $use_optimized_ips; then
        parse_url "$url_v4" "IPv4"
        parse_url "$url_v6" "IPv6"
    else
        parse_url "$url_v4" "IPv4"
    fi

    if ! [ -s "$paired_data_file" ]; then
        echo -e "${RED}无法从任何来源解析出优选 IP 地址.${NC}"
        return 1
    fi

    declare -g -a ip_list isp_list
    local shuffled_pairs
    mapfile -t shuffled_pairs < <(shuf "$paired_data_file")
    for pair in "${shuffled_pairs[@]}"; do
        ip_list+=("$(echo "$pair" | cut -d' ' -f1)")
        isp_list+=("$(echo "$pair" | cut -d' ' -f2-)")
    done
    if [ ${#ip_list[@]} -eq 0 ]; then
        echo -e "${RED}解析成功, 但未找到任何有效的 IP 地址.${NC}"
        return 1
    fi
    echo -e "${GREEN}成功合并获取 ${#ip_list[@]} 个优选 IP 地址, 列表已随机打乱.${NC}"
    return 0
}

generate_node_name() {
    local ip=$1
    local isp_name=$2
    local mode=$3
    
    case $mode in
        "official")
            echo "$ip-CFvpsus"
            ;;
        "cloud")
            echo "${isp_name}${ip}-vpsus"
            ;;
        "self")
            echo "${ip}-自选vpsus"
            ;;
        *)
            echo "${ip}-vpsus"
            ;;
    esac
}

main() {
    local url_file="/etc/sing-box/url.txt"
    declare -a valid_urls valid_ps_names
    
    echo -e "${GREEN}=================================================="
    echo -e " 节点优选生成器 (cfy)"
    echo -e " (适配老王的4合一sing-box)"
    echo -e " "
    echo -e " 作者: byJoey (github.com/byJoey)"
    echo -e " 博客: joeyblog.net"
    echo -e " TG群: t.me/+ft-zI76oovgwNmRh"
    echo -e "==================================================${NC}"
    echo ""

    if [ -f "$url_file" ]; then
        mapfile -t urls < "$url_file"
        for url in "${urls[@]}"; do
            decoded_json=$(echo "${url#\"vmess://\"}" | base64 -d 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$ps" ]; then
                    valid_urls+=("$url")
                    valid_ps_names+=("$ps")
                fi
            fi
        done
    fi

    local selected_url
    if [ ${#valid_urls[@]} -gt 0 ]; then
        if [ ${#valid_urls[@]} -eq 1 ]; then
            selected_url=${valid_urls[0]}
            echo -e "${YELLOW}检测到只有一个有效节点, 已自动选择: ${valid_ps_names[0]}${NC}"
        else
            echo -e "${YELLOW}请选择一个节点作为:${NC}"
            for i in "${!valid_ps_names[@]}"; do
                printf "%3d) %s\n" "$((i+1))" "${valid_ps_names[$i]}"
            done
            local choice
            while true; do
                read -p "请输入选项编号 (1-${#valid_urls[@]}): " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#valid_urls[@]} ]; then
                    selected_url=${valid_urls[$((choice-1))]}"
                    break
                else
                    echo -e "${RED}无效的输入, 请重试.${NC}"
                fi
            done
        fi
    else
        echo -e "${YELLOW}在 $url_file 中未找到有效节点.${NC}"
        while true; do
            read -p "请手动粘贴一个 vmess:// 链接作为: " selected_url
            if [[ "$selected_url" != vmess://* ]]; then
                echo -e "${RED}格式错误, 必须以 vmess:// 开头.${NC}"
                continue
            fi
            decoded_json=$(echo "${selected_url#\"vmess://\"}" | base64 -d 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$decoded_json" ]; then
                echo -e "${RED}无法解码链接, 请检查链接是否完整有效.${NC}"
                continue
            fi
            ps_check=$(echo "$decoded_json" | jq -e .ps >/dev/null 2>&1)
            if [ $? -ne 0 ]; then
                echo -e "${RED}解码成功, 但JSON内容不完整或格式错误. 请重试.${NC}"
                continue
            fi
            break
        done
    fi

    local base64_part=${selected_url#\"vmess://\"}
    local original_json=$(echo "$base64_part" | base64 -d)
    local original_ps=$(echo "$original_json" | jq -r .ps)
    echo -e "${GREEN}已选择: $original_ps${NC}"
    
    echo -e "${YELLOW}请选择要使用的 IP 地址来源:${NC}"
    echo "  1) Cloudflare 官方 (手动优选)"
    echo "  2) 云优选"
    echo "  3) 自优选模式"
    
    local ip_source_choice
    local mode=""
    local num_to_generate=0
    
    while true; do
        read -p "请输入选项编号 (1-3): " ip_source_choice
        if [[ "$ip_source_choice" == "1" ]]; then
            mode="official"
            echo -e "${YELLOW}正在从 Cloudflare 官网获取 IPv4 地址列表...${NC}"
        cloudflare_ips=$(curl -s https://www.cloudflare.com/ips-v4)
        if [ -z "$cloudflare_ips" ]; then
            echo -e "${RED}无法获取 Cloudflare IP 列表.${NC}"
            exit 1
        fi
        mapfile -t ip_list <<< "$cloudflare_ips"
        isp_list=()
        for ((i=0; i<${#ip_list[@]}; i++)); do
            isp_list+=("CF官方")
        done
        echo -e "${GREEN}成功获取 ${#ip_list[@]} 个 Cloudflare IPv4 地址段.${NC}"
        
        while true; do
            read -p "请输入您想生成的 URL 数量: " num_to_generate
            if [[ "$num_to_generate" =~ ^[0-9]+$ ]] && [ "$num_to_generate" -gt 0 ]; then
                break
            else
                echo -e "${RED}请输入一个有效的正整数.${NC}"
            fi
        done
        break
    elif [[ "$ip_source_choice" == "2" ]]; then
        mode="cloud"
        get_all_optimized_ips || exit 1
        num_to_generate=${#ip_list[@]}
        break
    elif [[ "$ip_source_choice" == "3" ]]; then
        mode="self"
        get_all_optimized_ips || exit 1
        num_to_generate=${#ip_list[@]}
        break
    else
        echo -e "${RED}无效的输入, 请重试.${NC}"
    fi
    done
    
    if [ $num_to_generate -gt 0 ]; then
        # 清空 jd.txt
        > jd.txt
        
        echo "---"
        echo -e "${YELLOW}生成的新节点链接如下:${NC}"
        
        for ((i=0; i<$num_to_generate; i++)); do
            local current_ip=""
            local isp_name=""
            
            if [ "$mode" == "official" ]; then
                # 对于官方模式，随机选择IP段
                local random_index=$((RANDOM % ${#ip_list[@]}))
            current_ip=${ip_list[$random_index]}
            isp_name=${isp_list[$random_index]}
            else
                current_ip=${ip_list[$i]}
                isp_name=${isp_list[$i]}
            fi
            
            # 生成新的节点名称
            local new_ps=$(generate_node_name "$current_ip" "$isp_name" "$mode")
            
            local modified_json=$(echo "$original_json" | jq --arg new_add "$current_ip" --arg new_ps "$new_ps" '.add = $new_add | .ps = $new_ps')
            local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
            local new_url="vmess://${new_base64}"
            
            # 输出到屏幕
            echo "$new_url"
            
            # 保存到 jd.txt
            echo "$new_url" >> jd.txt
        done
        
        echo "---"
        echo -e "${GREEN}共 ${num_to_generate} 个链接已生成完毕.${NC}"
        echo -e "${GREEN}所有节点已保存到 jd.txt${NC}"
    else
        echo -e "${RED}没有可用的 IP 地址用于生成节点.${NC}"
    fi
}

check_deps
main
