#!/bin/sh

# 交互式批量创建WiFi脚本 - 带起始序号和补零功能
# 添加菜单选项和PassWall2支持

# 设置默认值
DEFAULT_WIFI_PREFIX="tk"
DEFAULT_WIFI_START="1"
DEFAULT_IP_START="21"
DEFAULT_WIFI_PASS="password"
DEFAULT_JOIN_LAN="y"
DEFAULT_BAND="1"
DEFAULT_CREATE_PASSWALL="y"
DEFAULT_SHUNT_REMARK="tk"
DEFAULT_PASSWALL_VERSION="1"  # 1 for pw1, 2 for pw2
DEFAULT_USE_TK_PROXY="y"

# 检测可用无线设备
RADIO_2G=""
RADIO_5G=""

# 自动检测无线设备
for radio in $(uci show wireless | grep -E 'radio[0-9]+=wifi-device' | cut -d'=' -f1 | cut -d'.' -f2); do
    band=$(uci get wireless.$radio.band 2>/dev/null)
    case $band in
        "2g"|"11g"|"11g"|"11b"|"11bgn") RADIO_2G=$radio ;;
        "5g"|"11a"|"11ac"|"11ax") RADIO_5G=$radio ;;
    esac
done

# 如果自动检测失败，使用常见默认值
[ -z "$RADIO_2G" ] && RADIO_2G="radio0"
[ -z "$RADIO_5G" ] && RADIO_5G="radio1"

# 安装Xray函数
install_xray() {
    echo "开始安装 Xray..."
    echo "下载 Xray 安装包..."
    wget -O xray-core.ipk "https://ghfast.top/https://github.com/Crying-Center/uni-demo1/blob/master/xray-core_25.1.30-r1_mipsel_24kc.ipk"
    
    if [ $? -eq 0 ]; then
        echo "下载完成，开始安装..."
        opkg install xray-core.ipk
        if [ $? -eq 0 ]; then
            echo "Xray 安装成功！"
            rm -f xray-core.ipk
            return 0
        else
            echo "Xray 安装失败！"
            return 1
        fi
    else
        echo "下载失败，请检查网络连接！"
        return 1
    fi
}

# 安装Passwall2函数
install_pw2() {
    echo "开始安装 Passwall2..."
    echo "下载 Passwall2 安装包..."
    wget -O pw2-install.tar.gz "https://ghfast.top/https://github.com/Crying-Center/uni-demo1/raw/refs/heads/master/pw2-install-mipsel_24kc.tar.gz"
    
    if [ $? -eq 0 ]; then
        echo "下载完成，开始解压..."
        tar -xzf pw2-install.tar.gz
        if [ $? -eq 0 ]; then
            echo "解压完成，开始安装组件..."
            cd pw2-install-mipsel_24kc
            
            # 安装所有ipk文件
            for pkg in geoview_0.1.10-r1_mipsel_24kc.ipk v2ray-geoip_202506050146.1_all.ipk v2ray-geosite_20250608120644.1_all.ipk luci-24.10_luci-app-passwall2_25.6.21-r1_all.ipk luci-24.10_luci-i18n-passwall2-zh-cn_25.171.82706.aa5e94a_all.ipk; do
                echo "正在安装 ${pkg}..."
                opkg install $pkg
                if [ $? -ne 0 ]; then
                    echo "${pkg} 安装失败！"
                    cd ..
                    return 1
                fi
            done
            
            cd ..
            rm -rf pw2-install.tar.gz pw2-install-mipsel_24kc
            echo "Passwall2 安装成功！"
            return 0
        else
            echo "解压失败！"
            return 1
        fi
    else
        echo "下载失败，请检查网络连接！"
        return 1
    fi
}

# 检查Xray是否已安装
check_xray_installed() {
    if opkg list-installed | grep -E "xray-core|Xray" >/dev/null 2>&1; then
        return 0
    elif which xray >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查Passwall是否已安装
check_passwall_installed() {
    if [ -f "/etc/config/passwall" ]; then
        return 0
    else
        return 1
    fi
}

# 检查Passwall2是否已安装
check_passwall2_installed() {
    if [ -f "/etc/config/passwall2" ]; then
        return 0
    else
        return 1
    fi
}

# 创建WiFi和接口
create_wifi_interfaces() {
    # 查找LAN防火墙区域名称
    LAN_ZONE_NAME=""
    LAN_ZONE_INDEX=""
    for i in $(seq 0 10); do
        zone_name=$(uci -q get firewall.@zone[$i].name)
        [ -z "$zone_name" ] && break
        
        if [ "$zone_name" = "lan" ]; then
            LAN_ZONE_NAME="lan"
            LAN_ZONE_INDEX=$i
            break
        fi
    done

    if [ -z "$LAN_ZONE_INDEX" ]; then
        # 回退方法：查找包含LAN网络的第一个区域
        for i in $(seq 0 10); do
            networks=$(uci -q get firewall.@zone[$i].network)
            [ -z "$networks" ] && continue
            
            if echo "$networks" | grep -q "lan"; then
                LAN_ZONE_NAME=$(uci -q get firewall.@zone[$i].name)
                LAN_ZONE_INDEX=$i
                break
            fi
        done
    fi

    if [ -z "$LAN_ZONE_INDEX" ]; then
        echo "警告: 无法确定LAN防火墙区域，使用默认设置"
        LAN_ZONE_NAME="lan"
        LAN_ZONE_INDEX=0
    fi

    # 主配置循环
    for i in $(seq 0 $((WIFI_COUNT - 1))); do
        current_index=$((WIFI_START + i))
        
        # 格式化序号为两位数 (01, 02...)
        num_formatted=$(printf "%02d" $current_index)
        
        # 确定频段
        case $BAND_SELECTION in
            "1") radio_device=$RADIO_5G ; band="5GHz" ;;
            "2") radio_device=$RADIO_2G ; band="2.4GHz" ;;
            "3")
                if [ $i -lt $HALF_POINT ]; then
                    radio_device=$RADIO_5G
                    band="5GHz"
                else
                    radio_device=$RADIO_2G
                    band="2.4GHz"
                fi
                ;;
            *) radio_device=$RADIO_5G ; band="5GHz" ;;  # 默认
        esac
        
        wifi_name="${WIFI_PREFIX}${num_formatted}"
        ip_third=$((IP_START + i))
        ip_addr="192.168.${ip_third}.1"
        subnet="192.168.${ip_third}.0/24"
        
        echo -e "\n正在创建 $wifi_name (IP: $ip_addr, 频段: $band, 序号: $num_formatted)"
        
        # 创建无线配置
        uci add wireless wifi-iface > /dev/null
        uci set wireless.@wifi-iface[-1].device="$radio_device"
        uci set wireless.@wifi-iface[-1].mode="ap"
        uci set wireless.@wifi-iface[-1].ssid="$wifi_name"
        uci set wireless.@wifi-iface[-1].encryption="psk2"
        uci set wireless.@wifi-iface[-1].key="$WIFI_PASS"
        uci set wireless.@wifi-iface[-1].network="$wifi_name"
        
        # 创建网络接口
        uci set network.$wifi_name=interface
        uci set network.$wifi_name.proto="static"
        uci set network.$wifi_name.ipaddr="$ip_addr"
        uci set network.$wifi_name.netmask="255.255.255.0"
        
        # 配置DHCP
        uci set dhcp.$wifi_name=dhcp
        uci set dhcp.$wifi_name.interface="$wifi_name"
        uci set dhcp.$wifi_name.start="100"
        uci set dhcp.$wifi_name.limit="150"
        uci set dhcp.$wifi_name.leasetime="12h"
        
        # 将接口加入LAN防火墙区域
        if [ "$JOIN_LAN" = "y" ] || [ "$JOIN_LAN" = "Y" ]; then
            # 检查是否已在LAN区域中
            current_networks=$(uci -q get firewall.@zone[$LAN_ZONE_INDEX].network)
            if echo "$current_networks" | grep -q "\b$wifi_name\b"; then
                echo "$wifi_name 已在LAN防火墙区域中"
            else
                uci add_list firewall.@zone[$LAN_ZONE_INDEX].network="$wifi_name"
                echo "已将 $wifi_name 加入防火墙区域 $LAN_ZONE_NAME"
            fi
        fi
    done

    # 提交所有更改
    echo -e "\n正在提交配置更改..."
    uci commit wireless
    uci commit network
    uci commit dhcp
    uci commit firewall

    # 重启服务
    echo -e "\n正在应用配置..."
    sleep 2
    /etc/init.d/network reload
    sleep 1
    /etc/init.d/dnsmasq restart
    sleep 1
    /etc/init.d/firewall reload

    echo -e "\n操作完成! 已成功创建 $WIFI_COUNT 个WiFi网络 (序号 $FIRST_INDEX_FORMATTED 到 $LAST_INDEX_FORMATTED)"
    echo "注意: 新网络可能需要1-2分钟生效"
    
    return 0
}

# 创建分流规则
create_shunt_rules() {
    if [ "$PASSWALL_VERSION" = "2" ]; then
        # 检查PassWall2是否已安装
        if ! check_passwall2_installed; then
            echo "PassWall2未安装，正在自动安装..."
            if ! install_pw2; then
                echo "PassWall2安装失败，脚本退出"
                exit 1
            fi
        fi
        
        # 创建PassWall2分流规则
        echo "正在创建PassWall2分流规则..."
        for i in $(seq 0 $((WIFI_COUNT - 1))); do
            current_index=$((WIFI_START + i))
            num_formatted=$(printf "%02d" $current_index)
            wifi_name="${WIFI_PREFIX}${num_formatted}"
            ip_third=$((IP_START + i))
            subnet="192.168.${ip_third}.0/24"
            rule_name="${WIFI_PREFIX}${num_formatted}"
            
            # 检查是否已存在同名shunt_rules
            rule_exists=false
            tmpfile=$(mktemp)
            uci show passwall2 | grep -E 'passwall2\.@shunt_rules\[[0-9]+\]\.name=' > "$tmpfile"
            while IFS= read -r rule_line; do
                rule_name_check=$(echo "$rule_line" | cut -d'=' -f2 | tr -d "'")
                if [ "$rule_name_check" = "$rule_name" ]; then
                    rule_exists=true
                    break
                fi
            done < "$tmpfile"
            rm -f "$tmpfile"
            
            if ! $rule_exists; then
                # 创建新的shunt_rules
                uci add passwall2 shunt_rules
                uci set passwall2.@shunt_rules[-1].name="$rule_name"
                uci set passwall2.@shunt_rules[-1].remarks="${SHUNT_REMARK}${num_formatted}"
                uci set passwall2.@shunt_rules[-1].network="tcp,udp"
                uci set passwall2.@shunt_rules[-1].source="$subnet"
                uci set passwall2.@shunt_rules[-1].domain_list="regexp:.*"
                uci set passwall2.@shunt_rules[-1].ip_list="0.0.0.0/0"
                
                echo "已创建PassWall2分流规则: $rule_name (源: $subnet)"
            else
                echo "PassWall2分流规则 $rule_name 已存在，跳过创建"
            fi
        done
        
        # 提交PassWall2配置
        uci commit passwall2
        
        # 重启PassWall2服务
        if [ -f "/etc/init.d/passwall2" ]; then
            echo "重启PassWall2服务..."
            sleep 5
            if /etc/init.d/passwall2 enabled; then
                /etc/init.d/passwall2 restart >/dev/null 2>&1 || {
                    echo "警告: PassWall2重启失败，尝试手动重启"
                    echo "请手动执行: /etc/init.d/passwall2 restart"
                }
            else
                echo "PassWall2服务未启用，请手动启用并重启"
            fi
        fi
        
    else
        # 创建PassWall分流规则
        echo "正在创建PassWall分流规则..."
        for i in $(seq 0 $((WIFI_COUNT - 1))); do
            current_index=$((WIFI_START + i))
            num_formatted=$(printf "%02d" $current_index)
            wifi_name="${WIFI_PREFIX}${num_formatted}"
            ip_third=$((IP_START + i))
            subnet="192.168.${ip_third}.0/24"
            rule_name="${WIFI_PREFIX}${num_formatted}"
            
            # 检查是否已存在同名shunt_rules
            rule_exists=false
            tmpfile=$(mktemp)
            uci show passwall | grep -E 'passwall\.@shunt_rules\[[0-9]+\]\.name=' > "$tmpfile"
            while IFS= read -r rule_line; do
                rule_name_check=$(echo "$rule_line" | cut -d'=' -f2 | tr -d "'")
                if [ "$rule_name_check" = "$rule_name" ]; then
                    rule_exists=true
                    break
                fi
            done < "$tmpfile"
            rm -f "$tmpfile"
            
            if ! $rule_exists; then
                # 创建新的shunt_rules
                uci add passwall shunt_rules
                uci set passwall.@shunt_rules[-1].name="$rule_name"
                uci set passwall.@shunt_rules[-1].remarks="${SHUNT_REMARK}${num_formatted}"
                uci set passwall.@shunt_rules[-1].network="tcp,udp"
                uci set passwall.@shunt_rules[-1].source="$subnet"
                uci set passwall.@shunt_rules[-1].domain_list="regexp:.*"
                uci set passwall.@shunt_rules[-1].ip_list="0.0.0.0/0"
                
                echo "已创建PassWall分流规则: $rule_name (源: $subnet)"
            else
                echo "PassWall分流规则 $rule_name 已存在，跳过创建"
            fi
        done
        
        # 提交PassWall配置
        uci commit passwall
        
        # 使用tk代理默认设置
        if [ "$USE_TK_PROXY" = "y" ] || [ "$USE_TK_PROXY" = "Y" ]; then
            echo "设置PassWall全局配置..."
            uci set passwall.@global[0].socks_enabled='0'
            uci set passwall.@global[0].udp_node='myshunt'
            uci set passwall.@global[0].tcp_node_socks_port='1070'
            uci set passwall.@global[0].filter_proxy_ipv6='1'
            uci set passwall.@global[0].dns_shunt='chinadns-ng'
            uci set passwall.@global[0].dns_mode='tcp'
            uci set passwall.@global[0].remote_dns='8.8.4.4'
            uci delete passwall.@global[0].smartdns_remote_dns
            uci add_list passwall.@global[0].smartdns_remote_dns='https://1.1.1.1/dns-query'
            uci set passwall.@global[0].tcp_proxy_mode='proxy'
            uci set passwall.@global[0].udp_proxy_mode='proxy'
            uci set passwall.@global[0].localhost_proxy='1'
            uci set passwall.@global[0].client_proxy='1'
            uci set passwall.@global[0].acl_enable='0'
            uci set passwall.@global[0].log_tcp='1'
            uci set passwall.@global[0].log_udp='1'
            uci set passwall.@global[0].loglevel='error'
            uci set passwall.@global[0].trojan_loglevel='4'
            uci set passwall.@global[0].enabled='1'
            uci set passwall.@global[0].tcp_node='myshunt'
            uci set passwall.@global[0].use_direct_list='0'
            uci set passwall.@global[0].use_proxy_list='0'
            uci set passwall.@global[0].use_block_list='0'
            uci set passwall.@global[0].use_gfw_list='0'
            uci set passwall.@global[0].chn_list='0'
            
            uci commit passwall
            echo "已设置PassWall全局配置"
        fi
        
        # 重启PassWall服务
        if [ -f "/etc/init.d/passwall" ]; then
            echo "重启PassWall服务..."
            sleep 5
            if /etc/init.d/passwall enabled; then
                /etc/init.d/passwall restart >/dev/null 2>&1 || {
                    echo "警告: PassWall重启失败，尝试手动重启"
                    echo "请手动执行: /etc/init.d/passwall restart"
                }
            else
                echo "PassWall服务未启用，请手动启用并重启"
            fi
        fi
    fi
    
    echo -e "\n分流规则创建完成!"
    return 0
}

# 收集WiFi和接口信息
collect_wifi_info() {
    # 询问基本信息
    read -p "请输入要创建的WiFi数量 [1]: " WIFI_COUNT
    WIFI_COUNT=${WIFI_COUNT:-1}

    read -p "请输入起始WiFi序号 [$DEFAULT_WIFI_START]: " WIFI_START
    WIFI_START=${WIFI_START:-$DEFAULT_WIFI_START}

    read -p "请输入WiFi名称前缀 [$DEFAULT_WIFI_PREFIX]: " WIFI_PREFIX
    WIFI_PREFIX=${WIFI_PREFIX:-$DEFAULT_WIFI_PREFIX}

    read -p "请输入统一的WiFi密码 [$DEFAULT_WIFI_PASS]: " WIFI_PASS
    WIFI_PASS=${WIFI_PASS:-$DEFAULT_WIFI_PASS}

    read -p "请输入起始IP的第三段 [$DEFAULT_IP_START]: " IP_START
    IP_START=${IP_START:-$DEFAULT_IP_START}

    read -p "是否加入LAN防火墙区域? [$DEFAULT_JOIN_LAN]: " JOIN_LAN
    JOIN_LAN=${JOIN_LAN:-$DEFAULT_JOIN_LAN}

    # 频段选择
    echo -e "\n请选择频段："
    echo "1) 5GHz (更快速度，覆盖范围小)"
    echo "2) 2.4GHz (更远覆盖，速度较慢)"
    echo "3) 混合模式 (对半分)"
    read -p "请选择 [1]: " BAND_SELECTION
    BAND_SELECTION=${BAND_SELECTION:-$DEFAULT_BAND}

    # 验证输入
    if ! [ "$WIFI_COUNT" -eq "$WIFI_COUNT" ] 2>/dev/null || [ "$WIFI_COUNT" -lt 1 ]; then
        echo "错误：WiFi数量必须是大于0的整数"
        return 1
    fi

    if ! [ "$WIFI_START" -eq "$WIFI_START" ] 2>/dev/null || [ "$WIFI_START" -lt 1 ]; then
        echo "错误：起始WiFi序号必须是大于0的整数"
        return 1
    fi

    if [ $IP_START -lt 1 ] || [ $IP_START -gt 254 ]; then
        echo "错误：IP第三段必须在1-254之间"
        return 1
    fi

    # 计算混合模式的分界点
    if [ "$BAND_SELECTION" = "3" ]; then
        HALF_POINT=$(( (WIFI_COUNT + 1) / 2 ))  # 向上取整
    fi

    # 计算结束序号
    WIFI_END=$((WIFI_START + WIFI_COUNT - 1))

    # 格式化显示WiFi名称示例
    FIRST_INDEX_FORMATTED=$(printf "%02d" $WIFI_START)
    LAST_INDEX_FORMATTED=$(printf "%02d" $WIFI_END)
    
    return 0
}

# 收集分流规则信息
collect_shunt_info() {
    read -p "请输入分流规则备注前缀 [$WIFI_PREFIX]: " SHUNT_REMARK
    SHUNT_REMARK=${SHUNT_REMARK:-$WIFI_PREFIX}
    
    read -p "创建在PassWall(1)还是PassWall2(2)上? [$DEFAULT_PASSWALL_VERSION]: " PASSWALL_VERSION
    PASSWALL_VERSION=${PASSWALL_VERSION:-$DEFAULT_PASSWALL_VERSION}
    
    if [ "$PASSWALL_VERSION" = "1" ]; then
        read -p "是否使用tk代理默认设置? [$DEFAULT_USE_TK_PROXY]: " USE_TK_PROXY
        USE_TK_PROXY=${USE_TK_PROXY:-$DEFAULT_USE_TK_PROXY}
    fi
    
    return 0
}

# 显示配置摘要
show_config_summary() {
    echo -e "\n配置摘要："
    echo "======================================"
    echo "将创建 $WIFI_COUNT 个WiFi网络 (序号 $WIFI_START 到 $WIFI_END)"
    echo "WiFi名称格式: ${WIFI_PREFIX}${FIRST_INDEX_FORMATTED}, ${WIFI_PREFIX}$(printf "%02d" $((WIFI_START+1)))..."
    echo "统一密码: $WIFI_PASS"
    echo "IP地址: 192.168.x.1 (x从$IP_START开始)"
    echo "加入LAN防火墙: $( [ "$JOIN_LAN" = "y" ] && echo "是" || echo "否" )"
    echo -n "频段选择: "
    case $BAND_SELECTION in
        "1") echo "全部 5GHz" ;;
        "2") echo "全部 2.4GHz" ;;
        "3") echo "混合模式 (前$HALF_POINT个在5GHz，后$((WIFI_COUNT - HALF_POINT))个在2.4GHz)" ;;
        *) echo "未知选择，使用默认(5GHz)" && BAND_SELECTION="1" ;;
    esac
    
    if [ "$CREATE_SHUNT" = "y" ]; then
        echo "创建分流规则: 是"
        echo "分流规则备注: ${SHUNT_REMARK}${FIRST_INDEX_FORMATTED}, ${SHUNT_REMARK}$(printf "%02d" $((WIFI_START+1)))..."
        echo "分流平台: PassWall$PASSWALL_VERSION"
        if [ "$PASSWALL_VERSION" = "1" ]; then
            echo "使用tk代理默认设置: $( [ "$USE_TK_PROXY" = "y" ] && echo "是" || echo "否" )"
        fi
    else
        echo "创建分流规则: 否"
    fi
    echo "======================================"
}

# 显示主菜单
show_menu() {
    clear
    echo "======================================"
    echo " OpenWrt 批量WiFi创建与管理向导"
    echo "======================================"
    echo "1. 创建WiFi、接口以及分流"
    echo "2. 只创建WiFi、接口"
    echo "3. 只创建分流规则"
    echo "4. 安装Xray"
    echo "5. 安装PassWall2"
    echo "6. 安装Xray和PassWall2"
    echo "7. 退出"
    echo "======================================"
    printf "请输入选择 [1-7]: "
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1)
            echo "创建WiFi、接口以及分流..."
            CREATE_SHUNT="y"
            
            # 收集WiFi信息
            if ! collect_wifi_info; then
                echo "输入验证失败，请重新输入"
                sleep 2
                continue
            fi
            
            # 收集分流信息
            if ! collect_shunt_info; then
                echo "输入验证失败，请重新输入"
                sleep 2
                continue
            fi
            
            # 显示配置摘要
            show_config_summary
            
            # 确认执行
            read -p "确认创建? [Y/n]: " confirm
            confirm=${confirm:-y}
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "操作已取消"
                sleep 2
                continue
            fi
            
            # 执行创建
            create_wifi_interfaces
            create_shunt_rules
            ;;
        2)
            echo "只创建WiFi、接口..."
            CREATE_SHUNT="n"
            
            # 收集WiFi信息
            if ! collect_wifi_info; then
                echo "输入验证失败，请重新输入"
                sleep 2
                continue
            fi
            
            # 显示配置摘要
            show_config_summary
            
            # 确认执行
            read -p "确认创建? [Y/n]: " confirm
            confirm=${confirm:-y}
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "操作已取消"
                sleep 2
                continue
            fi
            
            # 执行创建
            create_wifi_interfaces
            ;;
        3)
            echo "只创建分流规则..."
            CREATE_SHUNT="y"
            
            # 如果没有WiFi信息，需要收集
            if [ -z "$WIFI_PREFIX" ] || [ -z "$WIFI_START" ] || [ -z "$WIFI_COUNT" ] || [ -z "$IP_START" ]; then
                read -p "请输入WiFi名称前缀 [$DEFAULT_WIFI_PREFIX]: " WIFI_PREFIX
                WIFI_PREFIX=${WIFI_PREFIX:-$DEFAULT_WIFI_PREFIX}
                
                read -p "请输入起始WiFi序号 [$DEFAULT_WIFI_START]: " WIFI_START
                WIFI_START=${WIFI_START:-$DEFAULT_WIFI_START}
                
                read -p "请输入WiFi数量 [1]: " WIFI_COUNT
                WIFI_COUNT=${WIFI_COUNT:-1}
                
                read -p "请输入起始IP的第三段 [$DEFAULT_IP_START]: " IP_START
                IP_START=${IP_START:-$DEFAULT_IP_START}
                
                # 计算结束序号
                WIFI_END=$((WIFI_START + WIFI_COUNT - 1))
                
                # 格式化显示WiFi名称示例
                FIRST_INDEX_FORMATTED=$(printf "%02d" $WIFI_START)
                LAST_INDEX_FORMATTED=$(printf "%02d" $WIFI_END)
            fi
            
            # 收集分流信息
            if ! collect_shunt_info; then
                echo "输入验证失败，请重新输入"
                sleep 2
                continue
            fi
            
            # 显示配置摘要
            show_config_summary
            
            # 确认执行
            read -p "确认创建? [Y/n]: " confirm
            confirm=${confirm:-y}
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "操作已取消"
                sleep 2
                continue
            fi
            
            # 执行创建
            create_shunt_rules
            ;;
        4)
            echo "安装Xray..."
            install_xray
            ;;
        5)
            echo "安装PassWall2..."
            install_pw2
            ;;
        6)
            echo "安装Xray和PassWall2..."
            install_xray
            xray_success=$?
            install_pw2
            pw2_success=$?
            
            if [ $xray_success -eq 0 ] && [ $pw2_success -eq 0 ]; then
                echo "Xray和PassWall2安装成功!"
            else
                echo "部分安装失败，Xray: $([ $xray_success -eq 0 ] && echo "成功" || echo "失败")"
                echo "PassWall2: $([ $pw2_success -eq 0 ] && echo "成功" || echo "失败")"
            fi
            ;;
        7)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选择，请重新输入!"
            sleep 2
            ;;
    esac
    
    echo ""
    echo "按回车键返回主菜单..."
    read dummy
done
