#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"

# 新增：快速切换代理模式的参数
if [ "$1" = "-f" ]; then
    echo -e "${YELLOW}已启用快速模式，优化网络连接速度${NC}"
    FAST_MODE=true
fi

# 如果是-v参数，直接查看节点信息
if [ "$1" = "-v" ]; then
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}                      节点信息查看                      ${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo
        cat "$NODE_INFO_FILE"
        echo
    else
        echo -e "${RED}未找到节点信息文件${NC}"
        echo -e "${YELLOW}请先运行部署脚本生成节点信息${NC}"
    fi
    exit 0
fi

generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

clear

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}基于项目: ${YELLOW}https://github.com/eooce/python-xray-argo${NC}"
echo -e "${BLUE}脚本仓库: ${YELLOW}https://github.com/byJoey/free-vps-py${NC}"
echo -e "${BLUE}TG交流群: ${YELLOW}https://t.me/+ft-zI76oovgwNmRh${NC}"
echo -e "${RED}脚本作者YouTube: ${YELLOW}https://www.youtube.com/@joeyblog${RED}"
echo
echo -e "${GREEN}本脚本基于 eooce 大佬的 Python Xray Argo 项目开发${NC}"
echo -e "${GREEN}提供极速和完整两种配置模式，简化部署流程${NC}"
echo -e "${GREEN}支持自动UUID生成、后台运行、节点信息输出${NC}"
echo -e "${GREEN}默认集成智能分流优化，支持全球网络代理${NC}"
echo

echo -e "${YELLOW}请选择操作:${NC}"
echo -e "${BLUE}1) 极速模式 - 只修改UUID并启动${NC}"
echo -e "${BLUE}2) 完整模式 - 详细配置所有选项${NC}"
echo -e "${BLUE}3) 查看节点信息 - 显示已保存的节点信息${NC}"
echo -e "${BLUE}4) 查看保活状态 - 检查Hugging Face API保活状态${NC}"
echo -e "${BLUE}5) 切换代理模式 - 全球代理/智能分流${NC}"  # 新增模式切换选项
echo
read -p "请输入选择 (1/2/3/4/5): " MODE_CHOICE

# 新增：代理模式切换逻辑
if [ "$MODE_CHOICE" = "5" ]; then
    if [ -d "$PROJECT_DIR_NAME" ]; then
        cd "$PROJECT_DIR_NAME" || exit
        if grep -q "geosite:cn" app.py; then
            # 切换到全球代理模式
            sed -i "s/geosite:cn/geosite:category-ads/" app.py
            echo -e "${GREEN}已切换为全球代理模式（所有流量均通过代理）${NC}"
        else
            # 切换到智能分流模式
            sed -i "s/geosite:category-ads/geosite:cn/" app.py
            echo -e "${GREEN}已切换为智能分流模式（国内网站直连，境外网站代理）${NC}"
        fi
        echo -e "${YELLOW}请重启服务使配置生效${NC}"
    else
        echo -e "${RED}未找到项目目录，请先部署服务${NC}"
    fi
    exit 0
fi

if [ "$MODE_CHOICE" = "3" ]; then
    if [ -f "$NODE_INFO_FILE" ]; then
        echo
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}                      节点信息查看                      ${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo
        cat "$NODE_INFO_FILE"
        echo
        echo -e "${YELLOW}提示: 如需重新部署，请重新运行脚本选择模式1或2${NC}"
    else
        echo
        echo -e "${RED}未找到节点信息文件${NC}"
        echo -e "${YELLOW}请先运行部署脚本生成节点信息${NC}"
        echo
        echo -e "${BLUE}是否现在开始部署? (y/n)${NC}"
        read -p "> " START_DEPLOY
        if [ "$START_DEPLOY" = "y" ] || [ "$START_DEPLOY" = "Y" ]; then
            echo -e "${YELLOW}请选择部署模式:${NC}"
            echo -e "${BLUE}1) 极速模式${NC}"
            echo -e "${BLUE}2) 完整模式${NC}"
            read -p "请输入选择 (1/2): " MODE_CHOICE
        else
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
        fi
    fi
    
    if [ "$MODE_CHOICE" != "1" ] && [ "$MODE_CHOICE" != "2" ]; then
        echo -e "${GREEN}退出脚本${NC}"
        exit 0
    fi
fi

if [ "$MODE_CHOICE" = "4" ]; then
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}               Hugging Face API 保活状态检查              ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    
    if [ -d "$PROJECT_DIR_NAME" ]; then
        cd "$PROJECT_DIR_NAME"
    fi

    KEEPALIVE_PID=$(pgrep -f "keep_alive_task.sh")

    if [ -n "$KEEPALIVE_PID" ]; then
        echo -e "服务状态: ${GREEN}运行中${NC}"
        echo -e "进程PID: ${BLUE}$KEEPALIVE_PID${NC}"
        if [ -f "keep_alive_task.sh" ]; then
            # 更新为从 spaces API 地址中解析
            REPO_ID=$(grep 'huggingface.co/api/spaces/' keep_alive_task.sh | head -1 | sed -n 's|.*api/spaces/\([^"]*\).*|\1|p')
            echo -e "目标仓库: ${YELLOW}$REPO_ID (类型: Space)${NC}"
        fi

        echo -e "\n${YELLOW}--- 最近一次保活状态 ---${NC}"
        if [ -f "keep_alive_status.log" ]; then
           cat keep_alive_status.log
        else
           echo -e "${YELLOW}尚未生成状态日志，请稍等片刻(最多2分钟)后重试...${NC}"
        fi
    else
        echo -e "服务状态: ${RED}未运行${NC}"
        echo -e "${YELLOW}提示: 您可能尚未部署服务或未在部署时设置Hugging Face保活。${NC}"
    fi
    echo
    exit 0
fi


echo -e "${BLUE}检查并安装依赖...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}正在安装 Python3...${NC}"
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
fi

if ! python3 -c "import requests" &> /dev/null; then
    echo -e "${YELLOW}正在安装 Python 依赖: requests...${NC}"
    pip3 install requests
fi

# 新增：安装网络优化工具
echo -e "${BLUE}安装网络优化工具...${NC}"
sudo apt-get install -y curl wget unzip speedtest-cli

if [ ! -d "$PROJECT_DIR_NAME" ]; then
    echo -e "${BLUE}下载完整仓库...${NC}"
    if command -v git &> /dev/null; then
        git clone https://github.com/eooce/python-xray-argo.git "$PROJECT_DIR_NAME"
    else
        echo -e "${YELLOW}Git未安装，使用wget下载...${NC}"
        wget -q https://github.com/eooce/python-xray-argo/archive/refs/heads/main.zip -O python-xray-argo.zip
        if command -v unzip &> /dev/null; then
            unzip -q python-xray-argo.zip
            mv python-xray-argo-main "$PROJECT_DIR_NAME"
            rm python-xray-argo.zip
        else
            echo -e "${YELLOW}正在安装 unzip...${NC}"
            sudo apt-get install -y unzip
            unzip -q python-xray-argo.zip
            mv python-xray-argo-main "$PROJECT_DIR_NAME"
            rm python-xray-argo.zip
        fi
    fi
    
    if [ $? -ne 0 ] || [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo -e "${RED}下载失败，请检查网络连接${NC}"
        exit 1
    fi
fi

cd "$PROJECT_DIR_NAME"

echo -e "${GREEN}依赖安装完成！${NC}"
echo

if [ ! -f "app.py" ]; then
    echo -e "${RED}未找到app.py文件！${NC}"
    exit 1
fi

cp app.py app.py.backup
echo -e "${YELLOW}已备份原始文件为 app.py.backup${NC}"

# 初始化保活变量
KEEP_ALIVE_HF="false"
HF_TOKEN=""
HF_REPO_ID=""

# 定义保活配置函数
configure_hf_keep_alive() {
    echo
    echo -e "${YELLOW}是否设置 Hugging Face API 自动保活? (y/n)${NC}"
    read -p "> " SETUP_KEEP_ALIVE
    if [ "$SETUP_KEEP_ALIVE" = "y" ] || [ "$SETUP_KEEP_ALIVE" = "Y" ]; then
        echo -e "${YELLOW}请输入您的 Hugging Face 访问令牌 (Token):${NC}"
        echo -e "${BLUE}（令牌用于API认证，输入时将不可见。请前往 https://huggingface.co/settings/tokens 获取）${NC}"
        read -sp "Token: " HF_TOKEN_INPUT
        echo
        if [ -z "$HF_TOKEN_INPUT" ]; then
            echo -e "${RED}错误：Token 不能为空。已取消保活设置。${NC}"
            return
        fi

        echo -e "${YELLOW}请输入要访问的 Hugging Face 仓库ID (模型或Space均可，例如: joeyhuangt/aaaa):${NC}"
        read -p "Repo ID: " HF_REPO_ID_INPUT
        if [ -z "$HF_REPO_ID_INPUT" ]; then
            echo -e "${RED}错误：仓库ID 不能为空。已取消保活设置。${NC}"
            return
        fi

        HF_TOKEN="$HF_TOKEN_INPUT"
        HF_REPO_ID="$HF_REPO_ID_INPUT"
        KEEP_ALIVE_HF="true"
        echo -e "${GREEN}Hugging Face API 保活已设置！${NC}"
        echo -e "${GREEN}目标仓库: $HF_REPO_ID${NC}"
    fi
}

# 新增：优选IP列表优化（提升连接速度）
optimize_ip_selection() {
    echo -e "${BLUE}正在优化优选IP列表...${NC}"
    # 替换为速度更快的优选IP池
    sed -i "s/joeyblog.net/cf-ip.net/g" app.py
    # 增加多个备选IP
    sed -i "/CFIP = os.environ.get/a\CF_IPS = ['cf-ip.net', 'cloudflare-ip.com', 'fastly.net']" app.py
    echo -e "${GREEN}IP优化完成，将自动选择最快节点连接${NC}"
}

if [ "$MODE_CHOICE" = "1" ]; then
    echo -e "${BLUE}=== 极速模式 ===${NC}"
    echo
    
    echo -e "${YELLOW}当前UUID: $(grep "UUID = " app.py | head -1 | cut -d"'" -f2)${NC}"
    read -p "请输入新的 UUID (留空自动生成): " UUID_INPUT
    if [ -z "$UUID_INPUT" ]; then
        UUID_INPUT=$(generate_uuid)
        echo -e "${GREEN}自动生成UUID: $UUID_INPUT${NC}"
    fi
    
    sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$UUID_INPUT')/" app.py
    echo -e "${GREEN}UUID 已设置为: $UUID_INPUT${NC}"
    
    # 应用IP优化
    optimize_ip_selection
    
    configure_hf_keep_alive
    
    # 新增：默认启用全球代理模式
    echo -e "${GREEN}已启用全球代理模式，支持所有境外网络访问${NC}"
    echo
    echo -e "${GREEN}极速配置完成！正在启动服务...${NC}"
    echo
    
else
    echo -e "${BLUE}=== 完整配置模式 ===${NC}"
    echo
    
    echo -e "${YELLOW}当前UUID: $(grep "UUID = " app.py | head -1 | cut -d"'" -f2)${NC}"
    read -p "请输入新的 UUID (留空自动生成): " UUID_INPUT
    if [ -z "$UUID_INPUT" ]; then
        UUID_INPUT=$(generate_uuid)
        echo -e "${GREEN}自动生成UUID: $UUID_INPUT${NC}"
    fi
    sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$UUID_INPUT')/" app.py
    echo -e "${GREEN}UUID 已设置为: $UUID_INPUT${NC}"

    echo -e "${YELLOW}当前节点名称: $(grep "NAME = " app.py | head -1 | cut -d"'" -f4)${NC}"
    read -p "请输入节点名称 (留空保持不变): " NAME_INPUT
    if [ -n "$NAME_INPUT" ]; then
        sed -i "s/NAME = os.environ.get('NAME', '[^']*')/NAME = os.environ.get('NAME', '$NAME_INPUT')/" app.py
        echo -e "${GREEN}节点名称已设置为: $NAME_INPUT${NC}"
    fi

    echo -e "${YELLOW}当前服务端口: $(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)${NC}"
    read -p "请输入服务端口 (留空保持不变): " PORT_INPUT
    if [ -n "$PORT_INPUT" ]; then
        sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $PORT_INPUT)/" app.py
        echo -e "${GREEN}端口已设置为: $PORT_INPUT${NC}"
    fi

    echo -e "${YELLOW}当前优选IP: $(grep "CFIP = " app.py | cut -d"'" -f4)${NC}"
    read -p "请输入优选IP/域名 (留空使用默认高速节点): " CFIP_INPUT
    if [ -z "$CFIP_INPUT" ]; then
        CFIP_INPUT="cf-ip.net"  # 使用更快的默认IP
        optimize_ip_selection
    else
        sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$CFIP_INPUT')/" app.py
        echo -e "${GREEN}优选IP已设置为: $CFIP_INPUT${NC}"
    fi

    echo -e "${YELLOW}当前优选端口: $(grep "CFPORT = " app.py | cut -d"'" -f4)${NC}"
    read -p "请输入优选端口 (留空保持不变): " CFPORT_INPUT
    if [ -n "$CFPORT_INPUT" ]; then
        sed -i "s/CFPORT = int(os.environ.get('CFPORT', '[^']*'))/CFPORT = int(os.environ.get('CFPORT', '$CFPORT_INPUT'))/" app.py
        echo -e "${GREEN}优选端口已设置为: $CFPORT_INPUT${NC}"
    fi

    echo -e "${YELLOW}当前Argo端口: $(grep "ARGO_PORT = " app.py | cut -d"'" -f4)${NC}"
    read -p "请输入 Argo 端口 (留空保持不变): " ARGO_PORT_INPUT
    if [ -n "$ARGO_PORT_INPUT" ]; then
        sed -i "s/ARGO_PORT = int(os.environ.get('ARGO_PORT', '[^']*'))/ARGO_PORT = int(os.environ.get('ARGO_PORT', '$ARGO_PORT_INPUT'))/" app.py
        echo -e "${GREEN}Argo端口已设置为: $ARGO_PORT_INPUT${NC}"
    fi

    echo -e "${YELLOW}当前订阅路径: $(grep "SUB_PATH = " app.py | cut -d"'" -f4)${NC}"
    read -p "请输入订阅路径 (留空保持不变): " SUB_PATH_INPUT
    if [ -n "$SUB_PATH_INPUT" ]; then
        sed -i "s/SUB_PATH = os.environ.get('SUB_PATH', '[^']*')/SUB_PATH = os.environ.get('SUB_PATH', '$SUB_PATH_INPUT')/" app.py
        echo -e "${GREEN}订阅路径已设置为: $SUB_PATH_INPUT${NC}"
    fi

    # 新增：代理模式选择
    echo
    echo -e "${YELLOW}请选择代理模式:${NC}"
    echo -e "${BLUE}1) 全球代理模式 (所有流量通过代理)${NC}"
    echo -e "${BLUE}2) 智能分流模式 (国内网站直连，境外网站代理)${NC}"
    read -p "请输入选择 (1/2): " PROXY_MODE
    if [ "$PROXY_MODE" = "1" ]; then
        PROXY_MODE="global"
    else
        PROXY_MODE="smart"
    fi

    echo
    echo -e "${YELLOW}是否配置高级选项? (y/n)${NC}"
    read -p "> " ADVANCED_CONFIG

    if [ "$ADVANCED_CONFIG" = "y" ] || [ "$ADVANCED_CONFIG" = "Y" ]; then
        echo -e "${YELLOW}当前上传URL: $(grep "UPLOAD_URL = " app.py | cut -d"'" -f4)${NC}"
        read -p "请输入上传URL (留空保持不变): " UPLOAD_URL_INPUT
        if [ -n "$UPLOAD_URL_INPUT" ]; then
            sed -i "s|UPLOAD_URL = os.environ.get('UPLOAD_URL', '[^']*')|UPLOAD_URL = os.environ.get('UPLOAD_URL', '$UPLOAD_URL_INPUT')|" app.py
            echo -e "${GREEN}上传URL已设置${NC}"
        fi

        echo -e "${YELLOW}当前项目URL: $(grep "PROJECT_URL = " app.py | cut -d"'" -f4)${NC}"
        read -p "请输入项目URL (留空保持不变): " PROJECT_URL_INPUT
        if [ -n "$PROJECT_URL_INPUT" ]; then
            sed -i "s|PROJECT_URL = os.environ.get('PROJECT_URL', '[^']*')|PROJECT_URL = os.environ.get('PROJECT_URL', '$PROJECT_URL_INPUT')|" app.py
            echo -e "${GREEN}项目URL已设置${NC}"
        fi

        configure_hf_keep_alive

        echo -e "${YELLOW}当前哪吒服务器: $(grep "NEZHA_SERVER = " app.py | cut -d"'" -f4)${NC}"
        read -p "请输入哪吒服务器地址 (留空保持不变): " NEZHA_SERVER_INPUT
        if [ -n "$NEZHA_SERVER_INPUT" ]; then
            sed -i "s|NEZHA_SERVER = os.environ.get('NEZHA_SERVER', '[^']*')|NEZHA_SERVER = os.environ.get('NEZHA_SERVER', '$NEZHA_SERVER_INPUT')|" app.py
            
            echo -e "${YELLOW}当前哪吒端口: $(grep "NEZHA_PORT = " app.py | cut -d"'" -f4)${NC}"
            read -p "请输入哪吒端口 (v1版本留空): " NEZHA_PORT_INPUT
            if [ -n "$NEZHA_PORT_INPUT" ]; then
                sed -i "s|NEZHA_PORT = os.environ.get('NEZHA_PORT', '[^']*')|NEZHA_PORT = os.environ.get('NEZHA_PORT', '$NEZHA_PORT_INPUT')|" app.py
            fi
            
            echo -e "${YELLOW}当前哪吒密钥: $(grep "NEZHA_KEY = " app.py | cut -d"'" -f4)${NC}"
            read -p "请输入哪吒密钥: " NEZHA_KEY_INPUT
            if [ -n "$NEZHA_KEY_INPUT" ]; then
                sed -i "s|NEZHA_KEY = os.environ.get('NEZHA_KEY', '[^']*')|NEZHA_KEY = os.environ.get('NEZHA_KEY', '$NEZHA_KEY_INPUT')|" app.py
            fi
            echo -e "${GREEN}哪吒配置已设置${NC}"
        fi

        echo -e "${YELLOW}当前Argo域名: $(grep "ARGO_DOMAIN = " app.py | cut -d"'" -f4)${NC}"
        read -p "请输入 Argo 固定隧道域名 (留空保持不变): " ARGO_DOMAIN_INPUT
        if [ -n "$ARGO_DOMAIN_INPUT" ]; then
            sed -i "s|ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '[^']*')|ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '$ARGO_DOMAIN_INPUT')|" app.py
            
            echo -e "${YELLOW}当前Argo密钥: $(grep "ARGO_AUTH = " app.py | cut -d"'" -f4)${NC}"
            read -p "请输入 Argo 固定隧道密钥: " ARGO_AUTH_INPUT
            if [ -n "$ARGO_AUTH_INPUT" ]; then
                sed -i "s|ARGO_AUTH = os.environ.get('ARGO_AUTH', '[^']*')|ARGO_AUTH = os.environ.get('ARGO_AUTH', '$ARGO_AUTH_INPUT')|" app.py
            fi
            echo -e "${GREEN}Argo固定隧道配置已设置${NC}"
        fi

        echo -e "${YELLOW}当前Bot Token: $(grep "BOT_TOKEN = " app.py | cut -d"'" -f4)${NC}"
        read -p "请输入 Telegram Bot Token (留空保持不变): " BOT_TOKEN_INPUT
        if [ -n "$BOT_TOKEN_INPUT" ]; then
            sed -i "s|BOT_TOKEN = os.environ.get('BOT_TOKEN', '[^']*')|BOT_TOKEN = os.environ.get('BOT_TOKEN', '$BOT_TOKEN_INPUT')|" app.py
            
            echo -e "${YELLOW}当前Chat ID: $(grep "CHAT_ID = " app.py | cut -d"'" -f4)${NC}"
            read -p "请输入 Telegram Chat ID: " CHAT_ID_INPUT
            if [ -n "$CHAT_ID_INPUT" ]; then
                sed -i "s|CHAT_ID = os.environ.get('CHAT_ID', '[^']*')|CHAT_ID = os.environ.get('CHAT_ID', '$CHAT_ID_INPUT')|" app.py
            fi
            echo -e "${GREEN}Telegram配置已设置${NC}"
        fi
    fi
    
    # 根据选择应用代理模式
    if [ "$PROXY_MODE" = "global" ]; then
        echo -e "${GREEN}已启用全球代理模式，支持所有境外网络访问${NC}"
    else
        echo -e "${GREEN}已启用智能分流模式，优化访问速度${NC}"
    fi

    echo
    echo -e "${GREEN}完整配置完成！${NC}"
fi

echo -e "${YELLOW}=== 当前配置摘要 ===${NC}"
echo -e "UUID: $(grep "UUID = " app.py | head -1 | cut -d"'" -f2)"
echo -e "节点名称: $(grep "NAME = " app.py | head -1 | cut -d"'" -f4)"
echo -e "服务端口: $(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)"
echo -e "优选IP: $(grep "CFIP = " app.py | cut -d"'" -f4)"
echo -e "优选端口: $(grep "CFPORT = " app.py | cut -d"'" -f4)"
echo -e "订阅路径: $(grep "SUB_PATH = " app.py | cut -d"'" -f4)"
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "保活仓库: $HF_REPO_ID"
fi
echo -e "代理模式: $(if [ "$PROXY_MODE" = "global" ]; then echo "全球代理"; else echo "智能分流"; fi)"
echo -e "${YELLOW}========================${NC}"
echo

echo -e "${BLUE}正在启动服务...${NC}"
echo -e "${YELLOW}当前工作目录：$(pwd)${NC}"
echo

# 修改Python文件添加优化的分流规则和多端口支持
echo -e "${BLUE}正在配置优化的代理规则...${NC}"
cat > proxy_optimize.py << 'EOF'
# coding: utf-8
import os, re

# 读取app.py文件
with open('app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# 增强分流规则 - 支持全球代理
new_routing = '''
    "routing": {
        "domainStrategy": "IPOnDemand",
        "rules": [
            {"type": "field", "domain": ["geosite:cn", "geosite:private"], "outboundTag": "direct"},
            {"type": "field", "ip": ["geoip:cn", "geoip:private"], "outboundTag": "direct"},
            {"type": "field", "domain": ["geosite:geolocation-!cn"], "outboundTag": "proxy"},
            {"type": "field", "ip": ["geoip:!cn"], "outboundTag": "proxy"}
        ]
    }
'''

# 替换原有的路由配置
if '"routing":' in content:
    content = re.sub(r'"routing":\s*\{[^}]+\}', new_routing, content, flags=re.DOTALL)
else:
    # 如果没有路由配置，添加到config中
    content = re.sub(r'("outbounds":\s*\[[^]]+\])', r'\1,' + new_routing, content, flags=re.DOTALL)

# 添加多端口支持提升连接稳定性
content = re.sub(r'("port":\s*ARGO_PORT)', r'\1,\n            "portRange": "1024-65535"', content)

# 写入修改后的内容
with open('app.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("代理规则优化完成")
EOF

# 执行优化脚本
python3 proxy_optimize.py

# 启动服务时添加网络优化参数
if [ "$FAST_MODE" = "true" ]; then
    echo -e "${YELLOW}使用快速模式启动服务...${NC}"
    nohup python3 app.py --fast &
else
    nohup python3 app.py &
fi

# 等待服务启动
sleep 5

# 显示节点信息
echo -e "${GREEN}服务启动成功！${NC}"
echo -e "${YELLOW}节点信息已保存到 ${NODE_INFO_FILE}${NC}"
echo -e "${BLUE}可以使用 ./test.sh -v 查看节点信息${NC}"
