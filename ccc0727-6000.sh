#!/bin/sh

# 交互式批量创建WiFi脚本 - 带起始序号和补零功能
echo "======================================"
echo " OpenWrt 批量WiFi创建向导"
echo "======================================"

# 设置默认值
DEFAULT_WIFI_PREFIX="tk"
DEFAULT_WIFI_START="1"
DEFAULT_IP_START="21"
DEFAULT_WIFI_PASS="password"
DEFAULT_JOIN_LAN="y"
DEFAULT_BAND="1"
DEFAULT_CREATE_PASSWALL="y"
DEFAULT_SHUNT_REMARK="tk"

# 检测可用无线设备
# 直接设置设备名称
RADIO_2G="MT7986_1_1"
RADIO_5G="MT7986_1_2"

# 询问基本信息
read -p "请输入要创建的WiFi数量 [1]: " wifi_count
wifi_count=${wifi_count:-1}

read -p "请输入起始WiFi序号 [$DEFAULT_WIFI_START]: " wifi_start
wifi_start=${wifi_start:-$DEFAULT_WIFI_START}

read -p "请输入WiFi名称前缀 [$DEFAULT_WIFI_PREFIX]: " wifi_prefix
wifi_prefix=${wifi_prefix:-$DEFAULT_WIFI_PREFIX}

read -p "请输入统一的WiFi密码 [$DEFAULT_WIFI_PASS]: " wifi_pass
wifi_pass=${wifi_pass:-$DEFAULT_WIFI_PASS}

read -p "请输入起始IP的第三段 [$DEFAULT_IP_START]: " ip_start
ip_start=${ip_start:-$DEFAULT_IP_START}

read -p "是否加入LAN防火墙区域? [$DEFAULT_JOIN_LAN]: " join_lan
join_lan=${join_lan:-$DEFAULT_JOIN_LAN}

# 频段选择
echo -e "\n请选择频段："
echo "1) 5GHz (更快速度，覆盖范围小)"
echo "2) 2.4GHz (更远覆盖，速度较慢)"
echo "3) 混合模式 (对半分)"
read -p "请选择 [1]: " band_selection
band_selection=${band_selection:-$DEFAULT_BAND}

# PassWall分流规则创建
read -p "是否创建PassWall分流规则? [y/N]: " create_passwall
create_passwall=${create_passwall:-$DEFAULT_CREATE_PASSWALL}

# 如果创建分流规则，询问规则备注前缀
if [ "$create_passwall" = "y" ] || [ "$create_passwall" = "Y" ]; then
    read -p "请输入分流规则备注前缀 [$DEFAULT_SHUNT_REMARK]: " shunt_remark
    shunt_remark=${shunt_remark:-$DEFAULT_SHUNT_REMARK}
fi

# 验证输入
if ! [ "$wifi_count" -eq "$wifi_count" ] 2>/dev/null || [ "$wifi_count" -lt 1 ]; then
    echo "错误：WiFi数量必须是大于0的整数"
    exit 1
fi

if ! [ "$wifi_start" -eq "$wifi_start" ] 2>/dev/null || [ "$wifi_start" -lt 1 ]; then
    echo "错误：起始WiFi序号必须是大于0的整数"
    exit 1
fi

if [ $ip_start -lt 1 ] || [ $ip_start -gt 254 ]; then
    echo "错误：IP第三段必须在1-254之间"
    exit 1
fi

# 计算混合模式的分界点
if [ "$band_selection" = "3" ]; then
    half_point=$(( (wifi_count + 1) / 2 ))  # 向上取整
fi

# 计算结束序号
wifi_end=$((wifi_start + wifi_count - 1))

# 显示配置摘要
echo -e "\n配置摘要："
echo "--------------------------------------"
echo "将创建 $wifi_count 个WiFi网络 (序号 $wifi_start 到 $wifi_end)"

# 格式化显示WiFi名称示例
first_index_formatted=$(printf "%02d" $wifi_start)
last_index_formatted=$(printf "%02d" $wifi_end)
echo "WiFi名称格式: ${wifi_prefix}${first_index_formatted}, ${wifi_prefix}$(printf "%02d" $((wifi_start+1)))..."

echo "统一密码: $wifi_pass"
echo "IP地址: 192.168.x.1 (x从$ip_start开始)"
echo "加入LAN防火墙: $( [ "$join_lan" = "y" ] && echo "是" || echo "否" )"
echo -n "频段选择: "
case $band_selection in
    "1") echo "全部 5GHz" ;;
    "2") echo "全部 2.4GHz" ;;
    "3") echo "混合模式 (前$half_point个在5GHz，后$((wifi_count - half_point))个在2.4GHz)" ;;
    *) echo "未知选择，使用默认(5GHz)" && band_selection="1" ;;
esac
echo "创建PassWall分流规则: $( [ "$create_passwall" = "y" ] && echo "是" || echo "否" )"
if [ "$create_passwall" = "y" ]; then
    echo "分流规则备注: ${shunt_remark}${first_index_formatted}, ${shunt_remark}$(printf "%02d" $((wifi_start+1)))..."
fi
echo "--------------------------------------"

read -p "确认创建? [Y/n]: " confirm
confirm=${confirm:-y}
[ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && echo "操作已取消" && exit 0

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
for i in $(seq 0 $((wifi_count - 1))); do
    current_index=$((wifi_start + i))
    
    # 格式化序号为两位数 (01, 02...)
    num_formatted=$(printf "%02d" $current_index)
    
    # 确定频段
    case $band_selection in
        "1") radio_device=$RADIO_5G ; band="5GHz" ;;
        "2") radio_device=$RADIO_2G ; band="2.4GHz" ;;
        "3")
            if [ $i -lt $half_point ]; then
                radio_device=$RADIO_5G
                band="5GHz"
            else
                radio_device=$RADIO_2G
                band="2.4GHz"
            fi
            ;;
        *) radio_device=$RADIO_5G ; band="5GHz" ;;  # 默认
    esac
    
    wifi_name="${wifi_prefix}${num_formatted}"
    ip_third=$((ip_start + i))
    ip_addr="192.168.${ip_third}.1"
    subnet="192.168.${ip_third}.0/24"
    shunt_rule_name="${wifi_prefix}${num_formatted}"
    
    echo -e "\n正在创建 $wifi_name (IP: $ip_addr, 频段: $band, 序号: $num_formatted)"
    
    # 创建无线配置
    uci add wireless wifi-iface > /dev/null
    uci set wireless.@wifi-iface[-1].device="$radio_device"
    uci set wireless.@wifi-iface[-1].mode="ap"
    uci set wireless.@wifi-iface[-1].ssid="$wifi_name"
    uci set wireless.@wifi-iface[-1].encryption="psk2"
    uci set wireless.@wifi-iface[-1].key="$wifi_pass"
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
    if [ "$join_lan" = "y" ] || [ "$join_lan" = "Y" ]; then
        # 检查是否已在LAN区域中
        current_networks=$(uci -q get firewall.@zone[$LAN_ZONE_INDEX].network)
        if echo "$current_networks" | grep -q "\b$wifi_name\b"; then
            echo "$wifi_name 已在LAN防火墙区域中"
        else
            uci add_list firewall.@zone[$LAN_ZONE_INDEX].network="$wifi_name"
            echo "已将 $wifi_name 加入防火墙区域 $LAN_ZONE_NAME"
        fi
    fi
    
    # 创建PassWall分流规则 - 使用config shunt_rules
    if [ "$create_passwall" = "y" ] || [ "$create_passwall" = "Y" ]; then
        # 检查PassWall是否安装
        if [ -f "/etc/config/passwall" ]; then
            # 检查是否已存在同名shunt_rules
            rule_exists=false
            # 使用临时文件避免重定向问题
            tmpfile=$(mktemp)
            uci show passwall | grep -E 'passwall\.@shunt_rules\[[0-9]+\]\.name=' > "$tmpfile"
            while IFS= read -r rule_line; do
                rule_name=$(echo "$rule_line" | cut -d'=' -f2 | tr -d "'")
                if [ "$rule_name" = "$shunt_rule_name" ]; then
                    rule_exists=true
                    break
                fi
            done < "$tmpfile"
            rm -f "$tmpfile"
            
            if ! $rule_exists; then
                # 创建新的shunt_rules
                uci add passwall shunt_rules
                uci set passwall.@shunt_rules[-1].name="$shunt_rule_name"
                uci set passwall.@shunt_rules[-1].remarks="${shunt_remark}${num_formatted}"
                uci set passwall.@shunt_rules[-1].network="tcp,udp"
                uci set passwall.@shunt_rules[-1].source="$subnet"
                uci set passwall.@shunt_rules[-1].domain_list="regexp:.*"
                uci set passwall.@shunt_rules[-1].ip_list="0.0.0.0/0"
                
                echo "已创建PassWall分流规则: $shunt_rule_name (源: $subnet)"
            else
                echo "PassWall分流规则 $shunt_rule_name 已存在，跳过创建"
            fi
        else
            echo "警告: PassWall未安装，跳过规则创建"
            create_passwall="n" # 防止后续重复提示
        fi
    fi
done

# 提交所有更改
echo -e "\n正在提交配置更改..."
uci commit wireless
uci commit network
uci commit dhcp
uci commit firewall

if [ "$create_passwall" = "y" ]; then
    uci commit passwall
fi

# 重启服务
echo -e "\n正在应用配置..."
sleep 2
/etc/init.d/network reload
sleep 1
/etc/init.d/dnsmasq restart
sleep 1
/etc/init.d/firewall reload

# 重启PassWall服务（使用更安全的方式）
if [ "$create_passwall" = "y" ] && [ -f "/etc/init.d/passwall" ]; then
    echo "重启PassWall服务..."
    # 避免锁冲突
    sleep 5
    # 尝试更安全的重启方法
    if /etc/init.d/passwall enabled; then
        /etc/init.d/passwall restart >/dev/null 2>&1 || {
            echo "警告: PassWall重启失败，尝试手动重启"
            echo "请手动执行: /etc/init.d/passwall restart"
        }
    else
        echo "PassWall服务未启用，请手动启用并重启"
    fi
fi

echo -e "\n操作完成! 已成功创建 $wifi_count 个WiFi网络 (序号 $first_index_formatted 到 $last_index_formatted)"
echo "注意: 新网络可能需要1-2分钟生效"

# 显示PassWall规则提示
if [ "$create_passwall" = "y" ]; then
    echo -e "\nPassWall分流规则已创建:"
    for i in $(seq 0 $((wifi_count - 1))); do
        current_index=$((wifi_start + i))
        num_formatted=$(printf "%02d" $current_index)
        wifi_name="${wifi_prefix}${num_formatted}"
        ip_third=$((ip_start + i))
        subnet="192.168.${ip_third}.0/24"
        rule_name="${wifi_prefix}${num_formatted}"
        echo " - $rule_name: 源 $subnet (备注: ${shunt_remark}${num_formatted})"
    done
    echo "请登录PassWall界面配置代理节点"
    
    # 直接查看PassWall配置文件内容
    echo -e "\n验证PassWall分流规则配置:"
    if [ -f "/etc/config/passwall" ]; then
        grep -A 6 -E "config shunt_rules" /etc/config/passwall | grep -E "option name|option source|option remarks"
    else
        echo "PassWall配置文件不存在，规则创建失败"
    fi
fi

# 显示防火墙状态
echo -e "\n防火墙LAN区域($LAN_ZONE_NAME)包含的网络:"
uci get firewall.@zone[$LAN_ZONE_INDEX].network

# 验证网络接口
echo -e "\n已创建的网络接口:"
uci show network | grep -E "network\.${wifi_prefix}[0-9]{2}="
