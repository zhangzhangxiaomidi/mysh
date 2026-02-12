#!/bin/sh

# 融合脚本 - 提供多个配置选项
# 作者: Eugene
# 日期: 2024-09-04
# 修改1: 移除硬编码UUID，改为用户输入
# 修改2: Tailscale IPK下载失败自动重试，移除认证key，醒目提示命令

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_NODE_ID="fJeo25Md"
DEFAULT_NODE_REMARKS="Eugene-UK"
DEFAULT_2G_SSID="Eugene工作室"
DEFAULT_5G_SSID="Eugene工作室-5G"
DEFAULT_PASSWORD="666666666"
# TOKEN_1="936052b9-9b2e-4bbf-92da-cc360c8670e1"  # 陈
#OKEN_1="1c13a0bb-6d7f-454e-a6cb-1d8c40053359"   # 陈
TOKEN_1="22901bbc-d07c-49b2-acea-7c2272164dbf"    # 陈
TOKEN_2="6b22ced7-c723-4dc8-9852-322a707b6f2a"    # zjh
TOKEN_3="4c363078-d90f-43c7-86a8-38bde5221b98"    # 颜

# URL解码函数
url_decode() {
    echo "$1" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b"
}

# 安装Tailscale并设置主机名函数（带下载重试、移除auth-key）
install_tailscale_and_set_hostname() {
    local wifi_name="$1"
    
    echo -e "${BLUE}>>> 开始安装Tailscale...${NC}"
    
    # ========== 第一部分：构建Tailscale主机名 ==========
    echo ">>> 构建Tailscale主机名..."
    
    # 1. 获取LAN口MAC地址（兼容不同ifconfig输出格式）
    LAN_MAC=$(ifconfig br-lan 2>/dev/null | awk '/ether/{print $2; exit} /HWaddr/{print $5; exit}')
    
    # 2. 如果上面没获取到，尝试使用更通用的方法
    if [ -z "$LAN_MAC" ]; then
        LAN_MAC=$(ifconfig br-lan 2>/dev/null | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | head -n1)
    fi
    
    # 3. 检查是否成功获取MAC
    if [ -z "$LAN_MAC" ]; then
        echo "错误：无法获取br-lan接口的MAC地址"
        echo "尝试使用eth0接口..."
        LAN_MAC=$(ifconfig eth0 2>/dev/null | awk '/ether/{print $2; exit} /HWaddr/{print $5; exit}')
        
        if [ -z "$LAN_MAC" ]; then
            echo "错误：无法获取任何网络接口的MAC地址"
            return 1
        fi
    fi
    
    # 4. 移除MAC地址中的冒号
    MAC_NO_COLON=$(echo "$LAN_MAC" | tr -d ':')
    
    # 5. 构建Tailscale主机名
    TAILSCALE_HOSTNAME="Op-${MAC_NO_COLON}"
    
    # 6. 如果提供了WiFi名称且不是默认名称，则追加到主机名
    if [ -n "$wifi_name" ] && [ "$wifi_name" != "$DEFAULT_2G_SSID" ]; then
        # 移除WiFi名称中的空格
        wifi_name_no_spaces=$(echo "$wifi_name" | tr -d ' ')
        TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME}-${wifi_name_no_spaces}"
    fi
    
    echo "LAN MAC地址: $LAN_MAC"
    echo "Tailscale主机名: $TAILSCALE_HOSTNAME"
    
    # ========== 第二部分：下载并安装Tailscale IPK（带重试） ==========
    echo ""
    echo ">>> 开始下载并安装Tailscale IPK包..."
    
    IPK_URL="https://gh-proxy.com//https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/tailscale_v1.92.3_mipsel_24kc.ipk"
    IPK_FILE="/tmp/tailscale.ipk"
    
    # 重试参数
    MAX_RETRIES=3
    RETRY_COUNT=0
    DOWNLOAD_SUCCESS=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo -e "${YELLOW}第 $RETRY_COUNT 次重试下载...${NC}"
            sleep 3
        fi
        
        echo "正在从以下地址下载IPK包（尝试 $((RETRY_COUNT+1))/$MAX_RETRIES）:"
        echo "$IPK_URL"
        
        if command -v curl >/dev/null 2>&1; then
            echo "使用curl下载..."
            curl -fSL --connect-timeout 30 --retry 2 "$IPK_URL" -o "$IPK_FILE"
        else
            echo "使用wget下载..."
            wget --no-check-certificate --timeout=30 --tries=2 "$IPK_URL" -O "$IPK_FILE"
        fi
        
        if [ $? -eq 0 ] && [ -f "$IPK_FILE" ]; then
            DOWNLOAD_SUCCESS=1
            echo "下载成功。文件大小: $(du -h "$IPK_FILE" | cut -f1)"
            break
        else
            echo -e "${RED}下载失败，文件不存在或下载错误。${NC}"
            rm -f "$IPK_FILE"  # 清理可能的残留
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
    
    if [ $DOWNLOAD_SUCCESS -ne 1 ]; then
        echo -e "${RED}错误：IPK包在 $MAX_RETRIES 次尝试后仍然下载失败！${NC}"
        echo "请检查网络连接或手动安装Tailscale。"
        return 1
    fi
    
    # 使用opkg安装IPK包
    echo "正在使用opkg安装IPK包..."
    opkg install "$IPK_FILE"
    
    # 检查安装是否成功
    if [ $? -ne 0 ]; then
        echo "警告：opkg安装过程可能遇到问题。"
        echo "尝试强制安装..."
        opkg install --force-overwrite "$IPK_FILE"
    fi
    
    # 清理临时文件
    rm -f "$IPK_FILE"
    echo "临时文件已清理。"
    
    # 验证tailscale命令是否可用
    if command -v tailscale >/dev/null 2>&1; then
        echo "✓ Tailscale 安装成功！"
    else
        echo -e "${RED}错误：Tailscale 安装后命令仍不可用。${NC}"
        echo "请检查："
        echo "  1. IPK包是否适用于当前OpenWrt版本和架构"
        echo "  2. 系统日志：logread | tail -20"
        return 1
    fi
    
    # ========== 第三部分：启动Tailscale（仅hostname，无auth-key） ==========
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}         即将执行Tailscale启动命令（无预共享密钥）${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}>>> 命令: ${NC}tailscale up --hostname=\"$TAILSCALE_HOSTNAME\""
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}说明：此命令将启动Tailscale并自动生成认证链接。${NC}"
    echo -e "${BLUE}      请复制链接到浏览器中登录您的Tailscale账号。${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 运行tailscale up命令，只设置主机名
    tailscale up --hostname="$TAILSCALE_HOSTNAME"
    
    # 提示用户
    echo "----------------------------------------"
    echo -e "${GREEN}Tailscale设置完成！${NC}"
    echo "Tailscale主机名已设置为: $TAILSCALE_HOSTNAME"
    echo "如果上面显示了认证链接，请复制到浏览器中打开完成认证。"
    echo "您可以使用 'tailscale status' 检查连接状态。"
    
    echo -e "${GREEN}Tailscale安装和设置完成！${NC}"
}

# 修改root密码函数
change_root_password() {
    echo -e "${BLUE}>>> 修改root密码...${NC}"
    
    # 使用passwd命令修改root密码
    echo -e "chenchenyu32132\nchenchenyu32132" | passwd root 2>/dev/null
    
    # 检查密码是否修改成功
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ root密码已成功修改为: chenchenyu32132${NC}"
        echo "请使用新密码登录系统。"
    else
        echo -e "${RED}✗ root密码修改失败，请手动执行以下命令:${NC}"
        echo "echo -e 'chenchenyu32132\\nchenchenyu32132' | passwd root"
    fi
}

# 显示菜单
show_menu() {
    echo -e "${GREEN}=== 配置菜单 ===${NC}"
    echo "1. 陈--快捷设置（wifi+ddnsto+pw+tailscale）"
    echo "2. 修改wifi"
    echo "3. 设置ddnsto"
    echo "4. 新增节点并应用"
    echo "5. 只导入节点"
    echo -e "${YELLOW}直接回车将选择选项1${NC}"
}

# 配置WiFi函数
setup_wifi() {
    local quick_mode=$1
    local wifi_name=$2
    
    if [ "$quick_mode" = "true" ]; then
        # 快速模式，使用传入的wifi_name
        SSID_2G="${wifi_name:-$DEFAULT_2G_SSID}"
        SSID_5G="${wifi_name:-$DEFAULT_2G_SSID}"
        PASSWORD=$DEFAULT_PASSWORD
        echo -e "${BLUE}使用WiFi配置: 2.4G=$SSID_2G, 5G=$SSID_5G${NC}"
    else
        # 交互模式
        read -p "请输入2.4G WiFi名称（默认: $DEFAULT_2G_SSID）: " input_2g_ssid
        read -p "请输入5G WiFi名称（默认: $DEFAULT_5G_SSID）: " input_5g_ssid
        read -p "请输入WiFi密码（默认: $DEFAULT_PASSWORD）: " input_password

        # 使用用户输入或默认值
        SSID_2G=${input_2g_ssid:-$DEFAULT_2G_SSID}
        SSID_5G=${input_5g_ssid:-$DEFAULT_5G_SSID}
        PASSWORD=${input_password:-$DEFAULT_PASSWORD}
    fi

    # 更新WiFi配置
    uci set wireless.@wifi-iface[0].ssid="$SSID_2G"
    uci set wireless.@wifi-iface[0].key="$PASSWORD"
    uci set wireless.@wifi-iface[1].ssid="$SSID_5G"
    uci set wireless.@wifi-iface[1].key="$PASSWORD"

    # 提交更改并重启无线网络
    uci commit wireless
    wifi reload

    echo -e "${GREEN}WiFi配置已更新：${NC}"
    echo "2.4G: $SSID_2G"
    echo "5G: $SSID_5G"
    echo "密码: $PASSWORD"
}

# 配置DDNSTO函数
setup_ddnsto() {
    local quick_mode=$1
    
    if [ "$quick_mode" = "true" ]; then
        # 快速模式，使用默认token
        SELECTED_TOKEN=$TOKEN_1
        echo -e "${BLUE}使用默认token: 陈${NC}"
    else
        # 交互模式
        echo "请选择token选项："
        echo "1. 陈 (默认)"
        echo "2. zjh"
        echo "3. 颜"
        echo "4. 输入自定义token"
        read -p "请输入选项编号 (1-4) [默认1]: " choice

        # 处理用户选择
        case $choice in
            1|"")
                SELECTED_TOKEN=$TOKEN_1
                echo "已选择: 陈"
                ;;
            2)
                SELECTED_TOKEN=$TOKEN_2
                echo "已选择: zjh"
                ;;
            3)
                SELECTED_TOKEN=$TOKEN_3
                echo "已选择: 颜"
                ;;
            4)
                read -p "请输入自定义token: " custom_token
                SELECTED_TOKEN=$custom_token
                echo "已设置自定义token"
                ;;
            *)
                echo "无效选项，使用默认值(陈)"
                SELECTED_TOKEN=$TOKEN_1
                ;;
        esac
    fi

    # 检查ddnsto配置文件是否存在
    if [ ! -f /etc/config/ddnsto ]; then
        echo -e "${RED}错误: /etc/config/ddnsto 文件不存在!${NC}"
        return 1
    fi

    # 备份原配置文件
    cp /etc/config/ddnsto /etc/config/ddnsto.backup.$(date +%Y%m%d%H%M%S)

    # 更新ddnsto配置
    uci set ddnsto.@ddnsto[0].feat_port='3033'
    uci set ddnsto.@ddnsto[0].feat_enabled='0'
    uci set ddnsto.@ddnsto[0].index='0'
    uci set ddnsto.@ddnsto[0].enabled='1'
    uci set ddnsto.@ddnsto[0].token="$SELECTED_TOKEN"

    # 提交更改
    uci commit ddnsto

    echo -e "${GREEN}ddnsto配置已更新:${NC}"
    echo "token: $SELECTED_TOKEN"

    # 重启ddnsto服务（如果服务存在）
    if [ -f /etc/init.d/ddnsto ]; then
        /etc/init.d/ddnsto restart
        echo "ddnsto服务已重启"
    else
        echo "注意: 未找到ddnsto服务，配置已更新但未重启服务"
    fi
}

# 配置Passwall节点函数（已移除硬编码UUID，改为用户输入）
setup_passwall_node() {
    local apply_global=$1
    local quick_mode=$2
    
    if [ "$quick_mode" = "true" ]; then
        # 快速模式，使用默认节点但需要用户输入UUID
        echo -e "${BLUE}使用默认节点配置，请提供节点UUID...${NC}"
        
        # 提示用户输入UUID
        read -p "请输入VLESS节点的UUID（必填）: " user_uuid
        if [ -z "$user_uuid" ]; then
            echo -e "${RED}错误：UUID不能为空，节点添加失败！${NC}"
            return 1
        fi
        
        # 检查默认节点是否已存在，如果存在则删除
        if uci get passwall.$DEFAULT_NODE_ID >/dev/null 2>&1; then
            uci delete passwall.$DEFAULT_NODE_ID
        fi
        
        # 添加默认节点配置（仅替换UUID为用户输入）
        uci set passwall.$DEFAULT_NODE_ID=nodes
        uci set passwall.$DEFAULT_NODE_ID.remarks="$DEFAULT_NODE_REMARKS"
        uci set passwall.$DEFAULT_NODE_ID.type='sing-box'
        uci set passwall.$DEFAULT_NODE_ID.protocol='vless'
        uci set passwall.$DEFAULT_NODE_ID.address='uk.tiktokjiasu.top'
        uci set passwall.$DEFAULT_NODE_ID.port='45604'
        uci set passwall.$DEFAULT_NODE_ID.uuid="$user_uuid"          # 用户输入的UUID
        uci set passwall.$DEFAULT_NODE_ID.tls='1'
        uci set passwall.$DEFAULT_NODE_ID.alpn='default'
        uci set passwall.$DEFAULT_NODE_ID.tls_serverName='tesla.com'
        uci set passwall.$DEFAULT_NODE_ID.utls='1'
        uci set passwall.$DEFAULT_NODE_ID.fingerprint='chrome'
        uci set passwall.$DEFAULT_NODE_ID.reality='1'
        uci set passwall.$DEFAULT_NODE_ID.reality_publicKey='Ksvm7_unQR4nijHHOYBKlzzTRTUPPKFaUrMdm80NLBo'
        uci set passwall.$DEFAULT_NODE_ID.reality_shortId='ea44e653'
        uci set passwall.$DEFAULT_NODE_ID.transport='tcp'
        uci set passwall.$DEFAULT_NODE_ID.mux='0'
        
        echo -e "${GREEN}已添加默认节点: $DEFAULT_NODE_ID (备注: $DEFAULT_NODE_REMARKS)${NC}"
        NODE_ID="$DEFAULT_NODE_ID"
    else
        # 交互模式
        read -p "是否输入VLESS节点链接? (直接回车使用默认节点): " vless_link

        if [ -n "$vless_link" ]; then
            # 解析用户输入的VLESS链接
            echo "正在解析VLESS链接..."
            
            # 从链接中提取信息
            uuid=$(echo "$vless_link" | awk -F'@' '{print $1}' | sed 's/vless:\/\///')
            server_info=$(echo "$vless_link" | awk -F'@' '{print $2}' | awk -F'?' '{print $1}')
            address=$(echo "$server_info" | awk -F':' '{print $1}')
            # 提取端口号，移除可能存在的斜杠和路径
            port=$(echo "$server_info" | awk -F':' '{print $2}' | awk -F'/' '{print $1}')
            params=$(echo "$vless_link" | awk -F'?' '{print $2}' | awk -F'#' '{print $1}')
            remarks_encoded=$(echo "$vless_link" | awk -F'#' '{print $2}')
            
            # 解码URL编码的备注
            if [ -n "$remarks_encoded" ]; then
                remarks=$(url_decode "$remarks_encoded")
            else
                remarks=""
            fi
            
            # 如果备注为空，使用随机值
            if [ -z "$remarks" ]; then
                remarks="Node_$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)"
            fi
            
            # 解析参数
            type=$(echo "$params" | tr '&' '\n' | grep 'type=' | cut -d'=' -f2)
            security=$(echo "$params" | tr '&' '\n' | grep 'security=' | cut -d'=' -f2)
            pbk=$(echo "$params" | tr '&' '\n' | grep 'pbk=' | cut -d'=' -f2)
            fp=$(echo "$params" | tr '&' '\n' | grep 'fp=' | cut -d'=' -f2)
            sni=$(echo "$params" | tr '&' '\n' | grep 'sni=' | cut -d'=' -f2)
            sid=$(echo "$params" | tr '&' '\n' | grep 'sid=' | cut -d'=' -f2)
            
            # 生成随机节点ID
            node_id=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)
            
            # 设置节点配置
            uci set passwall.$node_id=nodes
            uci set passwall.$node_id.remarks="$remarks"
            uci set passwall.$node_id.type='sing-box'
            uci set passwall.$node_id.protocol='vless'
            uci set passwall.$node_id.address="$address"
            uci set passwall.$node_id.port="$port"
            uci set passwall.$node_id.uuid="$uuid"
            uci set passwall.$node_id.tls='1'
            uci set passwall.$node_id.alpn='default'
            uci set passwall.$node_id.tls_serverName="$sni"
            uci set passwall.$node_id.utls='1'
            uci set passwall.$node_id.fingerprint="$fp"
            uci set passwall.$node_id.reality='1'
            uci set passwall.$node_id.reality_publicKey="$pbk"
            uci set passwall.$node_id.reality_shortId="$sid"
            uci set passwall.$node_id.transport="$type"
            uci set passwall.$node_id.mux='0'
            
            echo -e "${GREEN}已添加自定义节点: $node_id (备注: $remarks)${NC}"
            NODE_ID="$node_id"
        else
            # 使用默认节点，但需要用户输入UUID
            echo "使用默认节点配置，请提供节点UUID..."
            read -p "请输入VLESS节点的UUID（必填）: " user_uuid
            if [ -z "$user_uuid" ]; then
                echo -e "${RED}错误：UUID不能为空，节点添加失败！${NC}"
                return 1
            fi
            
            # 生成随机节点ID
            node_id=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)
            
            # 添加节点配置（仅替换UUID为用户输入）
            uci set passwall.$node_id=nodes
            uci set passwall.$node_id.remarks="$DEFAULT_NODE_REMARKS"
            uci set passwall.$node_id.type='sing-box'
            uci set passwall.$node_id.protocol='vless'
            uci set passwall.$node_id.address='103.195.190.172'
            uci set passwall.$node_id.port='58841'
            uci set passwall.$node_id.uuid="$user_uuid"                # 用户输入的UUID
            uci set passwall.$node_id.tls='1'
            uci set passwall.$node_id.alpn='default'
            uci set passwall.$node_id.tls_serverName='tesla.com'
            uci set passwall.$node_id.utls='1'
            uci set passwall.$node_id.fingerprint='chrome'
            uci set passwall.$node_id.reality='1'
            uci set passwall.$node_id.reality_publicKey='zQ0aE1tVll0KIsoDUCbTE6kpqg4coqvp1blzYUlPbCQ'
            uci set passwall.$node_id.reality_shortId='606beee75848ef0a'
            uci set passwall.$node_id.transport='tcp'
            uci set passwall.$node_id.mux='0'
            
            echo -e "${GREEN}已添加自定义节点: $node_id (备注: $DEFAULT_NODE_REMARKS)${NC}"
            NODE_ID="$node_id"
        fi
    fi

    # 提交更改
    uci commit passwall
    
    # 如果要求应用到全局配置
    if [ "$apply_global" = "true" ]; then
        # 设置全局选项
        uci set passwall.@global[0].enabled='1'
        uci set passwall.@global[0].tcp_node="$NODE_ID"
        uci set passwall.@global[0].udp_node='tcp'
        
        # 提交更改
        uci commit passwall
        
        echo -e "${GREEN}passwall配置已更新:${NC}"
        echo "- 全局设置已启用，TCP节点设置为 $NODE_ID"
        echo "- 已添加节点配置"
        
        # 重启passwall服务（如果服务存在）
        if [ -f /etc/init.d/passwall ]; then
            /etc/init.d/passwall restart
            echo "passwall服务已重启"
        else
            echo "注意: 未找到passwall服务，配置已更新但未重启服务"
        fi
    else
        echo -e "${GREEN}节点已添加但未应用到全局配置${NC}"
    fi
}

# 主菜单处理
show_menu
read -p "请选择操作 [1-5] (默认1): " choice
choice=${choice:-1}

case $choice in
    1)
        echo -e "${BLUE}执行快捷设置（wifi+ddnsto+pw+tailscale）...${NC}"
        
        # 询问用户WiFi名称
        read -p "请输入WiFi名称（直接回车使用默认值: ${DEFAULT_2G_SSID}）: " user_wifi_name
        if [ -z "$user_wifi_name" ]; then
            user_wifi_name="$DEFAULT_2G_SSID"
            echo -e "${YELLOW}使用默认WiFi名称: $user_wifi_name${NC}"
        else
            echo -e "${YELLOW}使用用户指定的WiFi名称: $user_wifi_name${NC}"
        fi
        
        # 执行WiFi设置（快速模式，使用用户指定的WiFi名称）
        setup_wifi "true" "$user_wifi_name"
        
        # 执行DDNSTO设置（快速模式）
        setup_ddnsto "true"
        
        # 检查passwall配置文件是否存在
        if [ ! -f /etc/config/passwall ]; then
            echo -e "${RED}错误: /etc/config/passwall 文件不存在!${NC}"
            exit 1
        fi
        # 备份原配置文件
        cp /etc/config/passwall /etc/config/passwall.backup.$(date +%Y%m%d%H%M%S)
        
        # 执行Passwall节点设置（快速模式） - 此处会提示用户输入UUID
        if ! setup_passwall_node "true" "true"; then
            echo -e "${RED}Passwall节点配置失败，已跳过。${NC}"
            # 可根据需要决定是否退出，这里仅提示
        fi
        
        echo -e "${GREEN}WiFi、DDNSTO和Passwall配置已完成！${NC}"
        
        # 执行Tailscale安装和主机名设置
        install_tailscale_and_set_hostname "$user_wifi_name"
        
        # 修改root密码
        change_root_password
        
        echo -e "${GREEN}所有配置已完成！${NC}"
        ;;
    2)
        echo -e "${BLUE}修改WiFi设置...${NC}"
        setup_wifi "false"
        ;;
    3)
        echo -e "${BLUE}设置DDNSTO...${NC}"
        setup_ddnsto "false"
        ;;
    4)
        echo -e "${BLUE}新增节点并应用...${NC}"
        # 检查passwall配置文件是否存在
        if [ ! -f /etc/config/passwall ]; then
            echo -e "${RED}错误: /etc/config/passwall 文件不存在!${NC}"
            exit 1
        fi
        # 备份原配置文件
        cp /etc/config/passwall /etc/config/passwall.backup.$(date +%Y%m%d%H%M%S)
        if ! setup_passwall_node "true" "false"; then
            echo -e "${RED}Passwall节点配置失败，请重试。${NC}"
            exit 1
        fi
        ;;
    5)
        echo -e "${BLUE}只导入节点...${NC}"
        # 检查passwall配置文件是否存在
        if [ ! -f /etc/config/passwall ]; then
            echo -e "${RED}错误: /etc/config/passwall 文件不存在!${NC}"
            exit 1
        fi
        # 备份原配置文件
        cp /etc/config/passwall /etc/config/passwall.backup.$(date +%Y%m%d%H%M%S)
        if ! setup_passwall_node "false" "false"; then
            echo -e "${RED}Passwall节点配置失败，请重试。${NC}"
            exit 1
        fi
        ;;
    *)
        echo -e "${RED}无效选择，请重新运行脚本并选择1-5之间的选项${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}操作完成！${NC}"
