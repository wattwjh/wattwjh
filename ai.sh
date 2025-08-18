
 
#!/bin/bash
# Python Xray Argo 一键部署脚本（终极修复版）
# 功能：生成完整节点（VLESS/VMESS/Trojan）+ Clash配置 + 非中国网站全代理
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 基础配置
NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"
CUSTOM_DOMAINS=""  # 自定义分流域名
MULTI_UUIDS=""     # 多节点UUID
PROTOCOLS=("vless" "vmess" "trojan")  # 支持的协议

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

# 3. 检查协议节点是否完整生成
check_protocols() {
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
        echo "缺失协议: ${missing[*]}"
        return 1
    fi
}

# 4. 子功能：Clash配置管理
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

# 5. 子功能：服务管理
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

# 6. 子功能：日志操作
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

# 7. 主脚本入口
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本（终极版）   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}功能：生成全协议节点 + 非中国网站全代理${NC}"
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

# 8. 依赖安装
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

# 9. 保活配置
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

# 10. 部署配置
echo -e "${BLUE}=== $( [ "$MODE_CHOICE" = "1" ] && echo "极速模式" || echo "完整模式" ) ===${NC}"

# 10.1 UUID配置
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

# 10.2 完整模式配置
if [ "$MODE_CHOICE" = "2" ]; then
    current_name=$(grep "NAME = " app.py | head -1 | cut -d"'" -f4)
    read -p "节点名称（当前: $current_name）: " name_input
    [ -n "$name_input" ] && sed -i "s/NAME = os.environ.get('NAME', '[^']*')/NAME = os.environ.get('NAME', '$name_input')/" app.py

    current_port=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    read -p "服务端口（当前: $current_port）: " port_input
    [ -n "$port_input" ] && sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $port_input)/" app.py

    current_cfip=$(grep "CFIP = " app.py | cut -d"'" -f4)
    read -p "优选IP（当前: $current_cfip）: " cfip_input
    [ -z "$cfip_input" ] && cfip_input="joeyblog.net"
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$cfip_input')/" app.py

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
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
    echo -e "${GREEN}优选IP: joeyblog.net${NC}"
    configure_hf_keep_alive
fi

# 11. 核心修复：生成节点和Clash配置（非中国全代理）
echo -e "${BLUE}生成节点和Clash配置...${NC}"
cat > protocol_patch.py << 'EOF'
#!/usr/bin/env python3
import os, base64, json, subprocess, time

# 全局变量
multi_uuids = os.environ.get('MULTI_UUIDS', '')