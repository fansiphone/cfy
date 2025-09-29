#!/bin/bash

# 定义颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 生成节点函数
generate_node() {
    mode=$1
    address=$2
    
    # 生成节点名称
    node_name="vpsus-$mode$address"
    
    # 生成服务器地址 (IPv6需要加方括号)
    if [[ $address == *:* ]]; then
        server_address="[$address]"
    else
        server_address="$address"
    fi        server_address="$address"
    fi
    
    # 生成节点配置 (固定格式)
    echo "vless://fd4f715d-da0d-4d03-87e2-2c8ee8a0e6b3@${server_address}:443?encryption=none&security=tls&sni=www.cloudflare.com&fp=randomized&type=ws&host=www.cloudflare.com&path=%2F%3Fed%3D2048#${node_name}"
}

#8#${node_name}"
}

# 自动生成所有节点
auto_generate_all_nodes() {
    echo -e "${BLUE}开始自动生成所有节点配置...${PLAIN}"
    
    # 清空输出文件
    > jd.txt
    
    # 1. 生成 Cloudflare 官方节点
    echo -e "${GREEN}生成 Cloudflare 官方节点...${PLAIN}"
    curl -sSL https://www.cloudflare.com/ips-v4 -o cf_ipv4.txt
    curl -sSL https://www.cloudflare.com/ips-v6 -o cf_ipv6.txt
    cat cf_ipv4.txt cf_ipv6.txt > cf_all_ip.txtv6.txt > cf_all_ip.txt
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            generate_node "CF" "$line" >> jd.txt
        fi
    done < cf_all_ip.txt
    rm -f cf_ipv4.txt cf_ipv6.txt cf_all_ip.txt
    
    # 2. 生成云优选节点（只使用IPv4）
    echo -e "${GREEN}生成云优选节点...${PLAIN}"
    curl -sSL http://speed.cloudflare.com/__down?bytes=1000 -o cf_ipv4.txt
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            generate_node "云优选" "$line" >> jd.txt
        fi
    done < cf_ipv4.txt
    rm -f cf_ipv4.txt
    
    # 3. 生成自优选节点
    echo -e "${GREEN}生成自优选节点...${PLAIN}"
    curl -sSL http://nas.848588.xyz:18080/output/abc/dy/cf.txt -o self_ip.txt
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            generate_node "自选" "$line" >> jd.txt
        fi
    done < self_ip.txt
    rm -f self_ip.txt
    
    # 输出结果
    total_nodes=$(wc -l < jd.txt)
    echo ""
    echo -e "${GREEN}所有节点已生成并保存到:${PLAIN} $(pwd)/jd.txt"
    echo -e "${GREEN}总节点数:${PLAIN} $total_nodes"
}

# 主函数
main() {
    # 自动生成所有节点
    auto_generate_all_nodes
    
    # 添加退出提示
    echo ""
    read -rp "按回车键退出脚本..."
}

# 执行主函数
main
