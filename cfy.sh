#!/bin/bash

# 定义颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 获取IP地址函数
ip_address() {
    ipv4_address=$(curl -s ipv4.ip.sb)
    ipv6_address=$(curl -s ipv6.ip.sb)
}

# 显示菜单函数
display_menu() {
    clear
    echo "###############################"
    echo -e "#   ${RED}Cloudflare WARP 一键配置脚本${PLAIN}   #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No           #"
    echo -e "# ${GREEN}博客${PLAIN}: https://owo.misaka.rest #"
    echo "###############################"
    echo ""

    echo -e " ${GREEN}1.${PLAIN} 安装 WARP"
    echo -e " ${GREEN}2.${PLAIN} 卸载 WARP"
    echo -e " ${GREEN}3.${PLAIN} 手动优选 Cloudflare IP"
    echo -e " ${GREEN}4.${PLAIN} 自动优选 Cloudflare IP"
    echo -e " ${GREEN}5.${PLAIN} 查看当前网络状态"
    echo -e " ${GREEN}6.${PLAIN} 重启 WARP"
    echo -e " ${GREEN}7.${PLAIN} 查看 WARP 日志"
    echo -e " ${GREEN}8.${PLAIN} 退出脚本"
    echo ""
}

# 安装 WARP
install_warp() {
    bash <(curl -fsSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh) 1
}

# 卸载 WARP
uninstall_warp() {
    bash <(curl -fsSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh) 2
}

# 手动优选 Cloudflare IP
manual_ip_selection() {
    echo -e "${BLUE}正在获取 Cloudflare 官方 IP 列表...${PLAIN}"
    curl -sSL https://www.cloudflare.com/ips-v4 -o cf_ipv4.txt
    curl -sSL https://www.cloudflare.com/ips-v6 -o cf_ipv6.txt
    
    # 合并IPv4和IPv6地址
    cat cf_ipv4.txt cf_ipv6.txt > cf_all_ip.txt
    
    # 生成节点配置
    generate_config "CF" "cf_all_ip.txt"
    rm -f cf_ipv4.txt cf_ipv6.txt cf_all_ip.txt
}

# 云优选模式
cloud_ip_selection() {
    echo -e "${BLUE}正在获取云优选 IP 列表...${PLAIN}"
    curl -sSL http://speed.cloudflare.com/__down?bytes=1000 -o cf_ipv4.txt
    curl -sSL http://[2606:4700:4700::1111]/__down?bytes=1000 -o cf_ipv6.txt
    
    # 合并IPv4和IPv6地址
    cat cf_ipv4.txt cf_ipv6.txt > cf_all_ip.txt
    
    # 生成节点配置
    generate_config "云优选" "cf_all_ip.txt"
    rm -f cf_ipv4.txt cf_ipv6.txt cf_all_ip.txt
}

# 自优选模式
self_ip_selection() {
    echo -e "${BLUE}正在获取自优选 IP 列表...${PLAIN}"
    curl -sSL http://nas.848588.xyz:18080/output/abc/dy/cf.txt -o self_ip.txt
    
    # 生成节点配置
    generate_config "自选" "self_ip.txt"
    rm -f self_ip.txt
}

# 生成配置文件函数
generate_config() {
    mode=$1
    ip_file=$2
    output_file="warp_nodes.txt"
    
    rm -f $output_file
    
    while read line; do
        if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # IPv4地址
            echo "vless://fd4f715d-da0d-4d03-87e2-2c8ee8a0e6b3@$line:443?encryption=none&security=tls&sni=www.cloudflare.com&fp=randomized&type=ws&host=www.cloudflare.com&path=%2F%3Fed%3D2048#vpsus-$mode$line" >> $output_file
        elif [[ $line =~ ^[a-fA-F0-9:]+$ ]]; then
            # IPv6地址
            echo "vless://fd4f715d-da0d-4d03-87e2-2c8ee8a0e6b3@[$line]:443?encryption=none&security=tls&sni=www.cloudflare.com&fp=randomized&type=ws&host=www.cloudflare.com&path=%2F%3Fed%3D2048#vpsus-$mode$line" >> $output_file
        elif [[ $line =~ [a-zA-Z0-9\.-]+\.[a-zA-Z]{2,} ]]; then
            # 域名
            echo "vless://fd4f715d-da0d-4d03-87e2-2c8ee8a0e6b3@$line:443?encryption=none&security=tls&sni=www.cloudflare.com&fp=randomized&type=ws&host=www.cloudflare.com&path=%2F%3Fed%3D2048#vpsus-$mode$line" >> $output_file
        fi
    done < $ip_file
    
    # 保存到 jd.txt 并打印路径
    cp -f $output_file jd.txt
    echo -e "${GREEN}配置已保存到:${PLAIN} $(pwd)/jd.txt"
}

# 主函数
main() {
    while true; do
        display_menu
        ip_address
        
        if [ -n "$ipv4_address" ]; then
            echo -e " ${BLUE}IPv4 地址:${PLAIN} $ipv4_address"
        fi
        
        if [ -n "$ipv6_address" ]; then
            echo -e " ${BLUE}IPv6 地址:${PLAIN} $ipv6_address"
        fi
        
        echo ""
        read -rp "请输入选项 [1-8]: " choice
        
        case $choice in
        1)
            install_warp
            read -rp "按回车键返回菜单..."
            ;;
        2)
            uninstall_warp
            read -rp "按回车键返回菜单..."
            ;;
        3)
            manual_ip_selection
            read -rp "按回车键返回菜单..."
            ;;
        4)
            cloud_ip_selection
            read -rp "按回车键返回菜单..."
            ;;
        5)
            bash <(curl -fsSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh) 4
            read -rp "按回车键返回菜单..."
            ;;
        6)
            warp restart
            read -rp "按回车键返回菜单..."
            ;;
        7)
            warp logs
            read -rp "按回车键返回菜单..."
            ;;
        8)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新输入！${PLAIN}"
            sleep 2
            ;;
        esac
    done
}

# 自动生成所有配置
auto_generate_all() {
    echo -e "${BLUE}开始生成所有配置...${PLAIN}"
    
    # 生成三种配置
    manual_ip_selection
    cloud_ip_selection
    self_ip_selection
    
    # 合并所有配置
    cat warp_nodes.txt > all_nodes.txt
    echo ""
    echo -e "${GREEN}所有配置已生成并保存到:${PLAIN}"
    echo -e "${YELLOW}手动优选配置:${PLAIN} $(pwd)/cf_all_ip.txt"
    echo -e "${YELLOW}云优选配置:${PLAIN} $(pwd)/cf_ipv4.txt 和 $(pwd)/cf_ipv6.txt"
    echo -e "${YELLOW}自优选配置:${PLAIN} $(pwd)/self_ip.txt"
    echo -e "${YELLOW}节点配置文件:${PLAIN} $(pwd)/warp_nodes.txt"
    echo -e "${YELLOW}JD保存文件:${PLAIN} $(pwd)/jd.txt"
}

# 执行自动生成
auto_generate_all
