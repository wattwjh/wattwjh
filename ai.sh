#!/bin/bash

# 颜色定义（统一两套脚本的颜色 颜色定义（统一两套脚本的颜色方案）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
RE='\033[0m'

# 通用变量（避免冲突，统一前缀）
NODE_INFO_FILE="$HOME/.merged_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"
WORK_DIR="/etc/sing-box"
CONFIG_DIR="$WORK_DIR/config.json"
CLIENT_DIR="$WORK_DIR/url.txt"
SERVER_NAME="sing-box"

# 工具函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 工具函数：生成UUID
generate_uuid() {
    if command_exists uuidgen; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command_exists python3; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

# 工具函数：读取用户输入（带提示）
reading() {
    read -p "$1 " input
    echo "$input"
}

# ====================== Xray Argo 相关功能（来自test.sh） ======================

# Xray Argo 极速配置模式
xray_quick_setup() {
    echo -e "${BLUE}=== 极速配置模式 ===${NC}"
    echo -e "${YELLOW}自动生成UUID并使用默认配置${NC}"
    
    UUID_INPUT=$(generate_uuid)
    echo -e "${GREEN}自动生成UUID: $UUID_INPUT${NC}"
    sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$UUID_INPUT')/" app.py
    
    # 自动设置优选IP
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
    echo -e "${GREEN}优选IP已自动设置为: joeyblog.net${NC}"
    
    # 启动服务
    echo -e "${GREEN}极速配置完成！正在启动服务...${NC}"
    pkill -f "python3 app.py" >/dev/null 2>&1
    nohup python3 app.py > app.log 2>&1 &
    echo -e "${GREEN}服务已启动，日志查看: tail -f app.log${NC}"
}

# Xray Argo 完整配置模式
xray_full_setup() {
    echo -e "${BLUE}=== 完整配置模式 ===${NC}"
    
    # 配置UUID
    current_uuid=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前UUID: $current_uuid${NC}"
    read -p "请输入新的UUID (留空自动生成): " UUID_INPUT
    if [ -z "$UUID_INPUT" ]; then
        UUID_INPUT=$(generate_uuid)
        echo -e "${GREEN}自动生成UUID: $UUID_INPUT${NC}"
    fi
    sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$UUID_INPUT')/" app.py
    
    # 配置服务端口
    current_port=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    echo -e "${YELLOW}当前服务端口: $current_port${NC}"
    read -p "请输入服务端口 (留空保持不变): " PORT_INPUT
    if [ -n "$PORT_INPUT" ]; then
        sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $PORT_INPUT)/" app.py
        echo -e "${GREEN}端口已设置为: $PORT_INPUT${NC}"
    fi
    
    # 配置Argo相关
    current_argo_domain=$(grep "ARGO_DOMAIN = " app.py | cut -d"'" -f4)
    echo -e "${YELLOW}当前Argo域名: $current_argo_domain${NC}"
    read -p "请输入Argo固定隧道域名 (留空保持不变): " ARGO_DOMAIN_INPUT
    if [ -n "$ARGO_DOMAIN_INPUT" ]; then
        sed -i "s|ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '[^']*')|ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '$ARGO_DOMAIN_INPUT')|" app.py
        
        current_argo_auth=$(grep "ARGO_AUTH = " app.py | cut -d"'" -f4)
        echo -e "${YELLOW}当前Argo密钥: $current_argo_auth${NC}"
        read -p "请输入Argo固定隧道密钥: " ARGO_AUTH_INPUT
        if [ -n "$ARGO_AUTH_INPUT" ]; then
            sed -i "s|ARGO_AUTH = os.environ.get('ARGO_AUTH', '[^']*')|ARGO_AUTH = os.environ.get('ARGO_AUTH', '$ARGO_AUTH_INPUT')|" app.py
        fi
        echo -e "${GREEN}Argo配置已更新${NC}"
    fi
    
    # 启动服务
    pkill -f "python3 app.py" >/dev/null 2>&1
    nohup python3 app.py > app.log 2>&1 &
    echo -e "${GREEN}完整配置完成，服务已启动${NC}"
}

# 查看Xray节点信息
xray_show_info() {
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}              Xray节点信息               ${NC}"
        echo -e "${GREEN}========================================${NC}"
        cat "$NODE_INFO_FILE"
    else
        echo -e "${RED}未找到节点信息文件，请先部署Xray服务${NC}"
    fi
}

# ====================== sing-box 相关功能（来自sing-box.sh） ======================

# 防火墙配置函数
allow_port() {
    local has_ufw=0
    local has_firewalld=0
    local has_iptables=0
    local has_ip6tables=0

    command_exists ufw && has_ufw=1
    command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1 && has_firewalld=1
    command_exists iptables && has_iptables=1
    command_exists ip6tables && has_ip6tables=1

    # 允许出站
    [ "$has_ufw" -eq 1 ] && ufw --force default allow outgoing
    [ "$has_firewalld" -eq 1 ] && firewall-cmd --permanent --zone=public --set-target=ACCEPT
    [ "$has_iptables" -eq 1 ] && iptables -P OUTPUT ACCEPT
    [ "$has_ip6tables" -eq 1 ] && ip6tables -P OUTPUT ACCEPT

    # 配置入站规则
    for rule in "$@"; do
        port=${rule%/*}
        proto=${rule#*/}
        [ "$has_ufw" -eq 1 ] && ufw allow in ${port}/${proto}
        [ "$has_firewalld" -eq 1 ] && firewall-cmd --permanent --add-port=${port}/${proto}
        [ "$has_iptables" -eq 1 ] && (iptables -C INPUT -p ${proto} --dport ${port} -j ACCEPT 2>/dev/null || iptables -A INPUT -p ${proto} --dport ${port} -j ACCEPT)
        [ "$has_ip6tables" -eq 1 ] && (ip6tables -C INPUT -p ${proto} --dport ${port} -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p ${proto} --dport ${port} -j ACCEPT)
    done

    [ "$has_firewalld" -eq 1 ] && firewall-cmd --reload
}

# 安装sing-box
singbox_install() {
    echo -e "${BLUE}=== 安装sing-box ===${NC}"
    mkdir -p "$WORK_DIR"
    
    # 检测架构
    local arch=$(uname -m)
    case $arch in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo -e "${RED}不支持的架构${NC}"; return 1 ;;
    esac
    
    # 下载二进制文件
    curl -sLo "$WORK_DIR/sing-box" "https://$ARCH.ssss.nyc.mn/sbx"
    curl -sLo "$WORK_DIR/argo" "https://$ARCH.ssss.nyc.mn/bot"
    chmod +x "$WORK_DIR/sing-boxc.mn/bot"
    chmod +x "$WORK_DIR/sing-box" "$WORK_DIR/argo"
    
    # 生成随机配置
    local vless_port=$((RANDOM % 5000 + 2000))
    local uuid=$(generate_uuid)
    local output=$("$WORK_DIR/sing-box" generate reality-keypair)
    local private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
    
    # 生成配置文件
    cat > "$CONFIG_DIR" << EOF
{
  "log": {
    "level": "error",
    "output": "$WORK_DIR/sb.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "type": "vless",
      "listen_port": $vless_port,
      "users": [{"uuid": "$uuid"}],
      "tls": {
        "enabled": true,
        "reality": {
          "enabled": true,
          "private_key": "$private_key",
          "handshake": {"server": "www.bing.com", "server_port": 443}
        }
      }
    }
  ],
  "outbounds": [{"type": "direct"}]
}
EOF
    
    # 放行端口
    allow_port "$vless_port/tcp"
    echo -e "${GREEN}sing-box安装完成，端口: $vless_port${NC}"
}

# 修改sing-box端口
singbox_change_port() {
    if [ ! -f "$CONFIG_DIR" ]; then
        echo -e "${RED}未找到sing-box配置文件，请先安装${NC}"
        return 1
    fi
    
    read -p "请输入新端口 (留空随机): " new_port
    [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
    
    # 更新vless端口
    sed -i '/"type": "vless"/,/listen_port/ s/"listen_port": [0-9]\+/"listen_port": '"$new_port"'/' "$CONFIG_DIR"
    allow_port "$new_port/tcp" >/dev/null 2>&1
    echo -e "${GREEN}sing-box端口已修改为: $new_port${NC}"
}

# ====================== 主菜单 ======================

main_menu() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}        Xray+sing-box 合并工具          ${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    echo -e "${BLUE}【Xray Argo 功能】${NC}"
    echo -e "1) 极速部署 Xray Argo"
    echo -e "2) 完整配置 Xray Argo"
    echo -e "3) 查看 Xray 节点信息\n"
    
    echo -e "${PURPLE}【sing-box 功能】${NC}"
    echo -e "4) 安装 sing-box"
    echo -e "5) 修改 sing-box 端口"
    echo -e "6) 查看 sing-box 状态\n"
    
    echo -e "${RED}0) 退出脚本${NC}\n"
    
    read -p "请选择操作 [0-6]: " choice
    case $choice in
        1) 
            [ ! -d "$PROJECT_DIR_NAME" ] && git clone https://github.com/eooce/python-xray-argo.git "$PROJECT_DIR_NAME"
            cd "$PROJECT_DIR_NAME" && xray_quick_setup && cd ..
            read -p "按回车返回菜单..." ;;
        2) 
            [ ! -d "$PROJECT_DIR_NAME" ] && git clone https://github.com/eooce/python-xray-argo.git "$PROJECT_DIR_NAME"
            cd "$PROJECT_DIR_NAME" && xray_full_setup && cd ..
            read -p "按回车返回菜单..." ;;
        3) 
            xray_show_info
            read -p "按回车返回菜单..." ;;
        4) 
            singbox_install
            read -p "按回车返回菜单..." ;;
        5) 
            singbox_change_port
            read -p "按回车返回菜单..." ;;
        6) 
            if command_exists systemctl; then
                systemctl status sing-box || echo -e "${RED}sing-box未运行${NC}"
            else
                echo -e "${YELLOW}请手动检查: $WORK_DIR/sing-box status${NC}"
            fi
            read -p "按回车返回菜单..." ;;
        0) 
            echo -e "${GREEN}退出脚本，感谢使用！${NC}"
            exit 0 ;;
        *) 
            echo -e "${RED}无效选择，请重试${NC}"
            read -p "按回车返回菜单..." ;;
    esac
    main_menu
}

# 启动主菜单
main_menu
