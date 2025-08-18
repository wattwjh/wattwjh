#!/bin/bash
# Python Xray Argo 一键部署脚本（最终修复版）
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
PROTOCOLS=("vless" "vmess" "trojan")  # 确保包含所有协议

# 工具函数：生成UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

# 工具函数：检查服务PID
get_service_pid() {
    local service_key=$1
    pgrep -f "$service_key" | head -1
}

# 检查节点文件是否包含所有协议
check_protocols_generated() {
    local list_file="$1"
    local missing=()
    
    for proto in "${PROTOCOLS[@]}"; do
        if ! grep -qi "$proto://" "$list_file" 2>/dev/null; then
            missing+=("$proto")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        return 0  # 所有协议都存在
    else
        echo "缺失协议节点: ${missing[*]}"
        return 1  # 存在缺失
    fi
}

# Clash配置管理
clash_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               Clash 配置管理               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 查看 Clash YAML 配置${NC}"
    echo -e "${BLUE}2) 导出 Clash 配置到本地${NC}"
    echo -e "${BLUE}3) 复制 Clash 订阅链接${NC}"
    read -p "请输入选择 (1-3): " CLASH_CHOICE

    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo -e "${RED}未找到项目目录，请先部署服务${NC}"
        exit 1
    fi
    cd "$PROJECT_DIR_NAME"

    case $CLASH_CHOICE in
        1)
            if [ -f "clash_config.yaml" ]; then
                cat "clash_config.yaml"
            else
                echo -e "${RED}Clash 配置文件未生成，请重新部署服务${NC}"
            fi
            ;;
        2)
            if [ -f "clash_config.yaml" ]; then
                local dest="$HOME/clash_config_$(date +%Y%m%d_%H%M).yaml"
                cp "clash_config.yaml" "$dest"
                echo -e "${GREEN}配置已导出到：$dest${NC}"
            else
                echo -e "${RED}Clash 配置文件未生成${NC}"
            fi
            ;;
        3)
            if [ -f "clash_sub.txt" ]; then
                local clash_sub=$(cat "clash_sub.txt")
                echo -e "${GREEN}Clash 订阅链接：${NC}"
                echo "$clash_sub"
                echo "$clash_sub" | xclip -selection clipboard 2>/dev/null && echo -e "${YELLOW}已复制到剪贴板${NC}"
            else
                echo -e "${RED}Clash 订阅文件未生成${NC}"
            fi
            ;;
    esac
    exit 0
}

# 服务管理
service_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               服务管理               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 启动主服务${NC}"
    echo -e "${BLUE}2) 停止主服务${NC}"
    echo -e "${BLUE}3) 重启主服务${NC}"
    echo -e "${BLUE}4) 重新生成所有节点${NC}"
    read -p "请输入选择 (1-4): " SERVICE_CHOICE

    local app_pid=$(get_service_pid "python3 app.py")

    case $SERVICE_CHOICE in
        1)
            if [ -z "$app_pid" ]; then
                [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
                nohup python3 app.py > app.log 2>&1 &
                echo -e "${GREEN}主服务已启动（PID: $(get_service_pid "python3 app.py")）${NC}"
            else
                echo -e "${YELLOW}主服务已运行（PID: $app_pid）${NC}"
            fi
            ;;
        2)
            if [ -n "$app_pid" ]; then
                kill "$app_pid" && echo -e "${GREEN}主服务已停止（PID: $app_pid）${NC}"
            else
                echo -e "${RED}主服务未运行${NC}"
            fi
            ;;
        3)
            if [ -n "$app_pid" ]; then
                kill "$app_pid" && sleep 2
            fi
            [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
            nohup python3 app.py > app.log 2>&1 &
            echo -e "${GREEN}主服务已重启（新PID: $(get_service_pid "python3 app.py")）${NC}"
            ;;
        4)
            echo -e "${BLUE}正在重新生成所有协议节点...${NC}"
            [ -n "$app_pid" ] && kill "$app_pid" && sleep 2
            [ -d "$PROJECT_DIR_NAME" ] && cd "$PROJECT_DIR_NAME"
            rm -f list.txt sub.txt clash_config.yaml clash_sub.txt
            nohup python3 app.py > app.log 2>&1 &
            echo -e "${GREEN}节点重新生成中，PID: $(get_service_pid "python3 app.py")${NC}"
            echo -e "${YELLOW}查看进度：tail -f $PROJECT_DIR_NAME/app.log${NC}"
            ;;
    esac
    exit 0
}

# 日志操作
log_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               日志操作               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 实时查看主服务日志${NC}"
    echo -e "${BLUE}2) 查看节点生成日志${NC}"
    echo -e "${BLUE}3) 清理所有日志文件${NC}"
    read -p "请输入选择 (1-3): " LOG_CHOICE

    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo -e "${RED}未找到项目目录，请先部署服务${NC}"
        exit 1
    fi
    local log_dir="$PROJECT_DIR_NAME"

    case $LOG_CHOICE in
        1)
            tail -f "$log_dir/app.log"
            ;;
        2)
            echo -e "${YELLOW}--- 节点生成记录 ---${NC}"
            grep -E "saved successfully|generate_links|clash_config" "$log_dir/app.log"
            ;;
        3)
            rm -f "$log_dir/app.log" "$log_dir/keep_alive_status.log"
            echo -e "${GREEN}所有日志已清理${NC}"
            ;;
    esac
    exit 0
}

# 主脚本入口
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本（最终修复版）   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}支持协议：${PROTOCOLS[*]}（自动生成所有协议节点）${NC}"
echo -e "${BLUE}附加功能：Clash配置、多节点、自定义分流${NC}"
echo

# 主菜单
echo -e "${YELLOW}请选择操作:${NC}"
echo -e "${BLUE}1) 极速模式 - 快速部署（默认配置）${NC}"
echo -e "${BLUE}2) 完整模式 - 自定义配置（推荐）${NC}"
echo -e "${BLUE}3) Clash 管理 - 查看/导出配置${NC}"
echo -e "${BLUE}4) 服务管理 - 启停/重启/重新生成节点${NC}"
echo -e "${BLUE}5) 日志操作 - 查看/清理日志${NC}"
echo -e "${BLUE}6) 查看节点信息 - 显示所有协议节点${NC}"
echo
read -p "请输入选择 (1-6): " MODE_CHOICE

# 菜单分支处理
case $MODE_CHOICE in
    3) clash_manage ;;
    4) service_manage ;;
    5) log_manage ;;
    6)
        if [ -f "$NODE_INFO_FILE" ]; then
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}               所有协议节点信息               ${NC}"
            echo -e "${GREEN}========================================${NC}"
            cat "$NODE_INFO_FILE"
            echo -e "\n${YELLOW}检查协议完整性:${NC}"
            check_protocols_generated "$PROJECT_DIR_NAME/list.txt" || \
                echo -e "${RED}注意：部分协议节点缺失，请通过菜单4重新生成${NC}"
        else
            echo -e "${RED}未找到节点信息文件${NC}"
            read -p "是否现在部署? (y/n): " start_deploy
            [ "$start_deploy" = "y" ] && read -p "选择部署模式 (1=极速/2=完整): " MODE_CHOICE || exit 0
        fi
        ;;
esac

# 部署模式校验
if [ "$MODE_CHOICE" != "1" ] && [ "$MODE_CHOICE" != "2" ]; then
    echo -e "${GREEN}退出脚本${NC}"
    exit 0
fi

# 依赖安装
echo -e "${BLUE}检查并安装依赖...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}安装Python3...${NC}"
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
fi
if ! python3 -c "import requests" &> /dev/null; then
    pip3 install requests
fi
if [ ! -d "$PROJECT_DIR_NAME" ]; then
    echo -e "${BLUE}下载项目仓库...${NC}"
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
[ ! -f "app.py" ] && echo -e "${RED}未找到app.py${NC}" && exit 1
cp app.py app.py.backup_"$(date +%Y%m%d_%H%M)"
echo -e "${GREEN}依赖安装完成！${NC}"

# 保活配置
KEEP_ALIVE_HF="false"
HF_TOKEN=""
HF_REPO_ID=""
configure_hf_keep_alive() {
    read -p "是否设置Hugging Face保活? (y/n): " setup_ka
    if [ "$setup_ka" = "y" ]; then
        read -sp "输入Hugging Face Token: " hf_token
        echo
        [ -z "$hf_token" ] && echo -e "${RED}Token不能为空${NC}" && return
        read -p "输入仓库ID（如 joeyhuangt/aaaa）: " hf_repo
        [ -z "$hf_repo" ] && echo -e "${RED}仓库ID不能为空${NC}" && return
        HF_TOKEN="$hf_token"
        HF_REPO_ID="$hf_repo"
        KEEP_ALIVE_HF="true"
        echo -e "${GREEN}保活配置完成！${NC}"
    fi
}

# 部署配置（强化协议节点生成）
echo -e "${BLUE}=== $( [ "$MODE_CHOICE" = "1" ] && echo "极速模式" || echo "完整模式" ) ===${NC}"

# UUID配置
current_uuid=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
echo -e "${YELLOW}当前UUID: $current_uuid${NC}"
if [ "$MODE_CHOICE" = "2" ]; then
    read -p "是否配置多节点? (y/n，多UUID用逗号分隔): " multi_node
    if [ "$multi_node" = "y" ]; then
        read -p "输入多个UUID（留空自动生成3个）: " multi_uuids
        if [ -z "$multi_uuids" ]; then
            multi_uuids="$(generate_uuid),$(generate_uuid),$(generate_uuid)"
            echo -e "${GREEN}自动生成多UUID: $multi_uuids${NC}"
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

# 完整模式额外配置
if [ "$MODE_CHOICE" = "2" ]; then
    current_name=$(grep "NAME = " app.py | head -1 | cut -d"'" -f4)
    read -p "输入节点名称（当前: $current_name，留空不变）: " name_input
    [ -n "$name_input" ] && sed -i "s/NAME = os.environ.get('NAME', '[^']*')/NAME = os.environ.get('NAME', '$name_input')/" app.py

    current_port=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    read -p "输入服务端口（当前: $current_port，留空不变）: " port_input
    [ -n "$port_input" ] && sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $port_input)/" app.py

    current_cfip=$(grep "CFIP = " app.py | cut -d"'" -f4)
    read -p "输入优选IP（当前: $current_cfip，留空用joeyblog.net）: " cfip_input
    [ -z "$cfip_input" ] && cfip_input="joeyblog.net"
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$cfip_input')/" app.py

    # 自定义分流规则
    read -p "是否添加自定义分流域名? (y/n，如 netflix.com): " custom_rules
    if [ "$custom_rules" = "y" ]; then
        read -p "输入分流域名（逗号分隔）: " domains_input
        [ -n "$domains_input" ] && CUSTOM_DOMAINS="$domains_input"
        echo -e "${GREEN}自定义分流已添加: $domains_input${NC}"
    fi

    # 高级选项
    read -p "是否配置高级选项? (y/n): " advanced
    if [ "$advanced" = "y" ]; then
        configure_hf_keep_alive
    fi
else
    # 极速模式：自动配置
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
    echo -e "${GREEN}优选IP已设置: joeyblog.net${NC}"
    configure_hf_keep_alive
fi

# 生成所有协议节点和Clash配置（最终修复版）
echo -e "${BLUE}生成所有协议节点（${PROTOCOLS[*]}）和Clash配置...${NC}"
cat > protocol_patch.py << 'EOF'
#!/usr/bin/env python3
import os, base64, json, subprocess, time

# 从环境变量获取配置
multi_uuids = os.environ.get('MULTI_UUIDS', '')
custom_domains = os.environ.get('CUSTOM_DOMAINS', '')
protocols = os.environ.get('PROTOCOLS', 'vless,vmess,trojan').split(',')

# 生成所有协议节点
def generate_all_protocols(argo_domain, uuid_list, cfip, cfport, name):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]
    isp = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()
    
    list_txt = ""
    uuid_arr = uuid_list.split(',') if uuid_list else [uuid_list]
    
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        
        # 生成VLESS节点
        if 'vless' in protocols:
            # VLESS-TLS
            list_txt += f"vless://{uuid}@{cfip}:{cfport}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{name}-{isp}-VLESS-TLS-{i}\n\n"
            # VLESS-80
            list_txt += f"vless://{uuid}@{cfip}:80?encryption=none&security=none&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{name}-{isp}-VLESS-80-{i}\n\n"
        
        # 生成VMESS节点
        if 'vmess' in protocols:
            # VMESS-TLS
            vmess_tls = {
                "v": "2", "ps": f"{name}-{isp}-VMESS-TLS-{i}",
                "add": cfip, "port": cfport, "id": uuid,
                "aid": "0", "scy": "none", "net": "ws",
                "type": "none", "host": argo_domain,
                "path": "/vmess-argo?ed=2560", "tls": "tls",
                "sni": argo_domain, "alpn": "", "fp": "chrome"
            }
            list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_tls).encode('utf-8')).decode('utf-8')}\n\n"
            
            # VMESS-80
            vmess_80 = {
                "v": "2", "ps": f"{name}-{isp}-VMESS-80-{i}",
                "add": cfip, "port": "80", "id": uuid,
                "aid": "0", "scy": "none", "net": "ws",
                "type": "none", "host": argo_domain,
                "path": "/vmess-argo?ed=2560", "tls": ""
            }
            list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_80).encode('utf-8')).decode('utf-8')}\n\n"
        
        # 生成Trojan节点
        if 'trojan' in protocols:
            # Trojan-TLS
            list_txt += f"trojan://{uuid}@{cfip}:{cfport}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{name}-{isp}-Trojan-TLS-{i}\n\n"
            # Trojan-80
            list_txt += f"trojan://{uuid}@{cfip}:80?security=none&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{name}-{isp}-Trojan-80-{i}\n\n"
    
    return list_txt, isp

# 生成Clash配置
def generate_clash_config(argo_domain, uuid_list, cfip, cfport, name, isp):
    proxies = "proxies:\n"
    uuid_arr = uuid_list.split(',') if uuid_list else [uuid_list]
    
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        
        if 'vless' in protocols:
            proxies += f'  - name: "{name}-{isp}-VLESS-TLS-{i}"\n    type: vless\n    server: {cfip}\n    port: {cfport}\n    uuid: {uuid}\n    encryption: none\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/vless-argo?ed=2560"\n      host: {argo_domain}\n\n'
        
        if 'vmess' in protocols:
            proxies += f'  - name: "{name}-{isp}-VMESS-TLS-{i}"\n    type: vmess\n    server: {cfip}\n    port: {cfport}\n    uuid: {uuid}\n    alterId: 0\n    cipher: auto\n    tls: true\n    network: ws\n    ws-opts:\n      path: "/vmess-argo?ed=2560"\n      host: {argo_domain}\n\n'
        
        if 'trojan' in protocols:
            proxies += f'  - name: "{name}-{isp}-Trojan-TLS-{i}"\n    type: trojan\n    server: {cfip}\n    port: {cfport}\n    password: {uuid}\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/trojan-argo?ed=2560"\n      host: {argo_domain}\n\n'
    
    # 构建代理组配置
    proxy_groups = "proxy-groups:\n"
    proxy_groups += "  - name: \"自动选择\"\n"
    proxy_groups += "    type: url-test\n"
    proxy_groups += "    proxies:\n"
    
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        if 'vless' in protocols:
            proxy_groups += f'      - "{name}-{isp}-VLESS-TLS-{i}"\n'
        if 'vmess' in protocols:
            proxy_groups += f'      - "{name}-{isp}-VMESS-TLS-{i}"\n'
        if 'trojan' in protocols:
            proxy_groups += f'      - "{name}-{isp}-Trojan-TLS-{i}"\n'
    
    proxy_groups += "    url: \"http://www.gstatic.com/generate_204\"\n"
    proxy_groups += "    interval: 300\n"
    proxy_groups += "  - name: \"全局代理\"\n"
    proxy_groups += "    type: select\n"
    proxy_groups += "    proxies:\n"
    proxy_groups += "      - \"自动选择\"\n"
    proxy_groups += "      - \"DIRECT\"\n"

    # 构建规则配置
    rules = "rules:\n"
    rules += "  - DOMAIN-SUFFIX,youtube.com,自动选择\n"
    rules += "  - DOMAIN-SUFFIX,youtu.be,自动选择\n"
    rules += "  - DOMAIN-SUFFIX,googlevideo.com,自动选择\n"
    
    if custom_domains:
        for domain in custom_domains.split(','):
            rules += f'  - DOMAIN-SUFFIX,{domain.strip()},自动选择\n'
    
    rules += "  - DOMAIN-SUFFIX,baidu.com,DIRECT\n"
    rules += "  - DOMAIN-SUFFIX,qq.com,DIRECT\n"
    rules += "  - GEOIP,CN,DIRECT\n"
    rules += "  - MATCH,全局代理\n"

    # 组合并写入配置
    clash_yaml = proxies + proxy_groups + rules
    with open('clash_config.yaml', 'w', encoding='utf-8') as f:
        f.write(clash_yaml)
    with open('clash_sub.txt', 'w', encoding='utf-8') as f:
        f.write(base64.b64encode(clash_yaml.encode('utf-8')).decode('utf-8'))

# 修改app.py确保所有协议节点被生成
def patch_app_py():
    with open('app.py', 'r', encoding='utf-8') as f:
        content = f.read()

    # 确保所有协议的入站配置存在
    inbound_config = '''"inbounds": [
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
                "streamSettings": {"network": "tcp"}
            },
            {
                "port": 3001,
                "listen": "127.0.0.1",
                "protocol": "vless",
                "settings": {"clients": [{"id": UUID}], "decryption": "none"},
                "streamSettings": {"network": "ws", "security": "none"}
            },
            {
                "port": 3002,
                "listen": "127.0.0.1",
                "protocol": "vless",
                "settings": {"clients": [{"id": UUID, "level": 0}], "decryption": "none"},
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/vless-argo"}
                },
                "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}
            },
            {
                "port": 3003,
                "listen": "127.0.0.1",
                "protocol": "vmess",
                "settings": {"clients": [{"id": UUID, "alterId": 0}]},
                "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess-argo"}},
                "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}
            },
            {
                "port": 3004,
                "listen": "127.0.0.1",
                "protocol": "trojan",
                "settings": {"clients": [{"password": UUID}]},
                "streamSettings": {
                    "network": "ws",
                    "security": "none",
                    "wsSettings": {"path": "/trojan-argo"}
                },
                "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}
            }
        ]'''
    
    # 替换入站配置
    content = content.replace(
        content[content.find('"inbounds": ['):content.find('"outbounds": [')],
        inbound_config
    )

    # 替换节点生成函数
    new_generate_links = '''async def generate_links(argo_domain):
    from protocol_generator import generate_all_protocols, generate_clash_config
    import os, base64, json
    
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()
    time.sleep(2)
    
    # 获取多节点UUID
    multi_uuids = os.environ.get('MULTI_UUIDS', '')
    uuid_list = multi_uuids if multi_uuids else UUID
    
    # 生成所有协议节点
    list_txt, isp = generate_all_protocols(argo_domain, uuid_list, CFIP, CFPORT, NAME)
    
    # 写入节点文件
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as f:
        f.write(list_txt)
    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as f:
        f.write(sub_txt)
    
    # 生成Clash配置
    generate_clash_config(argo_domain, uuid_list, CFIP, CFPORT, NAME, isp)
    
    print(f"所有协议节点生成完成: {os.path.join(FILE_PATH, 'list.txt')}")
    print(f"订阅链接已保存: {os.path.join(FILE_PATH, 'sub.txt')}")
    return sub_txt'''
    
    # 替换原有函数
    content = content.replace(
        content[content.find('async def generate_links(argo_domain):'):content.find('async def send_telegram():')],
        new_generate_links
    )

    with open('app.py', 'w', encoding='utf-8') as f:
        f.write(content)
    
    # 保存协议生成器（确保正确的语法结构）
    with open('protocol_generator.py', 'w', encoding='utf-8') as f:
        f.write('import os, base64, json, subprocess, time\n\n')
        f.write('def generate_all_protocols(argo_domain, uuid_list, cfip, cfport, name):\n')
        f.write('    meta_info = subprocess.run([\'curl\', \'-s\', \'https://speed.cloudflare.com/meta\'], capture_output=True, text=True)\n')
        f.write('    meta_info = meta_info.stdout.split(\'"\') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]\n')
        f.write('    isp = f"{meta_info[25]}-{meta_info[17]}".replace(\' \', \'_\').strip()\n\n')
        f.write('    list_txt = ""\n')
        f.write('    uuid_arr = uuid_list.split(\',\') if uuid_list else [uuid_list]\n')
        f.write('    protocols = os.environ.get(\'PROTOCOLS\', \'vless,vmess,trojan\').split(\',\')\n\n')
        f.write('    for i, uuid in enumerate(uuid_arr, 1):\n')
        f.write('        if not uuid: continue\n\n')
        f.write('        if \'vless\' in protocols:\n')
        f.write('            list_txt += f"vless://{uuid}@{cfip}:{cfport}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{name}-{isp}-VLESS-TLS-{i}\\n\\n"\n')
        f.write('            list_txt += f"vless://{uuid}@{cfip}:80?encryption=none&security=none&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{name}-{isp}-VLESS-80-{i}\\n\\n"\n\n')
        f.write('        if \'vmess\' in protocols:\n')
        f.write('            vmess_tls = {\n')
        f.write('                "v": "2", "ps": f"{name}-{isp}-VMESS-TLS-{i}",\n')
        f.write('                "add": cfip, "port": cfport, "id": uuid,\n')
        f.write('                "aid": "0", "scy": "none", "net": "ws",\n')
        f.write('                "type": "none", "host": argo_domain,\n')
        f.write('                "path": "/vmess-argo?ed=2560", "tls": "tls",\n')
        f.write('                "sni": argo_domain, "alpn": "", "fp": "chrome"\n')
        f.write('            }\n')
        f.write('            list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_tls).encode(\'utf-8\')).decode(\'utf-8\')}\\n\\n"\n\n')
        f.write('            vmess_80 = {\n')
        f.write('                "v": "2", "ps": f"{name}-{isp}-VMESS-80-{i}",\n')
        f.write('                "add": cfip, "port": "80", "id": uuid,\n')
        f.write('                "aid": "0", "scy": "none", "net": "ws",\n')
        f.write('                "type": "none", "host": argo_domain,\n')
        f.write('                "path": "/vmess-argo?ed=2560", "tls": ""\n')
        f.write('            }\n')
        f.write('            list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_80).encode(\'utf-8\')).decode(\'utf-8\')}\\n\\n"\n\n')
        f.write('        if \'trojan\' in protocols:\n')
        f.write('            list_txt += f"trojan://{uuid}@{cfip}:{cfport}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{name}-{isp}-Trojan-TLS-{i}\\n\\n"\n')
        f.write('            list_txt += f"trojan://{uuid}@{cfip}:80?security=none&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{name}-{isp}-Trojan-80-{i}\\n\\n"\n\n')
        f.write('    return list_txt, isp\n\n')

        f.write('def generate_clash_config(argo_domain, uuid_list, cfip, cfport, name, isp):\n')
        f.write('    proxies = "proxies:\\n"\n')
        f.write('    uuid_arr = uuid_list.split(\',\') if uuid_list else [uuid_list]\n')
        f.write('    protocols = os.environ.get(\'PROTOCOLS\', \'vless,vmess,trojan\').split(\',\')\n\n')
        f.write('    for i, uuid in enumerate(uuid_arr, 1):\n')
        f.write('        if not uuid: continue\n\n')
        f.write('        if \'vless\' in protocols:\n')
        f.write('            proxies += f\'  - name: "{name}-{isp}-VLESS-TLS-{i}"\\n    type: vless\\n    server: {cfip}\\n    port: {cfport}\\n    uuid: {uuid}\\n    encryption: none\\n    tls: true\\n    servername: {argo_domain}\\n    fp: chrome\\n    network: ws\\n    ws-opts:\\n      path: "/vless-argo?ed=2560"\\n      host: {argo_domain}\\n\\n\'\n\n')
        f.write('        if \'vmess\' in protocols:\n')
        f.write('            proxies += f\'  - name: "{name}-{isp}-VMESS-TLS-{i}"\\n    type: vmess\\n    server: {cfip}\\n    port: {cfport}\\n    uuid: {uuid}\\n    alterId: 0\\n    cipher: auto\\n    tls: true\\n    network: ws\\n    ws-opts:\\n      path: "/vmess-argo?ed=2560"\\n      host: {argo_domain}\\n\\n\'\n\n')
        f.write('        if \'trojan\' in protocols:\n')
        f.write('            proxies += f\'  - name: "{name}-{isp}-Trojan-TLS-{i}"\\n    type: trojan\\n    server: {cfip}\\n    port: {cfport}\\n    password: {uuid}\\n    tls: true\\n    servername: {argo_domain}\\n    fp: chrome\\n    network: ws\\n    ws-opts:\\n      path: "/trojan-argo?ed=2560"\\n      host: {argo_domain}\\n\\n\'\n\n')

        f.write('    # 构建代理组配置\n')
        f.write('    proxy_groups = "proxy-groups:\\n"\n')
        f.write('    proxy_groups += "  - name: \\"自动选择\\"\\n"\n')
        f.write('    proxy_groups += "    type: url-test\\n"\n')
        f.write('    proxy_groups += "    proxies:\\n"\n\n')
        f.write('    for i, uuid in enumerate(uuid_arr, 1):\n')
        f.write('        if not uuid: continue\n')
        f.write('        if \'vless\' in protocols:\n')
        f.write('            proxy_groups += f\'      - "{name}-{isp}-VLESS-TLS-{i}"\\n\'\n')
        f.write('        if \'vmess\' in protocols:\n')
        f.write('            proxy_groups += f\'      - "{name}-{isp}-VMESS-TLS-{i}"\\n\'\n')
        f.write('        if \'trojan\' in protocols:\n')
        f.write('            proxy_groups += f\'      - "{name}-{isp}-Trojan-TLS-{i}"\\n\'\n\n')
        f.write('    proxy_groups += "    url: \\"http://www.gstatic.com/generate_204\\"\\n"\n')
        f.write('    proxy_groups += "    interval: 300\\n"\n')
        f.write('    proxy_groups += "  - name: \\"全局代理\\"\\n"\n')
        f.write('    proxy_groups += "    type: select\\n"\n')
        f.write('    proxy_groups += "    proxies:\\n"\n')
        f.write('    proxy_groups += "      - \\"自动选择\\"\\n"\n')
        f.write('    proxy_groups += "      - \\"DIRECT\\"\\n"\n\n')

        f.write('    # 构建规则配置\n')
        f.write('    rules = "rules:\\n"\n')
        f.write('    rules += "  - DOMAIN-SUFFIX,youtube.com,自动选择\\n"\n')
        f.write('    rules += "  - DOMAIN-SUFFIX,youtu.be,自动选择\\n"\n')
        f.write('    rules += "  - DOMAIN-SUFFIX,googlevideo.com,自动选择\\n"\n\n')
        f.write('    custom_domains = os.environ.get(\'CUSTOM_DOMAINS\', \'\')\n')
        f.write('    if custom_domains:\n')
        f.write('        for domain in custom_domains.split(\',\'):\n')
        f.write('            rules += f\'  - DOMAIN-SUFFIX,{domain.strip()},自动选择\\n\'\n\n')
        f.write('    rules += "  - DOMAIN-SUFFIX,baidu.com,DIRECT\\n"\n')
        f.write('    rules += "  - DOMAIN-SUFFIX,qq.com,DIRECT\\n"\n')
        f.write('    rules += "  - GEOIP,CN,DIRECT\\n"\n')
        f.write('    rules += "  - MATCH,全局代理\\n"\n\n')

        f.write('    # 组合并写入配置\n')
        f.write('    clash_yaml = proxies + proxy_groups + rules\n')
        f.write('    with open(\'clash_config.yaml\', \'w\', encoding=\'utf-8\') as f:\n')
        f.write('        f.write(clash_yaml)\n')
        f.write('    with open(\'clash_sub.txt\', \'w\', encoding=\'utf-8\') as f:\n')
        f.write('        f.write(base64.b64encode(clash_yaml.encode(\'utf-8\')).decode(\'utf-8\'))\n')

# 确保主函数调用正确缩进
def main():
    patch_app_py()

if __name__ == "__main__":
    main()
EOF

# 传递环境变量并执行补丁（确保所有协议被包含）
MULTI_UUIDS="$MULTI_UUIDS" CUSTOM_DOMAINS="$CUSTOM_DOMAINS" PROTOCOLS="${PROTOCOLS[*]}" python3 protocol_patch.py && echo -e "${GREEN}协议节点生成逻辑已注入${NC}"

# 服务启动
echo -e "${BLUE}启动服务...${NC}"
pkill -f "python3 app.py" > /dev/null 2>&1
sleep 2
python3 app.py > app.log 2>&1 &
APP_PID=$!
if [ -z "$APP_PID" ] || [ "$APP_PID" -eq 0 ]; then
    nohup python3 app.py > app.log 2>&1 &
    sleep 2
    APP_PID=$(get_service_pid "python3 app.py")
    [ -z "$APP_PID" ] && echo -e "${RED}服务启动失败，请查看日志：tail -f app.log${NC}" && exit 1
fi
echo -e "${GREEN}主服务已启动（PID: $APP_PID）${NC}"

# 保活服务
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "${BLUE}启动Hugging Face保活服务...${NC}"
    cat > keep_alive_task.sh << EOF
#!/bin/bash
while true; do
    status_code=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/$HF_REPO_ID")
    if [ "\$status_code" -eq 200 ]; then
        echo "Hugging Face保活成功（Space: $HF_REPO_ID）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
    else
        status_code_model=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/models/$HF_REPO_ID")
        if [ "\$status_code_model" -eq 200 ]; then
            echo "Hugging Face保活成功（Model: $HF_REPO_ID）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        else
            echo "Hugging Face保活失败（状态码: \$status_code）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        fi
    fi
    sleep 120
done
EOF
    chmod +x keep_alive_task.sh
    nohup ./keep_alive_task.sh >/dev/null 2>&1 &
    echo -e "${GREEN}保活服务已启动${NC}"
fi

# 等待节点生成并验证
echo -e "${BLUE}等待所有协议节点生成（最多10分钟）...${NC}"
MAX_WAIT=600
WAIT_COUNT=0
NODE_INFO=""
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if [ -f "list.txt" ] && [ -s "list.txt" ]; then
        # 检查是否所有协议都已生成
        if check_protocols_generated "list.txt"; then
            NODE_INFO=$(cat sub.txt)
            break
        else
            echo -e "${YELLOW}节点生成不完整，等待重试...${NC}"
            sleep 10
            WAIT_COUNT=$((WAIT_COUNT + 10))
        fi
    else
        [ $((WAIT_COUNT % 30)) -eq 0 ] && echo -e "${YELLOW}已等待 $((WAIT_COUNT/60)) 分 $((WAIT_COUNT%60)) 秒...${NC}"
        sleep 5
        WAIT_COUNT=$((WAIT_COUNT + 5))
    fi
done

# 部署完成处理
if [ -n "$NODE_INFO" ]; then
    SERVICE_PORT=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    CURRENT_UUID=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    SUB_PATH_VALUE=$(grep "SUB_PATH = " app.py | cut -d"'" -f4)
    PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || "获取失败")
    DECODED_NODES=$(echo "$NODE_INFO" | base64 -d 2>/dev/null || echo "$NODE_INFO")

    # 保存节点信息
    SAVE_INFO="========================================
               所有协议节点信息（${PROTOCOLS[*]}）
========================================
部署时间: $(date)
UUID: $( [ -n "$MULTI_UUIDS" ] && echo "$MULTI_UUIDS" || echo "$CURRENT_UUID" )
服务端口: $SERVICE_PORT
订阅路径: /$SUB_PATH_VALUE
=== 访问地址 ===
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE
本地节点列表: $PROJECT_DIR_NAME/list.txt
=== Clash 信息 ===
配置文件: $PROJECT_DIR_NAME/clash_config.yaml
订阅内容: $(cat clash_sub.txt 2>/dev/null || "生成中")
=== 节点预览 ===
$(echo "$DECODED_NODES" | head -6)
...
=== 管理命令 ===
查看所有节点: cat $PROJECT_DIR_NAME/list.txt
重新生成节点: 菜单4选择"重新生成所有节点"
查看日志: tail -f $PROJECT_DIR_NAME/app.log
"
    echo "$SAVE_INFO" > "$NODE_INFO_FILE"

    # 终端输出
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               部署完成！所有协议节点已生成               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}=== 生成的协议节点 ===${NC}"
    echo -e "支持: ${BLUE}${PROTOCOLS[*]}${NC}"
    echo -e "${YELLOW}=== 节点位置 ===${NC}"
    echo -e "明文列表: ${GREEN}$PROJECT_DIR_NAME/list.txt${NC}"
    echo -e "订阅链接: ${GREEN}http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE${NC}"
    echo -e "${YELLOW}=== 验证结果 ===${NC}"
    check_protocols_generated "$PROJECT_DIR_NAME/list.txt" && \
        echo -e "${GREEN}所有协议节点生成正常${NC}" || \
        echo -e "${RED}部分协议节点缺失，请通过菜单4重新生成${NC}"
else
    echo -e "${RED}等待超时！节点生成失败${NC}"
    echo -e "${YELLOW}错误排查:${NC}"
    echo -e "1. 查看日志: tail -f $PROJECT_DIR_NAME/app.log"
    echo -e "2. 尝试重新生成: 运行脚本选择菜单4->4"
    exit 1
fi

echo -e "${GREEN}最终修复版部署完成！${NC}"
exit 0
