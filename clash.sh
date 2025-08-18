#!/bin/bash
# Python Xray Argo 一键部署脚本（修复版：含Clash支持+格式修正）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 基础配置
NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"
CUSTOM_DOMAINS=""  # 自定义分流域名（全局变量）
MULTI_UUIDS=""     # 多节点UUID（全局变量）

# 1. 工具函数：生成UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

# 2. 工具函数：检查服务PID
get_service_pid() {
    local service_key=$1
    pgrep -f "$service_key" | head -1
}

# 3. 子功能：Clash配置管理
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
                echo -e "${GREEN}Clash 订阅链接（已复制到剪贴板，需安装xclip）：${NC}"
                echo "$clash_sub" | xclip -selection clipboard 2>/dev/null || echo "$clash_sub"
                [ $? -eq 0 ] && echo -e "${YELLOW}订阅链接已复制到剪贴板${NC}"
            else
                echo -e "${RED}Clash 订阅文件未生成${NC}"
            fi
            ;;
    esac
    exit 0
}

# 4. 子功能：服务管理
service_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               服务管理               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 启动主服务${NC}"
    echo -e "${BLUE}2) 停止主服务${NC}"
    echo -e "${BLUE}3) 重启主服务${NC}"
    echo -e "${BLUE}4) 停止保活服务${NC}"
    read -p "请输入选择 (1-4): " SERVICE_CHOICE

    local app_pid=$(get_service_pid "python3 app.py")
    local keepalive_pid=$(get_service_pid "keep_alive_task.sh")

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
            if [ -n "$keepalive_pid" ]; then
                kill "$keepalive_pid" && rm -f keep_alive_status.log
                echo -e "${GREEN}保活服务已停止（PID: $keepalive_pid）${NC}"
            else
                echo -e "${RED}保活服务未运行${NC}"
            fi
            ;;
    esac
    exit 0
}

# 5. 子功能：日志操作
log_manage() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               日志操作               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${BLUE}1) 实时查看主服务日志${NC}"
    echo -e "${BLUE}2) 查看保活状态日志${NC}"
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
            if [ -f "$log_dir/keep_alive_status.log" ]; then
                cat "$log_dir/keep_alive_status.log"
            else
                echo -e "${RED}保活日志不存在（路径：$log_dir/keep_alive_status.log）${NC}"
            fi
            ;;
        3)
            rm -f "$log_dir/app.log" "$log_dir/keep_alive_status.log"
            echo -e "${GREEN}所有日志已清理（路径：$log_dir）${NC}"
            ;;
    esac
    exit 0
}

# 6. 主脚本入口
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本（修复版）   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}支持协议：VLESS/VMESS/Trojan（兼容Clash客户端）${NC}"
echo -e "${BLUE}核心功能：Clash配置生成、多节点管理、服务运维${NC}"
echo

# 主菜单
echo -e "${YELLOW}请选择操作:${NC}"
echo -e "${BLUE}1) 极速模式 - 只修改UUID并启动${NC}"
echo -e "${BLUE}2) 完整模式 - 详细配置（多节点/分流/Clash）${NC}"
echo -e "${BLUE}3) Clash 管理 - 查看/导出Clash配置${NC}"
echo -e "${BLUE}4) 服务管理 - 启停/重启主服务/保活服务${NC}"
echo -e "${BLUE}5) 日志操作 - 查看/清理服务日志${NC}"
echo -e "${BLUE}6) 查看节点信息 - 显示已保存的节点信息${NC}"
echo -e "${BLUE}7) 查看保活状态 - 检查Hugging Face API保活状态${NC}"
echo
read -p "请输入选择 (1-7): " MODE_CHOICE

# 菜单分支处理
case $MODE_CHOICE in
    3) clash_manage ;;
    4) service_manage ;;
    5) log_manage ;;
    7)
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}               Hugging Face API 保活状态检查              ${NC}"
        echo -e "${GREEN}========================================${NC}"
        if [ -d "$PROJECT_DIR_NAME" ]; then cd "$PROJECT_DIR_NAME"; fi
        local keepalive_pid=$(get_service_pid "keep_alive_task.sh")
        if [ -n "$keepalive_pid" ]; then
            echo -e "服务状态: ${GREEN}运行中${NC}"
            echo -e "进程PID: ${BLUE}$keepalive_pid${NC}"
            if [ -f "keep_alive_task.sh" ]; then
                local repo_id=$(grep 'huggingface.co/api/spaces/' keep_alive_task.sh | head -1 | sed -n 's|.*api/spaces/\([^"]*\).*|\1|p')
                echo -e "目标仓库: ${YELLOW}$repo_id (类型: Space)${NC}"
            fi
            echo -e "\n${YELLOW}--- 最近一次保活状态 ---${NC}"
            [ -f "keep_alive_status.log" ] && cat "keep_alive_status.log" || echo -e "${YELLOW}尚未生成状态日志（最多等2分钟）${NC}"
        else
            echo -e "服务状态: ${RED}未运行${NC}"
            echo -e "${YELLOW}提示: 需在部署时设置Hugging Face保活${NC}"
        fi
        exit 0
        ;;
    6)
        if [ -f "$NODE_INFO_FILE" ]; then
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}                      节点信息查看                      ${NC}"
            echo -e "${GREEN}========================================${NC}"
            cat "$NODE_INFO_FILE"
            echo -e "${YELLOW}提示: Clash配置路径：$PROJECT_DIR_NAME/clash_config.yaml${NC}"
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

# 7. 依赖安装
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
cp app.py app.py.backup_"$(date +%Y%m%d_%H%M)"  # 配置自动备份
echo -e "${GREEN}依赖安装完成！${NC}"

# 8. 保活配置
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

# 9. 部署配置（支持多节点+自定义分流）
echo -e "${BLUE}=== $( [ "$MODE_CHOICE" = "1" ] && echo "极速模式" || echo "完整模式" ) ===${NC}"

# 9.1 UUID配置（多节点支持）
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

# 9.2 完整模式额外配置（自定义分流）
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
    # 极速模式：自动配置优选IP+保活
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
    echo -e "${GREEN}优选IP已设置: joeyblog.net${NC}"
    configure_hf_keep_alive
fi

# 10. 生成YouTube分流+Clash配置（核心功能）
echo -e "${BLUE}生成YouTube分流+Clash配置...${NC}"
cat > youtube_patch.py << 'EOF'
#!/usr/bin/env python3
# coding: utf-8
import os, base64, json, subprocess, time

# 读取全局变量（从环境变量获取）
multi_uuids = os.environ.get('MULTI_UUIDS', '')
custom_domains = os.environ.get('CUSTOM_DOMAINS', '')

# 函数1：生成Clash YAML配置
def generate_clash_yaml(argo_domain, uuid_list, cfip, cfport, name):
    # 获取ISP信息
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]
    isp = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    # 1. 生成多节点配置
    proxies = "proxies:\n"
    uuid_arr = uuid_list.split(',') if uuid_list else [uuid_list]
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        # VLESS-TLS
        proxies += f'  - name: "{name}-{isp}-VLESS-TLS-{i}"\n    type: vless\n    server: {cfip}\n    port: {cfport}\n    uuid: {uuid}\n    encryption: none\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/vless-argo?ed=2560"\n      host: {argo_domain}\n\n'
        # VMESS-80
        proxies += f'  - name: "{name}-{isp}-VMESS-80-{i}"\n    type: vmess\n    server: {cfip}\n    port: 80\n    uuid: {uuid}\n    alterId: 0\n    cipher: auto\n    tls: false\n    network: ws\n    ws-opts:\n      path: "/vmess-argo?ed=2560"\n      host: {argo_domain}\n\n'
        # Trojan-TLS
        proxies += f'  - name: "{name}-{isp}-Trojan-TLS-{i}"\n    type: trojan\n    server: {cfip}\n    port: {cfport}\n    password: {uuid}\n    tls: true\n    servername: {argo_domain}\n    fp: chrome\n    network: ws\n    ws-opts:\n      path: "/trojan-argo?ed=2560"\n      host: {argo_domain}\n\n'

    # 2. 代理组配置
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
  - name: "YouTube 分流"
    type: select
    proxies:
      - "自动选择"
      - "DIRECT"
'''

    # 3. 分流规则（含自定义域名）
    rules = '''rules:
  # YouTube分流
  - DOMAIN-SUFFIX,youtube.com,YouTube 分流
  - DOMAIN-SUFFIX,youtu.be,YouTube 分流
  - DOMAIN-SUFFIX,googlevideo.com,YouTube 分流
'''
    # 添加自定义分流
    if custom_domains:
        for domain in custom_domains.split(','):
            rules += f'  - DOMAIN-SUFFIX,{domain.strip()},全局代理\n'
    # 默认规则
    rules += '''  # 国内直连
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - GEOIP,CN,DIRECT
  # 兜底规则
  - MATCH,全局代理
'''

    # 合并并写入文件
    clash_yaml = proxies + proxy_groups + rules
    with open('clash_config.yaml', 'w', encoding='utf-8') as f:
        f.write(clash_yaml)
    # 生成Clash订阅（base64编码）
    clash_sub = base64.b64encode(clash_yaml.encode('utf-8')).decode('utf-8')
    with open('clash_sub.txt', 'w', encoding='utf-8') as f:
        f.write(clash_sub)
    print(f"Clash配置生成完成：clash_config.yaml")
    print(f"Clash订阅生成完成：clash_sub.txt")
    return clash_yaml, clash_sub

# 函数2：修改app.py（YouTube分流+多节点支持）
def patch_app_py():
    with open('app.py', 'r', encoding='utf-8') as f:
        content = f.read()

    # 替换Xray配置（含YouTube分流）
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
                "streamSettings": {"network": "tcp"}
            },
            {
                "port": 3001,
                "listen": "127.0.0.1",
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": UUID}],
                    "decryption": "none"
                },
                "streamSettings": {"network": "ws", "security": "none"}
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
                    "wsSettings": {"path": "/vless-argo"}
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
                    "wsSettings": {"path": "/vmess-argo"}
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
                    "wsSettings": {"path": "/trojan-argo"}
                },
                "sniffing": {
                    "enabled": True,
                    "destOverride": ["http", "tls", "quic"],
                    "metadataOnly": False
                }
            }
        ],
        "outbounds": [
            {"protocol": "freedom", "tag": "direct"},
            {
                "protocol": "vmess",
                "tag": "youtube",
                "settings": {
                    "vnext": [{
                        "address": "172.233.171.224",
                        "port": 16416,
                        "users": [{
                            "id": "8c1b9bea-cb51-43bb-a65c-0af31bbbf145",
                            "alterId": 0
                        }]
                    }]
                },
                "streamSettings": {"network": "tcp"}
            },
            {"protocol": "blackhole", "tag": "block"}
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {
                    "type": "field",
                    "domain": [
                        "youtube.com", "youtu.be",
                        "googlevideo.com", "ytimg.com",
                        "gstatic.com", "googleapis.com"
                    ],
                    "outboundTag": "youtube"
                }
            ]
        }
    }'''
    content = content.replace(old_config, new_config)

    # 替换generate_links函数（支持多节点+Clash）
    old_generate = '''# Generate links and subscription content
async def generate_links(argo_domain):
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
    new_generate = '''# Generate links and subscription content
async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"') if meta_info.stdout else ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "Unknown", "", "", "", "", "", "", "", "Unknown"]
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()
    time.sleep(2)
    
    # 生成多节点配置
    list_txt = ""
    multi_uuids = os.environ.get('MULTI_UUIDS', '')
    uuid_arr = multi_uuids.split(',') if multi_uuids else [UUID]
    for i, uuid in enumerate(uuid_arr, 1):
        if not uuid: continue
        # VLESS-TLS
        list_txt += f"vless://{uuid}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-TLS-{i}\\n\\n"
        # VMESS-TLS
        vmess_tls = {"v": "2", "ps": f"{NAME}-{ISP}-VMESS-TLS-{i}", "add": CFIP, "port": CFPORT, "id": uuid, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "tls", "sni": argo_domain, "alpn": "", "fp": "chrome"}
        list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_tls).encode('utf-8')).decode('utf-8')}\\n\\n"
        # Trojan-TLS
        list_txt += f"trojan://{uuid}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-TLS-{i}\\n\\n"
        # VLESS-80（无TLS）
        list_txt += f"vless://{uuid}@{CFIP}:80?encryption=none&security=none&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-80-{i}\\n\\n"
        # VMESS-80（无TLS）
        vmess_80 = {"v": "2", "ps": f"{NAME}-{ISP}-VMESS-80-{i}", "add": CFIP, "port": "80", "id": uuid, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "", "sni": "", "alpn": "", "fp": ""}
        list_txt += f"vmess://{base64.b64encode(json.dumps(vmess_80).encode('utf-8')).decode('utf-8')}\\n\\n"
        # Trojan-80（无TLS）
        list_txt += f"trojan://{uuid}@{CFIP}:80?security=none&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-80-{i}\\n\\n"
    
    # 写入节点列表和订阅
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)
    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
    
    # 生成Clash配置
    from __main__ import generate_clash_yaml
    generate_clash_yaml(argo_domain, multi_uuids if multi_uuids else UUID, CFIP, CFPORT, NAME)
    
    print(sub_txt)
    print(f"{FILE_PATH}/sub.txt saved successfully")
    
    # Additional actions
    send_telegram()
    upload_nodes()
    return sub_txt'''
    content = content.replace(old_generate, new_generate)

    # 写入修改后的app.py
    with open('app.py', 'w', encoding='utf-8') as f:
        f.write(content)
    print("app.py修改完成（YouTube分流+多节点支持）")

# 执行补丁
if __name__ == "__main__":
    patch_app_py()
EOF

# 传递环境变量并执行补丁脚本（确保Clash生成函数获取到多节点和自定义分流参数）
MULTI_UUIDS="$MULTI_UUIDS" CUSTOM_DOMAINS="$CUSTOM_DOMAINS" python3 youtube_patch.py && rm youtube_patch.py
echo -e "${GREEN}YouTube分流+Clash配置集成完成！${NC}"

# 11. 服务启动
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

# 12. 保活服务启动
KEEPALIVE_PID=""
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "${BLUE}启动Hugging Face保活服务...${NC}"
    cat > keep_alive_task.sh << EOF
#!/bin/bash
while true; do
    # 尝试Spaces API
    status_code=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/$HF_REPO_ID")
    if [ "\$status_code" -eq 200 ]; then
        echo "Hugging Face保活成功（Space: $HF_REPO_ID）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
    else
        # 尝试Models API
        status_code_model=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/models/$HF_REPO_ID")
        if [ "\$status_code_model" -eq 200 ]; then
            echo "Hugging Face保活成功（Model: $HF_REPO_ID）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        else
            echo "Hugging Face保活失败（Space状态: \$status_code, Model状态: \$status_code_model）- \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        fi
    fi
    sleep 120
done
EOF
    chmod +x keep_alive_task.sh
    nohup ./keep_alive_task.sh >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
    echo -e "${GREEN}保活服务已启动（PID: $KEEPALIVE_PID）${NC}"
fi

# 13. 节点信息等待与保存（含Clash信息）
echo -e "${BLUE}等待节点信息生成（最多10分钟）...${NC}"
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

# 14. 部署完成输出（强化Clash信息显示）
if [ -n "$NODE_INFO" ]; then
    SERVICE_PORT=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    CURRENT_UUID=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    SUB_PATH_VALUE=$(grep "SUB_PATH = " app.py | cut -d"'" -f4)
    PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || "获取失败")
    DECODED_NODES=$(echo "$NODE_INFO" | base64 -d 2>/dev/null || echo "$NODE_INFO")

    # 确保Clash配置已生成（兜底检查）
    if [ ! -f "clash_config.yaml" ]; then
        echo -e "${YELLOW}Clash配置生成延迟，正在手动补充...${NC}"
        UUID=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
        CFIP=$(grep "CFIP = " app.py | cut -d"'" -f4)
        CFPORT=$(grep "CFPORT = " app.py | cut -d"'" -f4)
        NAME=$(grep "NAME = " app.py | head -1 | cut -d"'" -f4)
        ISP=$(curl -s https://speed.cloudflare.com/meta | grep -oP '"colo":"\K[^"]+' || echo "Unknown")
        
        cat > clash_config.yaml << EOF
proxies:
  - name: "${NAME}-${ISP}-VLESS"
    type: vless
    server: ${CFIP}
    port: ${CFPORT}
    uuid: ${UUID}
    encryption: none
    tls: true
    servername: ${CFIP}
    network: ws
    ws-opts:
      path: "/vless-argo?ed=2560"
      host: ${CFIP}

  - name: "${NAME}-${ISP}-VMESS"
    type: vmess
    server: ${CFIP}
    port: ${CFPORT}
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    tls: true
    network: ws
    ws-opts:
      path: "/vmess-argo?ed=2560"
      host: ${CFIP}

proxy-groups:
  - name: "自动选择"
    type: url-test
    proxies:
      - "${NAME}-${ISP}-VLESS"
      - "${NAME}-${ISP}-VMESS"
    url: "http://www.gstatic.com/generate_204"
    interval: 300

rules:
  - DOMAIN-SUFFIX,youtube.com,自动选择
  - MATCH,自动选择
EOF
        base64 clash_config.yaml > clash_sub.txt
    fi

    # 保存节点信息（含Clash）
    SAVE_INFO="========================================
                      节点信息保存                      
========================================
部署时间: $(date)
UUID: $( [ -n "$MULTI_UUIDS" ] && echo "$MULTI_UUIDS" || echo "$CURRENT_UUID" )
服务端口: $SERVICE_PORT
订阅路径: /$SUB_PATH_VALUE
=== 访问地址 ===
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE
管理面板: http://$PUBLIC_IP:$SERVICE_PORT
本地订阅: http://localhost:$SERVICE_PORT/$SUB_PATH_VALUE
=== Clash 专属地址 ===
Clash配置文件: $PROJECT_DIR_NAME/clash_config.yaml
Clash订阅内容: $(cat clash_sub.txt 2>/dev/null || "生成中")
=== 节点信息 ===
$DECODED_NODES
=== 管理命令 ===
查看日志: tail -f $PROJECT_DIR_NAME/app.log
停止主服务: kill $APP_PID
重启主服务: kill $APP_PID && nohup python3 $PROJECT_DIR_NAME/app.py > $PROJECT_DIR_NAME/app.log 2>&1 &
$( [ -n "$KEEPALIVE_PID" ] && echo "停止保活服务: kill $KEEPALIVE_PID && rm $PROJECT_DIR_NAME/keep_alive_status.log" )
=== 功能说明 ===
- 支持VLESS/VMESS/Trojan协议（兼容Clash客户端）
- 已集成YouTube分流+自定义分流（域名：$CUSTOM_DOMAINS）
- 多节点配置：$( [ -n "$MULTI_UUIDS" ] && echo "已启用（$MULTI_UUIDS）" || echo "未启用" )
"
    echo "$SAVE_INFO" > "$NODE_INFO_FILE"

    # 终端输出
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}                      部署完成！                      ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}=== 服务信息 ===${NC}"
    echo -e "主服务PID: ${BLUE}$APP_PID${NC}"
    [ -n "$KEEPALIVE_PID" ] && echo -e "保活服务PID: ${BLUE}$KEEPALIVE_PID${NC}"
    echo -e "服务端口: ${BLUE}$SERVICE_PORT${NC}"
    echo -e "${YELLOW}=== Clash 信息 ===${NC}"
    echo -e "配置文件: ${GREEN}$PROJECT_DIR_NAME/clash_config.yaml${NC}"
    echo -e "订阅链接: ${GREEN}$(cat clash_sub.txt 2>/dev/null)${NC}"
    echo -e "${YELLOW}=== 节点订阅 ===${NC}"
    echo -e "公网订阅: ${GREEN}http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE${NC}"
    echo -e "节点信息已保存至: ${GREEN}$NODE_INFO_FILE${NC}"
else
    echo -e "${RED}等待超时！节点信息未生成${NC}"
    echo -e "${YELLOW}查看日志: tail -f $PROJECT_DIR_NAME/app.log${NC}"
    exit 1
fi

echo -e "${GREEN}修复版部署完成！Clash配置已确保生成！${NC}"
exit 0
