#!/bin/bash

# 定义颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 检查模板文件是否存在
check_template() {
    if [ ! -f "/etc/sing-box/url.txt" ]; then
        echo -e "${RED}错误：模板文件 /etc/sing-box/url.txt 不存在${PLAIN}"
        exit 1
    fi
}

# 生成节点函数（使用参数替换代替sed）
generate_nodes() {
    mode=$1
    ip_file=$2
    
    # 检查IP文件是否存在
    if [ ! -f "$ip_file" ]; then
        echo -e "${RED}错误：IP文件 $ip_file 不存在${PLAIN}"
        return
    fi
    
    # 读取模板
    template_line=$(head -n 1 /etc/sing-box/url.txt)
    
    # 处理IP文件
    while IFS= read -r line; do
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        # 移除可能的回车符和        # 移除可能的回车符和空格
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
        
        # 使用参数替换处理模板
        new_node="${template_line//服务器地址/$server_address}"
        new_node="${new_node//节点名/$node_name}"
        
        # 保存节点到文件
        echo "$new_node" >> jd.txt
    done < "$ip_file"
}

# 自动生成所有节点
auto_generate_all_nodes() {
    echo -e "${BLUE}开始自动生成所有节点配置...${PLAIN}"
    echo ""
    
    # 清空输出文件
    > jd.txt
    
    # 1. 生成 Cloudflare 官方节点
    echo -e "${GREEN}生成 Cloudflare 官方节点...${PLAIN}"
    curl -sSL https://www.cloudflare.com/ips-v4 -o cf_ipv4.txt
    curl -sSL https://www.cloudflare.com/ips-v6 -o cf_ipv6.txt
    cat cf_ipv4.txt cf_ipv6.txt > cf_all_ip.txt
    generate_nodes "CF" "cf_all_ip.txt"
    rm -f cf_ipv4.txt cf_ipv6.txt cf_all_ip.txt
    
    # 2. 生成云优选节点（只使用IPv4）
    echo -e "${GREEN}生成云优选节点...${PLAIN}"
    curl -sSL http://speed.cloudflare.com/__down?bytes=1000 -o cf_ipv4.txt
    generate_nodes "云优选" "cf_ipv4.txt"
    rm -f cf_ipv4.txt
    
    # 3. 生成自优选节点
    echo -e "${GREEN}生成自优选节点...${PLAIN}"
    curl -sSL http://nas.848588.xyz:18080/output/abc/dy/cf.txt -o self_ip.txt
    generate_nodes "自选" "self_ip.txt"
    rm -f self_ip.txt
    
    # 输出结果
    total_nodes=$(wc -l < jd.txt)
    echo ""
    echo -e "${GREEN}所有节点已生成并保存到:${PLAIN} $(pwd)/jd.txt"
    echo -e "${GREEN}总节点数:${PLAIN} $total_nodes"
}

# 主函数
main() {
    # 检查模板文件
    check_template
    
    # 自动生成所有节点
    auto_generate_all_nodes
    
    # 添加enerate_all_nodes
    
    # 添加退出提示
    echo ""
    read -rp "按回车键退出脚本..."
}

# 执行主函数
main
