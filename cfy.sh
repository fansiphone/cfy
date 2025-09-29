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
    
    # 生成节点配置并使用模板
    generate_nodes_from_template "CF" "cf_all_ip.txt"
    rm -f cf_ipv4.txt cf_ipv6.txt cf_all_ip.txt
}

# 云优选模式
cloud_ip_selection() {
    echo -e "${BLUE}正在获取云优选 IP 列表...${PLAIN}"
    # 只获取IPv4地址，忽略IPv6
    curl -sSL http://speed.cloudflare.com/__down?bytes=1000 -o cf_ipv4.txt
    
    # 生成节点配置并使用模板
    generate_nodes_from_template "云优选" "cf_ipv4.txt"
    rm -f cf_ipv4.txt
}

# 自优选模式
self_ip_selection() {
    echo -e "${BLUE}正在获取自优选 IP 列表...${PLAIN}"
    curl -sSL http://nas.848588.xyz:18080/output/abc/dy/cf.txt -o self_ip.txt
    
    # 生成节点配置并使用模板
    generate_nodes_from_template "自选" "self_ip.txt"
    rm -f self_ip.txt
}

# 从模板生成节点函数
generate_nodes_from_template() {
    mode=$1
    ip_file=$2
    
    # 检查模板文件是否存在
    if [ ! -f "/etc/sing-box/url.txt" ]; then
        echo -e "${RED}错误：模板文件 /etc/sing-box/url.txt 不存在${PLAIN}"
        return
    fi
    
    # 读取模板配置
    template_line=$(head -n 1 /etc/sing-box/url.txt)
    
    # 处理IP文件
    while IFS= read -r line; do
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        # 移除可能的回车符
        line=$(echo "$line" | tr -d '\r' | xargs)
        
        # 生成节点名称
        node_name="vpsus-$mode$line"
        
        # 生成服务器地址
        if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # IPv4地址
            server_address="${line}"
        elif [[ $line =~ ^[a-fA-F0-9:]+$ ]]; then
            # IPv6地址
            server_address="[${line}]"
        else
            # 域名
            server_address="${line}"
        fi
        
        # 使用模板生成节点配置
        new_node=$(echo "$template_line" | sed "s/服务器地址/${server_address}/g; s/节点名/${node_name}/g")
        
        # 保存节点到文件
        echo "$new_node" >> jd.txt
    done < "$ip_file"
}

# 自动生成所有配置
auto_generate_all() {
    echo -e "${BLUE}开始生成所有配置...${PLAIN}"
    
    # 清空输出文件
    > jd.txt
    
    # 生成三种配置
    manual_ip_selection
    cloud_ip_selection
    self_ip_selection
    
    echo ""
    echo -e "${GREEN}所有配置已生成并保存到:${PLAIN} $(pwd)/jd.txt"
    echo -e "${GREEN}总节点数:${PLAIN} $(wc -l < jd.txt)"
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

# 执行自动生成三种来源的所有节点
auto_generate_all
