
#!/bin/bash
# 优化版 Python Xray Argo 一键部署脚本
# 功能：全球代理(国内直连+国际代理) + 速度优化 + 自动优选IP
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 基础配置
NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"
CUSTOM_DOMAINS=""
MULTI_UUIDS=""
PROTOCOLS=("vless" "vmess" "trojan")
BEST_CFIP=""

# 1. 生成UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

# 2. 检查服务PID
get_service_pid() {
    local service_key=$1
    pgrep -f "$service_key" | head -1
}

# 3. 检查协议完整性
check_protocols() {
    local list_file="$1"
    local missing=()
    for proto in "${PROTOCOLS[@]}"; do
        if ! grep -qi "$proto://" "$list_file" 2>/dev/null; then
            missing+=("$proto")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    else
        echo "缺失协议: ${missing[*]}"
        return 1
    fi
}

# 4. Clash配置管理
clash_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               Clash 配置管理               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 查看配置${NC}"
    echo -e "${BLUE}2) 导出配置${NC}"
    echo -e "${BLUE}3) 复制订阅链接${NC}"
    read -p "选择: " CLASH_CHOICE

    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo -e "${RED}未找到项目目录，请先部署${NC}"
        exit 1
    fi
    cd "$PROJECT_DIR_NAME"

    case $CLASH_CHOICE in
        1) [ -f "clash_config.yaml" ] && cat "clash_config.yaml" || echo -e "${RED}配置未生成${NC}" ;;
        2) 
            if [ -f "clash_config.yaml" ]; then
                local dest="$HOME/clash_$(date +%Y%m%d).yaml"
                cp "clash_config.yaml" "$dest"
                echo -e "${GREEN}已导出至: $dest${NC}"
            else
                echo -e "${RED}配置未生成${NC}"
            fi
            ;;
        3)
            if [ -f "clash_sub.txt" ]; then
                local sub=$(cat "clash_sub.txt")
                echo -e "${GREEN}订阅链接:${NC}\n$sub"
                echo "$sub" | xclip -selection clipboard 2>/dev/null && echo -e "${YELLOW}已复制到剪贴板${NC}"
            else
                echo -e "${RED}订阅未生成${NC}"
            fi
            ;;
    esac
    exit 0
}

# 5. 服务管理
service_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               服务管理               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 启动服务${NC}"
    echo -e "${BLUE}2) 停止服务${NC}"
    echo -e "${BLUE}3) 重启服务${NC}"
    echo -e "${BLUE}4) 重新生成节点${NC}"
    read -p "选择: " SERVICE_CHOICE

    local app_pid=$(get_service_pid "python3 app.py")

    case $SERVICE_CHOICE in
        1)
            if [ -z "$app_pid" ]; then
                [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
                nohup python3 app.py > app.log 2>&1 &
                echo -e "${GREEN}服务已启动（PID: $(get_service_pid "python3 app.py")）${NC}"
            else
                echo -e "${YELLOW}服务已运行（PID: $app_pid）${NC}"
            fi
            ;;
        2)
            if [ -n "$app_pid" ]; then
                kill "$app_pid" && echo -e "${GREEN}服务已停止${NC}"
            else
                echo -e "${RED}服务未运行${NC}"
            fi
            ;;
        3)
            [ -n "$app_pid" ] && kill "$app_pid" && sleep 2
            [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
            nohup python3 app.py > app.log 2>&1 &
            echo -e "${GREEN}服务已重启（PID: $(get_service_pid "python3 app.py")）${NC}"
            ;;
        4)
            echo -e "${BLUE}重新生成节点...${NC}"
            [ -n "$app_pid" ] && kill "$app_pid" && sleep 2
            [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
            rm -f list.txt sub.txt clash_config.yaml clash_sub.txt
            nohup python3 app.py > app.log 2>&1 &
            echo -e "${GREEN}节点生成中（PID: $(get_service_pid "python3 app.py")）${NC}"
            ;;
    esac
    exit 0
}

# 6. 日志操作
log_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               日志操作               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 查看服务日志${NC}"
    echo -e "${BLUE}2) 查看节点生成日志${NC}"
    echo -e "${BLUE}3) 清理日志${NC}"
    read -p "选择: " LOG_CHOICE

    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo -e "${RED}未找到项目目录${NC}"
        exit 1
    fi
    local log_dir="$PROJECT_DIR_NAME"

    case $LOG_CHOICE in
        1) tail -f "$log_dir/app.log" ;;
        2) grep -E "generate_links|clash|node" "$log_dir/app.log" ;;
        3) rm -f "$log_dir/app.log" && echo -e "${GREEN}日志已清理${NC}" ;;
    esac
    exit 0
}

# 7. 筛选最优Cloudflare IP
select_best_cfip() {
    echo -e "${BLUE}开始筛选最优Cloudflare IP（提升连接速度）...${NC}"
    
    # 安装必要工具
    if ! command -v wget &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y wget
    fi
    
    # 下载Cloudflare IP测速工具
    if [ ! -f "CloudflareSpeedTest" ]; then
        echo -e "${YELLOW}正在下载IP测速工具...${NC}"
        wget -q https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareSpeedTest_linux_amd64.tar.gz -O cfst.tar.gz
        tar -zxf cfst.tar.gz CloudflareSpeedTest
        chmod +x CloudflareSpeedTest
        rm -f cfst.tar.gz
    fi
    
    # 测试并选择最优IP（延迟低、速度快）
    echo -e "${BLUE}正在测试IP质量（约30秒）...${NC}"
    BEST_CFIP=$(./CloudflareSpeedTest -t 10 -n 50 -p 443 | grep -oE "([0-9]+\.){3}[0-9]+" | head -1)
    
    #  fallback方案
    if [ -z "$BEST_CFIP" ]; then
        echo -e "${YELLOW}IP测试失败，使用备用IP${NC}"
        BEST_CFIP="104.18.18.18"  # 备用Cloudflare IP
    else
        echo -e "${GREEN}已选择最优IP: $BEST_CFIP${NC}"
    fi
}

# 8. 主入口
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本（优化版）   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}功能：全球代理(国内直连+国际代理) + 速度优化${NC}"
echo -e "${BLUE}支持协议：${PROTOCOLS[*]}${NC}"
echo

# 主菜单
echo -e "${YELLOW}请选择操作:${NC}"
echo -e "${BLUE}1) 极速部署${NC}"
echo -e "${BLUE}2) 完整配置（推荐）${NC}"
echo -e "${BLUE}3) Clash管理${NC}"
echo -e "${BLUE}4) 服务管理${NC}"
echo -e "${BLUE}5) 日志操作${NC}"
echo -e "${BLUE}6) 查看节点信息${NC}"
read -p "选择 (1-6): " MODE_CHOICE

# 菜单处理
case $MODE_CHOICE in
    3) clash_manage ;;
    4) service_manage ;;
    5) log_manage ;;
    6)
        if [ -f "$NODE_INFO_FILE" ]; then
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}               节点信息               ${NC}"
            echo -e "${GREEN}========================================${NC}"
            cat "$NODE_INFO_FILE"
            echo -e "\n${YELLOW}协议检查:${NC}"
            check_protocols "$PROJECT_DIR_NAME/list.txt" || \
                echo -e "${RED}部分协议缺失，建议通过菜单4重新生成${NC}"
        else
            echo -e "${RED}未找到节点信息${NC}"
            read -p "是否部署? (y/n): " start_deploy
            [ "$start_deploy" = "y" ] && read -p "模式 (1/2): " MODE_CHOICE || exit 0
        fi
        ;;
esac

# 部署模式校验
if [ "$MODE_CHOICE" != "1" ] && [ "$MODE_CHOICE" != "2" ]; then
    echo -e "${GREEN}退出${NC}"
    exit 0
fi

# 9. 依赖安装
echo -e "${BLUE}安装依赖...${NC}"
if ! command -v python3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
fi
if ! python3 -c "import requests" &> /dev/null; then
    pip3 install requests
fi
if [ ! -d "$PROJECT_DIR_NAME" ]; then
    if command -v git &> /dev/null; then
        git clone https://github.com/eooce/python-xray-argo.git "$PROJECT_DIR_NAME"
    else
        sudo apt-get install -y unzip wget
        wget -q https://github.com/eooce/python-xray-argo/archive/refs/heads/main.zip -O tmp.zip
        unzip -q tmp.zip && mv python-xray-argo-main "$PROJECT_DIR_NAME" && rm tmp.zip
    fi
    [ $? -ne 0 ] && echo -e "${RED}下载失败，请检查网络${NC}" && exit 1
fi
cd "$PROJECT_DIR_NAME"
[ ! -f "app.py" ] && echo -e "${RED}缺少app.py${NC}" && exit 1
cp app.py app.py.backup_"$(date +%Y%m%d)"  # 备份配置
echo -e "${GREEN}依赖安装完成${NC}"

# 10. 筛选最优IP
select_best_cfip

# 11. 保活配置
KEEP_ALIVE_HF="false"
HF_TOKEN=""
HF_REPO_ID=""
configure_hf_keep_alive() {
    read -p "启用Hugging Face保活? (y/n): " setup_ka
    if [ "$setup_ka" = "y" ]; then
        read -sp "输入Token: " hf_token
        echo
        [ -z "$hf_token" ] && echo -e "${RED}Token不能为空${NC}" && return
        read -p "输入仓库ID: " hf_repo
        [ -z "$hf_repo" ] && echo -e "${RED}仓库ID不能为空${NC}" && return
        HF_TOKEN="$hf_token"
        HF_REPO_ID="$hf_repo"
        KEEP_ALIVE_HF="true"
    fi
}

# 12. 部署配置
echo -e "${BLUE}=== $( [ "$MODE_CHOICE" = "1" ] && echo "极速模式" || echo "完整模式" ) ===${NC}"

# 12.1 UUID配置
current_uuid=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
echo -e "${YELLOW}当前UUID: $current_uuid${NC}"
if [ "$MODE_CHOICE" = "2" ]; then
    read -p "启用多节点? (y/n): " multi_node
    if [ "$multi_node" = "y" ]; then
        read -p "输入UUID（逗号分隔，留空自动生成3个）: " multi_uuids
        if [ -z "$multi_uuids" ]; then
            multi_uuids="$(generate_uuid),$(generate_uuid),$(generate_uuid)"
            echo -e "${GREEN}自动生成UUID: $multi_uuids${NC}"
        fi
        MULTI_UUIDS="$multi_uuids"
    else
        read -p "输入新UUID（留空自动生成）: " uuid_input
        [ -z "$uuid_input" ] && uuid_input=$(generate_uuid)
        sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$uuid_input')/" app.py
        echo -e "${GREEN}UUID已设置: $uuid_input${NC}"
    fi
else
    # 极速模式：单UUID
    read -p "输入新UUID（留空自动生成）: " uuid_input
    [ -z "$uuid_input" ] && uuid_input=$(generate_uuid)
    sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$uuid_input')/" app.py
    echo -e "${GREEN}UUID已设置: $uuid_input${NC}"
fi

# 12.2 完整模式配置
if [ "$MODE_CHOICE" = "2" ]; then
    current_name=$(grep "NAME = " app.py | head -1 | cut -d"'" -f4)
    read -p "节点名称（当前: $current_name）: " name_input
    [ -n "$name_input" ] && sed -i "s/NAME = os.environ.get('NAME', '[^']*')/NAME = os.environ.get('NAME', '$name_input')/" app.py

    current_port=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    read -p "服务端口（当前: $current_port）: " port_input
    [ -n "$port_input" ] && sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $port_input)/" app.py

    # 使用自动选择的最优IP
    echo -e "${YELLOW}使用自动选择的最优IP: $BEST_CFIP${NC}"
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$BEST_CFIP')/" app.py

    # 自定义分流（可选）
    read -p "添加自定义分流域名? (y/n): " custom_rules
    if [ "$custom_rules" = "y" ]; then
        read -p "域名（逗号分隔）: " domains_input
        [ -n "$domains_input" ] && CUSTOM_DOMAINS="$domains_input"
    fi

    # 高级选项
    read -p "配置高级选项? (y/n): " advanced
    [ "$advanced" = "y" ] && configure_hf_keep_alive
else
    # 极速模式默认配置
    echo -e "${YELLOW}使用自动选择的最优IP: $BEST_CFIP${NC}"
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$BEST_CFIP')/" app.py
    configure_hf_keep_alive
fi

# 13. 生成节点和Clash配置（全局代理+速度优化）
echo -e "${BLUE}生成节点和Clash配置...${NC}"
cat > protocol_patch.py << 'EOF'
#!/usr/bin/env python3
import os, base64, json, subprocess, time

# 全局变量
multi_uuids = os.environ.get('MULTI_UUIDS', '')
custom_domains = os.environ.get('CUSTOM_DOMAINS', '')

# 生成Clash配置（国内直连+国际全代理）
def generate_clash_config(argo_domain, uuid_list, cfip, cfport, name):
    # 获取ISP信息
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]
    isp = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    # 多节点配置
    proxies = "proxies:\n"
    uuid_arr = uuid_list.split(',') if uuid_list else [uuid_list]
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        # VLESS-TLS (优化版)
        proxies += f'  - name: "{name}-{isp}-VLESS-TLS-{i}"\n    type: vless\n    server: {cfip}\n    port: {cfport}\n    uuid: {uuid}\n    encryption: none\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/vless-argo?ed=2560"\n      host: {argo_domain}\n    alpn:\n      - h2\n      - http/1.1\n\n'
        # VMESS-80 (优化版)
        proxies += f'  - name: "{name}-{isp}-VMESS-80-{i}"\n    type: vmess\n    server: {cfip}\n    port: 80\n    uuid: {uuid}\n    alterId: 0\n    cipher: auto\n    tls: false\n    network: ws\n    ws-opts:\n      path: "/vmess-argo?ed=2560"\n      host: {argo_domain}\n    alpn:\n      - h2\n      - http/1.1\n\n'
        # Trojan-TLS (优化版)
        proxies += f'  - name: "{name}-{isp}-Trojan-TLS-{i}"\n    type: trojan\n    server: {cfip}\n    port: {cfport}\n    password: {uuid}\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/trojan-argo?ed=2560"\n      host: {argo_domain}\n    alpn:\n      - h2\n      - http/1.1\n\n'

    # 代理组
    proxy_groups = f'''proxy-groups:
  - name: "自动选择"
    type: url-test
    proxies:
'''
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        proxy_groups += f'      - "{name}-{isp}-VLESS-TLS-{i}"\n      - "{name}-{isp}-VMESS-80-{i}"\n      - "{name}-{isp}-Trojan-TLS-{i}"\n'
    proxy_groups += '''    url: "http://www.gstatic.com/generate_204"
    interval: 300
  - name: "全局代理"
    type: select
    proxies:
      - "自动选择"
      - "DIRECT"
'''

    # 核心规则：国内直连，国际全代理
    rules = '''rules:
  # 广告屏蔽
  - GEOSITE,category-ads-all,BLOCK
  
  # 国内直连（所有中国网站）
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  - DOMAIN-SUFFIX,.cn,DIRECT
  - DOMAIN-SUFFIX,.中国,DIRECT
  - GEOSITE,geolocation-cn,DIRECT
  
  # 内网直连
  - GEOSITE,private,DIRECT
  - GEOIP,private,DIRECT
'''

    # 自定义分流
    if custom_domains:
        for domain in custom_domains.split(','):
            rules += f'  - DOMAIN-SUFFIX,{domain.strip()},全局代理\n'

    # 兜底规则：所有非国内流量走代理
    rules += '''  - MATCH,全局代理
'''

    # 写入配置
    clash_yaml = proxies + proxy_groups + rules
    with open('clash_config.yaml', 'w', encoding='utf-8') as f:
        f.write(clash_yaml)
    # 生成订阅
    clash_sub = base64.b64encode(clash_yaml.encode('utf-8')).decode('utf-8')
    with open('clash_sub.txt', 'w', encoding='utf-8') as f:
        f.write(clash_sub)
    return clash_yaml, clash_sub

# 修改app.py生成完整节点和优化配置
def patch_app():
    with open('app.py', 'r', encoding='utf-8') as f:
        content = f.read()

    # 优化Xray核心配置（全局代理+速度优化）
    old_config = 'config ={"log":{"access":"/dev/null","error":"/dev/null","loglevel":"none",},"inbounds":[{"port":ARGO_PORT ,"protocol":"vless","settings":{"clients":[{"id":UUID ,"flow":"xtls-rprx-vision",},],"decryption":"none","fallbacks":[{"dest":3001 },{"path":"/vless-argo","dest":3002 },{"path":"/vmess-argo","dest":3003 },{"path":"/trojan-argo","dest":3004 },],},"streamSettings":{"network":"tcp",},},{"port":3001 ,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":UUID },],"decryption":"none"},"streamSettings":{"network":"ws","security":"none"}},{"port":3002 ,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":UUID ,"level":0 }],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},{"port":3003 ,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[{"id":UUID ,"alterId":0 }]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},{"port":3004 ,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[{"password":UUID },]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/trojan-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},],"outbounds":[{"protocol":"freedom","tag": "direct" },{"protocol":"blackhole","tag":"block"}]}'

    new_config = '''config = {
        "log": {
            "access": "/dev/null",
            "error": "/dev/null",
            "loglevel": "none"
        },
        "inbounds": [
            {
                "port": ARGO_PORT,
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": UUID, "flow": "xtls-rprx-vision"}],
                    "decryption": "none",
                    "fallbacks": [
                        {"dest": 3001},
                        {"path": "/vless-argo", "dest": 3002},
                        {"path": "/vmess-argo", "dest": 3003},
                        {"path": "/trojan-argo", "dest": 3004}
                    ]
                },
                "streamSettings": {
                    "network": "tcp",
                    "tcpSettings": {"header": {"type": "none"}},
                    "security": "tls",
                    "tlsSettings": {"serverName": "cloudflare.com", "alpn": ["h2", "http/1.1"]}
                }
            },
            {
                "port": 3001,
                "listen": "127.0.0.1",
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": UUID}],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/", "headers": {"Host": "cloudflare.com"}}
                }
            },
            {
                "port": 3002,
                "listen": "127.0.0.1",
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": UUID, "level": 0}],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/vless-argo?ed=2560", "headers": {"Host": "cloudflare.com"}}
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "metadataOnly": False
                }
            },
            {
                "port": 3003,
                "listen": "127.0.0.1",
                "protocol": "vmess",
                "settings": {
                    "clients": [{"id": UUID, "alterId": 0}]
                },
                "streamSettings": {
                    "network": "ws",
                    "wsSettings": {"path": "/vmess-argo?ed=2560", "headers": {"Host": "cloudflare.com"}}
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "metadataOnly": False
                }
            },
            {
                "port": 3004,
                "listen": "127.0.0.1",
                "protocol": "trojan",
                "settings": {
                    "clients": [{"password": UUID}]
                },
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/trojan-argo?ed=2560", "headers": {"Host": "cloudflare.com"}}
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "metadataOnly": False
                }
            }
        ],
        "outbounds": [
            {"protocol": "freedom", "tag": "direct"},  # 直连（国内网站）
            {
                "protocol": "vless",  # 主代理协议
                "tag": "proxy",
                "settings": {
                    "vnext": [{
                        "address": CFIP,
                        "port": CFPORT,
                        "users": [{"id": UUID, "flow": "xtls-rprx-vision"}]
                    }]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "tls",
                    "tlsSettings": {"serverName": CFIP, "allowInsecure": False}
                }
            },
            {"protocol": "blackhole", "tag": "block"}  # 拦截广告
        ],
        "routing": {
            "domainStrategy": "IPOnDemand",
            "rules": [
                # 国内网站直连
                {"type": "field", "domain": ["geosite:cn", "geosite:private"], "outboundTag": "direct"},
                {"type": "field", "ip": ["geoip:cn", "geoip:private"], "outboundTag": "direct"},
                # 广告拦截
                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"},
                # 其余所有流量走代理（全球代理）
                {"type": "field", "network": "tcp,udp", "outboundTag": "proxy"}
            ]
        },
        "dns": {  # 优化DNS解析
            "servers": [
                "1.1.1.1",  # Cloudflare DNS
                "8.8.8.8",  # Google DNS
                {"address": "223.5.5.5", "domains": ["geosite:cn"]}  # 国内域名用阿里云DNS
            ]
        }
    }'''

    # 替换配置
    content = content.replace(old_config, new_config)

    # 修改generate_links函数，优化节点链接
    old_generate_function = '''async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"')
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    time.sleep(2)
    VMESS = {"v": "2", "ps": f"{NAME}-{ISP}", "add": CFIP, "port": CFPORT, "id": UUID, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "tls", "sni": argo_domain, "alpn": "", "fp": "chrome"}
 
    list_txt = f"""
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}
  
vmess://{ base64.b64encode(json.dumps(VMESS).encode('utf-8')).decode('utf-8')}

trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}
    """
    
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)

    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
        
    print(sub_txt)
    
    print(f"{FILE_PATH}/sub.txt saved successfully")
    
    # Additional actions
    send_telegram()
    upload_nodes()
 
    return sub_txt'''

    new_generate_function = '''async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"')
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    time.sleep(2)
    # 优化VMESS配置
    VMESS = {
        "v": "2", 
        "ps": f"{NAME}-{ISP}", 
        "add": CFIP, 
        "port": CFPORT, 
        "id": UUID, 
        "aid": "0", 
        "scy": "none", 
        "net": "ws", 
        "type": "none", 
        "host": argo_domain, 
        "path": "/vmess-argo?ed=2560", 
        "tls": "tls", 
        "sni": argo_domain, 
        "alpn": "h2,http/1.1",  # 启用HTTP/2提升速度
        "fp": "chrome"
    }
 
    # 增加vless+xtls协议链接（速度更快）
    list_txt = f"""
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=xtls&sni={argo_domain}&fp=chrome&type=tcp&flow=xtls-rprx-vision#{NAME}-{ISP}-xtls
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-ws
vmess://{ base64.b64encode(json.dumps(VMESS).encode('utf-8')).decode('utf-8')}
trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}
    """
    
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt.strip())

    sub_txt = base64.b64encode(list_txt.strip().encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
        
    print(sub_txt)
    
    print(f"{FILE_PATH}/sub.txt saved successfully")
    
    # Additional actions
    send_telegram()
    upload_nodes()
 
    return sub_txt'''

    # 替换生成链接的函数
    content = content.replace(old_generate_function, new_generate_function)

    # 写入修改后的内容
    with open('app.py', 'w', encoding='utf-8') as f:
        f.write(content)

if __name__ == "__main__":
    patch_app()
EOF

# 执行补丁脚本（传入环境变量）
MULTI_UUIDS="$MULTI_UUIDS" CUSTOM_DOMAINS="$CUSTOM_DOMAINS" python3 protocol_patch.py && rm protocol_patch.py
echo -e "${GREEN}节点配置生成完成${NC}"

# 14. 启动服务
echo -e "${BLUE}启动服务...${NC}"
pkill -f "python3 app.py" > /dev/null 2>&1
sleep 2
python3 app.py > app.log 2>&1 &
APP_PID=$!
if [ -z "$APP_PID" ] || [ "$APP_PID" -eq 0 ]; then
    nohup python3 app.py > app.log 2>&1 &
    sleep 2
    APP_PID=$(get_service_pid "python3 app.py")
    [ -z "$APP_PID" ] && echo -e "${RED}服务启动失败，请查看日志${NC}" && exit 1
fi
echo -e "${GREEN}主服务已启动（PID: $APP_PID）${NC}"

# 15. 启动保活服务
KEEPALIVE_PID=""
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "${BLUE}启动保活服务...${NC}"
    cat > keep_alive_task.sh << EOF
#!/bin/bash
while true; do
    status_code=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/$HF_REPO_ID")
    if [ "\$status_code" -eq 200 ]; then
        echo "保活成功（\$(date)）" > keep_alive_status.log
    else
        echo "保活失败（状态码：\$status_code，\$(date)）" > keep_alive_status.log
    fi
    sleep 120
done
EOF
    chmod +x keep_alive_task.sh
    nohup ./keep_alive_task.sh >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
    echo -e "${GREEN}保活服务已启动（PID: $KEEPALIVE_PID）${NC}"
fi

# 16. 等待节点生成
echo -e "${BLUE}等待节点生成（最多10分钟）...${NC}"
MAX_WAIT=600
WAIT_COUNT=0
NODE_INFO=""
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if [ -f ".cache/sub.txt" ] && [ -n "$(cat .cache/sub.txt 2>/dev/null)" ]; then
        NODE_INFO=$(cat .cache/sub.txt)
        break
    elif [ -f "sub.txt" ] && [ -n "$(cat sub.txt 2>/dev/null)" ]; then
        NODE_INFO=$(cat sub.txt)
        break
    fi
    [ $((WAIT_COUNT % 30)) -eq 0 ] && echo -e "${YELLOW}已等待 $((WAIT_COUNT/60)) 分 $((WAIT_COUNT%60)) 秒...${NC}"
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
done

# 17. 输出结果
if [ -n "$NODE_INFO" ]; then
    SERVICE_PORT=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    CURRENT_UUID=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    SUB_PATH_VALUE=$(grep "SUB_PATH = " app.py | cut -d"'" -f4)
    PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || "获取失败")
    DECODED_NODES=$(echo "$NODE_INFO" | base64 -d 2>/dev/null || echo "$NODE_INFO")

    # 保存节点信息
    SAVE_INFO="========================================
                      节点信息                      
========================================
部署时间: $(date)
UUID: $( [ -n "$MULTI_UUIDS" ] && echo "$MULTI_UUIDS" || echo "$CURRENT_UUID" )
服务端口: $SERVICE_PORT
优选IP: $BEST_CFIP
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE
Clash配置: $PROJECT_DIR_NAME/clash_config.yaml
支持协议: ${PROTOCOLS[*]}
=== 节点列表 ===
$DECODED_NODES
=== 管理命令 ===
查看日志: tail -f $PROJECT_DIR_NAME/app.log
重启服务: ./$0 4
"
    echo "$SAVE_INFO" > "$NODE_INFO_FILE"

    # 终端输出
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               部署完成！               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}订阅地址:${NC} ${GREEN}http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE${NC}"
    echo -e "${YELLOW}Clash配置已生成，可通过菜单3管理${NC}"
    echo -e "${YELLOW}节点信息已保存至:${NC} ${GREEN}$NODE_INFO_FILE${NC}"
else
    echo -e "${RED}节点生成超时！${NC}"
    echo -e "${YELLOW}查看日志: tail -f $PROJECT_DIR_NAME/app.log${NC}"
    exit 1
fi

echo -e "${GREEN}脚本执行完成${NC}"
exit 0
