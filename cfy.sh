#!/bin/bash

# cfy.sh Cloudflare优选IP脚本
# 作者：byJoey (修改版)

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[1;37m'
nc='\033[0m'

printf "\n%s" "${yellow}╔══════════════════════════════════════════════════════════════════════════════╗${nc}"
printf "\n%s" "${yellow}║%s%-74s%s║${nc}" " " " cfy - Cloudflare IP优选 " " "
printf "\n%s" "${yellow}╚══════════════════════════════════════════════════════════════════════════════╝${nc}"
printf "\n\n"

# 函数定义
info() {
    printf "\r  [${green}信息${nc}] ${cyan}%s${nc}\n" "$*"
}

user() {
    printf "\r  [${yellow}用户${nc}] ${cyan}%s${nc}" "$*"
}

succ() {
    printf "\r%s[ ${green}成功${nc} ] ${cyan}%s${nc}\n" "  " "$*"
}

err() {
    printf "\r%s[ ${red}错误${nc} ] ${red}%s${nc}\n" "  " "$*"
}

warn() {
    printf "\r  [${yellow}注意${nc}] ${red}%s${nc}\n" "$*"
}

# 获取运营商
get_operator() {
    local ip=$1
    local isp=$(curl -s --max-time 2 "http://ip.taobao.com/service/getIpInfo.php?ip=$ip" 2>/dev/null | awk -F'"' '/isp/ {print $4}' | head -1)
    if [[ -z "$isp" ]]; then
        isp="未知"
    fi
    # 简写运营商
    if [[ "$isp" == *"电信"* ]]; then
        isp="CT"
    elif [[ "$isp" == *"移动"* ]]; then
        isp="CM"
    elif [[ "$isp" == *"联通"* ]]; then
        isp="CU"
    else
        isp="其他"
    fi
    echo "$isp"
}

# 测试延迟 (ms)
test_latency() {
    local server=$1
    local ips
    if [[ $server =~ [a-zA-Z] ]]; then
        # 如果是域名，解析IP用于ping
        ips=$(dig +short $server | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        if [[ -z "$ips" ]]; then
            echo 9999
            return
        fi
        server=$ips
    fi
    if [[ $server =~ : ]]; then
        # IPv6
        ping6 -c 3 -W 2 $server 2>/dev/null | tail -1 | awk '{print $6}' | cut -d/ -f2 | awk '{print int($1 * 1000 + 0.5)}' || echo 9999
    else
        # IPv4
        ping -c 3 -W 2 $server 2>/dev/null | tail -1 | awk '{print $4}' | cut -d/ -f2 | awk '{print int($1 * 1000 + 0.5)}' || echo 9999
    fi
}

# 获取用户输入
read -p "$(user '请选择模式 (1)云优选 (2)Cloudflare官方 (3)自优选 (4)退出 [默认1]: ')" mode
mode=${mode:-1}
if [[ $mode == 4 ]]; then
    exit 0
fi

info "请输入配置信息"
read -p "$(user 'UUID: ')" uuid
read -p "$(user 'WS Path (默认 /): ')" path
path=${path:-/}
read -p "$(user 'Host (默认 example.com): ')" host
host=${host:-example.com}

case $mode in
1)
    info "开始云优选模式..."
    local ipv4=$(curl -s "https://www.cloudflare.com/ips-v4")
    local ipv6=$(curl -s "https://www.cloudflare.com/ips-v6")
    local servers=($(echo -e "$ipv4\n$ipv6" | grep -v '^$' | tr '\n' ' '))
    rm -f jd.txt
    local count=0
    for server in "${servers[@]}"; do
        local latency=$(test_latency "$server")
        info "测试 $server : ${latency}ms"
        if [[ $latency -lt 300 && $latency -lt 9999 ]]; then
            local operator=$(get_operator "$server")
            local name="vpsus-${operator}[${server}]"
            local node="vless://${uuid}@${server}:443?encryption=none&security=tls&type=ws&host=${host}&path=${path}#${name}"
            echo "$node" >> jd.txt
            ((count++))
        fi
    done
    succ "云优选模式完成，共生成 ${count} 个节点，保存到 jd.txt"
    ;;
2)
    info "开始Cloudflare官方模式..."
    local ipv4=$(curl -s "https://www.cloudflare.com/ips-v4")
    local ipv6=$(curl -s "https://www.cloudflare.com/ips-v6")
    local servers=($(echo -e "$ipv4\n$ipv6" | sort -u | grep -v '^$' | tr '\n' ' '))
    rm -f jd.txt
    local count=0
    for server in "${servers[@]}"; do
        local name="vpsus-CF[${server}]"
        local node="vless://${uuid}@${server}:443?encryption=none&security=tls&type=ws&host=${host}&path=${path}#${name}"
        echo "$node" >> jd.txt
        ((count++))
    done
    succ "Cloudflare官方模式完成，共生成 ${count} 个节点，保存到 jd.txt"
    ;;
3)
    info "开始自优选模式..."
    local txt_content=$(curl -s "http://nas.848588.xyz:18080/output/abc/dy/cf.txt")
    if [[ -z "$txt_content" ]]; then
        err "无法获取自优选列表"
        exit 1
    fi
    local servers=($(echo "$txt_content" | sed '/^$/d' | sed 's/[ \t]*//g' | tr '\n' ' '))
    rm -f jd.txt
    local count=0
    for server in "${servers[@]}"; do
        local name="vpsus-自选[${server}]"
        local node="vless://${uuid}@${server}:443?encryption=none&security=tls&type=ws&host=${host}&path=${path}#${name}"
        echo "$node" >> jd.txt
        ((count++))
    done
    succ "自优选模式完成，共生成 ${count} 个节点，保存到 jd.txt"
    ;;
*)
    err "无效模式"
    exit 1
    ;;
esac
