#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 安装必要依赖
install_dependencies() {
    clear
    echo -e "${YELLOW}正在安装必要依赖...${NC}"
    if [ -f "/etc/debian_version" ]; then
        apt update > /dev/null 2>&1
        apt install -y jq curl wget git qrencode > /dev/null 2>&1
    elif [ -f "/etc/redhat-release" ]; then
        yum install -y epel-release > /dev/null 2>&1
        yum install -y jq curl wget git qrencode > /dev/null 2>&1
    fi
}

# 获取公网IP
get_public_ip() {
    echo -e "${YELLOW}正在获取公网 IP...${NC}"
    public_ip=$(curl -s https://api.ip.sb/ip)
    if [ $? -ne 0 ]; then
        public_ip=$(curl -s https://ipinfo.io/ip)
    fi
    echo -e "${GREEN}公网 IP: $public_ip${NC}"
}

# 获取 Cloudflare IP 列表
get_cloudflare_ips() {
    echo -e "${YELLOW}请选择 IP 获取方式:${NC}"
    echo "1. 官方优选 (Cloudflare 官方 IP)"
    echo "2. 云优选 (第三方 IP 库)"
    echo "3. 手动输入"
    echo "4. 自选模式 (从指定链接获取)"
    read -p "请选择 (1/2/3/4): " ip_source

    case $ip_source in
        1)
            echo -e "${YELLOW}正在从 Cloudflare 获取官方 IP...${NC}"
            ips=$(curl -s https://www.cloudflare.com/ips-v4)
            mode="official"
            ;;
        2)
            echo -e "${YELLOW}正在从第三方获取优选 IP...${NC}"
            ips=$(curl -s https://ipinfo.io/ips | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
            mode="cloud"
            ;;
        3)
            read -p "请输入 IP 地址 (多个IP用空格分隔): " ips
            mode="manual"
            ;;
        4)
            echo -e "${YELLOW}正在从自选链接获取 IP...${NC}"
            ips=$(curl -s http://nas.848588.xyz:18080/output/abc/dy/cf.txt)
            mode="self"
            ;;
        *)
            echo -e "${RED}无效选择，使用默认官方 IP${NC}"
            ips=$(curl -s https://www.cloudflare.com/ips-v4)
            mode="official"
            ;;
    esac

    # 移除空行和重复项
    ips=$(echo "$ips" | sed '/^$/d' | sort -u)
    echo -e "${GREEN}获取到 ${#ips[@]} 个 IP 地址${NC}"
}

# 生成节点名称
generate_node_name() {
    ip=$1
    case $mode in
        "official")
            echo "vpsus-CF$ip"
            ;;
        "cloud")
            echo "vpsus-$(curl -s https://ipinfo.io/$ip/org | cut -d' ' -f1)$ip"
            ;;
        "self")
            echo "vpsus-自选$ip"
            ;;
        *)
            echo "vpsus-$ip"
            ;;
    esac
}

# 生成节点配置
generate_nodes() {
    echo -e "${YELLOW}正在生成节点配置...${NC}"
    port=$1
    
    # 清空现有节点文件
    > jd.txt
    
    for ip in $ips; do
        # 生成节点名称
        node_name=$(generate_node_name "$ip")
        
        # 生成节点配置
        {
            echo "端口: $port"
            echo "IP: $ip"
            echo "模式: $mode"
            echo "节点名称: $node_name"
            echo "----------"
        } >> jd.txt
        
        # 节点配置示例 (实际应用中需要生成具体协议配置)
        echo "vmess://$(echo -n "{\"add\":\"$ip\",\"port\":\"$port\",\"ps\":\"$node_name\"}" | base64)" >> jd.txt
    done
    
    echo -e "${GREEN}节点配置已保存到 jd.txt${NC}"
}

# 生成 Clash 配置
generate_clash_config() {
    port=$1
    output_file="clash_config_${port}.yaml"
    
    echo -e "${YELLOW}正在生成 Clash 配置文件...${NC}"
    echo "port: 7890" > $output_file
    echo "socks-port: 7891" >> $output_file
    echo "allow-lan: true" >> $output_file
    echo "mode: Rule" >> $output_file
    echo "log-level: info" >> $output_file
    echo "external-controller: 127.0.0.1:9090" >> $output_file
    echo "proxies:" >> $output_file
    
    for ip in $ips; do
        node_name=$(generate_node_name "$ip")
        {
            echo "  - name: \"$node_name\""
            echo "    type: vmess"
            echo "    server: $ip"
            echo "    port: $port"
            echo "    uuid: 12345678-1234-5678-1234-567812345678"
            echo "    alterId: 64"
            echo "    cipher: auto"
            echo "    udp: true"
        } >> $output_file
    done
    
    echo -e "${GREEN}Clash 配置文件已保存到 $output_file${NC}"
}

# 显示二维码
show_qrcode() {
    echo -e "${YELLOW}节点二维码:${NC}"
    for ip in $ips; do
        node_name=$(generate_node_name "$ip")
        config="vmess://$(echo -n "{\"add\":\"$ip\",\"port\":\"$port\",\"ps\":\"$node_name\"}" | base64)"
        qrencode -t ANSIUTF8 "$config"
    done
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}==============================${NC}"
    echo -e "${GREEN}    Cloudflare 节点生成器     ${NC}"
    echo -e "${GREEN}==============================${NC}"
    echo "1. 安装依赖"
    echo "2. 获取公网 IP"
    echo "3. 获取 Cloudflare IP"
    echo "4. 生成节点配置"
    echo "5. 生成 Clash 配置"
    echo "6. 显示二维码"
    echo "7. 退出"
    echo -e "${GREEN}==============================${NC}"
}

# 主程序
while true; do
    main_menu
    read -p "请选择操作 (1-7): " choice
    
    case $choice in
        1) install_dependencies ;;
        2) get_public_ip ;;
        3) get_cloudflare_ips ;;
        4) 
            if [ -z "$ips" ]; then
                echo -e "${RED}请先获取 IP 地址!${NC}"
                sleep 1
                continue
            fi
            read -p "请输入端口号 (默认 443): " port
            port=${port:-443}
            generate_nodes "$port"
            ;;
        5) 
            if [ -z "$ips" ]; then
                echo -e "${RED}请先获取 IP 地址!${NC}"
                sleep 1
                continue
            fi
            read -p "请输入端口号 (默认 443): " port
            port=${port:-443}
            generate_clash_config "$port"
            ;;
        6) 
            if [ -z "$ips" ]; then
                echo -e "${RED}请先获取 IP 地址!${NC}"
                sleep 1
                continue
            fi
            show_qrcode
            ;;
        7) 
            echo -e "${GREEN}再见!${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}无效选择，请重新输入!${NC}"
            sleep 1
            ;;
    esac
    
    read -p "按回车键继续..."
done
