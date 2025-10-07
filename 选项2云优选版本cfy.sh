#!/bin/bash

# === 第一步：优先检测--cloud参数，直接拦截非交互模式 ===
AUTO_RUN_CLOUD=0
for arg in "$@"; do
    if [[ "$arg" == "-c" || "$arg" == "--cloud" ]]; then
        AUTO_RUN_CLOUD=1
        break
    fi
done

# 如果是非交互模式，直接执行选项2逻辑，不进入主流程
if [[ "$AUTO_RUN_CLOUD" -eq 1 ]]; then
    # 定义必要变量和函数（仅保留选项2所需逻辑）
    INSTALL_PATH="/usr/local/bin/cfy"
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'

    # 检查依赖
    check_deps() {
        for cmd in jq curl base64 grep sed mktemp shuf; do
            if ! command -v "$cmd" &> /dev/null; then
                echo -e "${RED}错误: 命令 '$cmd' 未找到. 请先安装它.${NC}"
                exit 1
            fi
        done
    }

    # 检查IP是否存在
    ip_exists() {
        local ip="$1"
        local file="$2"
        [ -f "$file" ] || return 1
        grep -qxF "$ip" "$file"
    }

    # 处理选项2核心逻辑（修复：将IP列表声明为全局变量）
    process_cloud_optimize() {
        echo -e "${YELLOW}正在获取优选 IPv4 地址...${NC}"
        
        local paired_data_file
        paired_data_file=$(mktemp)
        trap 'rm -f "$paired_data_file"' EXIT

        parse_url() {
            local url="$1"; local type_desc="$2"
            echo -e "  -> 正在获取 ${type_desc} 列表..."
            local html_content=$(curl -s "$url")
            if [ -z "$html_content" ]; then 
                echo -e "${RED}  -> 获取 ${type_desc} 列表失败!${NC}"
                return
            fi
            local table_rows=$(echo "$html_content" | tr -d '\n\r' | sed 's/<tr>/\n&/g' | grep '^<tr>')
            local ips=$(echo "$table_rows" | sed -n 's/.*data-label="优选地址">\([^<]*\)<.*/\1/p')
            local isps=$(echo "$table_rows" | sed -n 's/.*data-label="线路名称">\([^<]*\)<.*/\1/p')
            paste -d' ' <(echo "$ips") <(echo "$isps") >> "$paired_data_file"
        }

        # 从云优选页面获取IP
        local url_v4="https://www.wetest.vip/page/cloudflare/address_v4.html"
        parse_url "$url_v4" "云优选页面IPv4"

        # 从指定URL获取IP（新增功能）
        echo -e "  -> 正在从自选链接获取IP列表..."
        local self_url="http://nas.848588.xyz:18080/output/abc/dy/cf.txt"
        local self_ips=$(curl -s "$self_url")
        if [ -n "$self_ips" ]; then
            # 为这些IP添加"自选"线路标识
            echo "$self_ips" | while read -r ip; do
                if [ -n "$ip" ]; then
                    echo "$ip 自选" >> "$paired_data_file"
                fi
            done
            echo -e "  -> 成功获取自选链接IP列表"
        else
            echo -e "${YELLOW}  -> 获取自选链接IP列表失败，将仅使用云优选页面数据${NC}"
        fi

        if ! [ -s "$paired_data_file" ]; then 
            echo -e "${RED}无法从来源解析出优选 IP 地址.${NC}"
            exit 1
        fi

        # 关键修复：用declare -g声明全局变量，确保函数外可访问
        declare -g -a ip_list=() isp_list=()
        local shuffled_pairs
        # 去重并打乱顺序
        mapfile -t shuffled_pairs < <(sort -u "$paired_data_file" | shuf)
        for pair in "${shuffled_pairs[@]}"; do
            ip_list+=("$(echo "$pair" | cut -d' ' -f1)")
            isp_list+=("$(echo "$pair" | cut -d' ' -f2-)")
        done
        
        # 去重追加到ipv4.txt
        local ipv4_file="ipv4.txt"
        if [ ${#ip_list[@]} -gt 0 ]; then
            echo -e "${YELLOW}正在将新IP追加到 $ipv4_file（自动去重）...${NC}"
            local new_count=0
            
            for ip in "${ip_list[@]}"; do
                if ! ip_exists "$ip" "$ipv4_file"; then
                    echo "$ip" >> "$ipv4_file"
                    ((new_count++))
                fi
            done
            
            echo -e "${GREEN}已完成！新增 ${new_count} 个IP，$ipv4_file 中共有 $(wc -l < "$ipv4_file") 个唯一IP${NC}"
        fi
        
        if [ ${#ip_list[@]} -eq 0 ]; then 
            echo -e "${RED}解析成功, 但未找到任何有效的 IP 地址.${NC}"
            exit 1
        fi
        echo -e "${GREEN}成功获取 ${#ip_list[@]} 个优选 IP 地址, 列表已随机打乱.${NC}"
    }

    # 生成节点名称
    generate_node_name() {
        local ip="$1"
        local isp_name="$2"
        echo "${isp_name}${ip}-vpsus"
    }

    # 非交互模式主逻辑
    main_non_interactive() {
        local url_file="/etc/sing-box/url.txt"
        local selected_url=""

        # 自动选择第一个有效节点
        if [ -f "$url_file" ]; then
            mapfile -t urls < "$url_file"
            for url in "${urls[@]}"; do
                decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                    ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                    if [ $? -eq 0 ] && [ -n "$ps" ]; then 
                        selected_url="$url"
                        break
                    fi
                fi
            done
        fi

        if [ -z "$selected_url" ]; then
            echo -e "${RED}非交互模式：未找到有效节点，无法执行选项2${NC}"
            exit 1
        fi

        # 解析原始节点信息
        local base64_part="${selected_url#"vmess://"}"
        local original_json=$(echo "$base64_part" | base64 -d)
        
        # 获取IP列表（此时ip_list已是全局变量）
        process_cloud_optimize
        
        # 生成节点链接（现在能正确读取ip_list长度）
        local num_to_generate=${#ip_list[@]}
        if [ "$num_to_generate" -gt 0 ]; then
            > jd.txt  # 清空输出文件
            
            local mode="cloud"
            for ((i=0; i<num_to_generate; i++)); do
                local current_ip="${ip_list[$i]}"
                local isp_name="${isp_list[$i]}"
                local new_ps=$(generate_node_name "$current_ip" "$isp_name")
                local modified_json=$(echo "$original_json" | jq --arg new_add "$current_ip" --arg new_ps "$new_ps" '.add = $new_add | .ps = $new_ps')
                local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
                local new_url="vmess://${new_base64}"
                echo "$new_url" >> jd.txt
            done
            
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] 自动执行云优选完成，新增 ${num_to_generate} 个节点"
        else
            echo -e "${RED}没有可用的 IP 地址用于生成节点.${NC}"
            exit 1
        fi
    }

    # 执行非交互模式
    check_deps
    main_non_interactive
    exit 0  # 强制退出，不执行后续交互代码
fi

# === 以下为无交互模式代码 ===
INSTALL_PATH="/usr/local/bin/cfy"

# 安装逻辑
if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装 [cfy 节点优选生成器]..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 安装需要管理员权限。请使用 'curl ... | sudo bash' 或 'sudo bash <(curl ...)' 命令来运行。"
        exit 1
    fi
    
    echo "正在将脚本写入到 $INSTALL_PATH..."
    
    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" || "$(basename "$0")" == "-bash" ]]; then
        if ! cat /proc/self/fd/0 > "$INSTALL_PATH"; then
            echo "❌ 写入脚本失败 (管道模式)，请重试。"
            exit 1
        fi
    else
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

# 无交互模式主程序
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

ip_exists() {
    local ip="$1"
    local file="$2"
    [ -f "$file" ] || return 1
    grep -qxF "$ip" "$file"
}

process_cloud_optimize() {
    echo -e "${YELLOW}正在获取优选 IPv4 地址...${NC}"
    
    local paired_data_file
    paired_data_file=$(mktemp)
    trap 'rm -f "$paired_data_file"' EXIT

    parse_url() {
        local url="$1"; local type_desc="$2"
        echo -e "  -> 正在获取 ${type_desc} 列表..."
        local html_content=$(curl -s "$url")
        if [ -z "$html_content" ]; then 
            echo -e "${RED}  -> 获取 ${type_desc} 列表失败!${NC}"
            return
        fi
        local table_rows=$(echo "$html_content" | tr -d '\n\r' | sed 's/<tr>/\n&/g' | grep '^<tr>')
        local ips=$(echo "$table_rows" | sed -n 's/.*data-label="优选地址">\([^<]*\)<.*/\1/p')
        local isps=$(echo "$table_rows" | sed -n 's/.*data-label="线路名称">\([^<]*\)<.*/\1/p')
        paste -d' ' <(echo "$ips") <(echo "$isps") >> "$paired_data_file"
    }

    # 从云优选页面获取IP
    local url_v4="https://www.wetest.vip/page/cloudflare/address_v4.html"
    parse_url "$url_v4" "云优选页面IPv4"

    # 从指定URL获取IP
    echo -e "  -> 正在从自选链接获取IP列表..."
    local self_url="http://nas.848588.xyz:18080/output/abc/dy/cf.txt"
    local self_ips=$(curl -s "$self_url")
    if [ -n "$self_ips" ]; then
        # 为这些IP添加"自选"线路标识
        echo "$self_ips" | while read -r ip; do
            if [ -n "$ip" ]; then
                echo "$ip 自选" >> "$paired_data_file"
            fi
        done
        echo -e "  -> 成功获取自选链接IP列表"
    else
        echo -e "${YELLOW}  -> 获取自选链接IP列表失败，将仅使用云优选页面数据${NC}"
    fi

    if ! [ -s "$paired_data_file" ]; then 
        echo -e "${RED}无法从来源解析出优选 IP 地址.${NC}"
        exit 1
    fi

    declare -g -a ip_list=() isp_list=()
    local shuffled_pairs
    # 去重并打乱顺序
    mapfile -t shuffled_pairs < <(sort -u "$paired_data_file" | shuf)
    for pair in "${shuffled_pairs[@]}"; do
        ip_list+=("$(echo "$pair" | cut -d' ' -f1)")
        isp_list+=("$(echo "$pair" | cut -d' ' -f2-)")
    done
    
    local ipv4_file="ipv4.txt"
    if [ ${#ip_list[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在将新IP追加到 $ipv4_file（自动去重）...${NC}"
        local new_count=0
        
        for ip in "${ip_list[@]}"; do
            if ! ip_exists "$ip" "$ipv4_file"; then
                echo "$ip" >> "$ipv4_file"
                ((new_count++))
            fi
        done
        
        echo -e "${GREEN}已完成！新增 ${new_count} 个IP，$ipv4_file 中共有 $(wc -l < "$ipv4_file") 个唯一IP${NC}"
    fi
    
    if [ ${#ip_list[@]} -eq 0 ]; then 
        echo -e "${RED}解析成功, 但未找到任何有效的 IP 地址.${NC}"
        exit 1
    fi
    echo -e "${GREEN}成功获取 ${#ip_list[@]} 个优选 IP 地址, 列表已随机打乱.${NC}"
}

get_all_optimized_ips() {
    # 直接执行云优选模式，不显示选择菜单
    process_cloud_optimize
}

generate_node_name() {
    local ip="$1"
    local isp_name="$2"
    local mode="$3"
    
    case "$mode" in
        "official")
            echo "${ip}-CFvpsus"
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
    local selected_url=""
    
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
            decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$ps" ]; then 
                    valid_urls+=("$url")
                    valid_ps_names+=("$ps")
                fi
            fi
        done
    fi

    if [ ${#valid_urls[@]} -gt 0 ]; then
        # 自动选择第一个有效节点
        selected_url="${valid_urls[0]}"
        echo -e "${YELLOW}已自动选择节点: ${valid_ps_names[0]}${NC}"
    else
        echo -e "${RED}在 $url_file 中未找到有效节点.${NC}"
        exit 1
    fi

    local base64_part="${selected_url#"vmess://"}"
    local original_json=$(echo "$base64_part" | base64 -d)
    local original_ps=$(echo "$original_json" | jq -r .ps)
    echo -e "${GREEN}已选择: $original_ps${NC}"
    
    declare -g -a ip_list=() isp_list=()
    get_all_optimized_ips || exit 1
    
    local num_to_generate=${#ip_list[@]}
    if [ "$num_to_generate" -gt 0 ]; then
        > jd.txt
        
        echo "---"; echo -e "${YELLOW}生成的新节点链接如下:${NC}"
        
        local mode="cloud"
        for ((i=0; i<num_to_generate; i++)); do
            local current_ip="${ip_list[$i]}"
            local isp_name="${isp_list[$i]}"
            
            local new_ps=$(generate_node_name "$current_ip" "$isp_name" "$mode")
            local modified_json=$(echo "$original_json" | jq --arg new_add "$current_ip" --arg new_ps "$new_ps" '.add = $new_add | .ps = $new_ps')
            local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
            local new_url="vmess://${new_base64}"
            
            echo "$new_url"
            echo "$new_url" >> jd.txt
        done
        
        echo "---"; echo -e "${GREEN}共 ${num_to_generate} 个链接已生成完毕.${NC}"
        echo -e "${GREEN}所有节点已保存到 jd.txt${NC}"
    else
        echo -e "${RED}没有可用的 IP 地址用于生成节点.${NC}"
        exit 1
    fi
}

check_deps
main
