#!/bin/sh
# 功能：设置OpenWrt主机名为Op-MAC地址全称，并安装指定的Tailscale IPK包

# ========== 第一部分：设置主机名 ==========
echo ">>> 开始设置主机名..."

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
        exit 1
    fi
fi

# 4. 移除MAC地址中的冒号
MAC_NO_COLON=$(echo "$LAN_MAC" | tr -d ':')

# 5. 设置主机名为Op-MAC地址全称
NEW_HOSTNAME="Op-${MAC_NO_COLON}"

echo "LAN MAC地址: $LAN_MAC"
echo "设置主机名为: $NEW_HOSTNAME"

# 6. 永久设置主机名
uci set system.@system[0].hostname="$NEW_HOSTNAME"
uci commit system

# 7. 立即生效（无需重启）
echo "$NEW_HOSTNAME" > /proc/sys/kernel/hostname

echo "主机名设置完成。"
echo "当前主机名: $(cat /proc/sys/kernel/hostname)"

# ========== 第二部分：下载并安装Tailscale IPK ==========
echo ""
echo ">>> 开始下载并安装Tailscale IPK包..."

# 1. 定义IPK包的下载地址和本地保存路径
IPK_URL="https://ghfast.top/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/tailscale_v1.92.3_mipsel_24kc.ipk"
IPK_FILE="/tmp/tailscale.ipk"

# 2. 下载IPK包 (如果curl不存在则使用wget)
echo "正在从以下地址下载IPK包:"
echo "$IPK_URL"
if command -v curl >/dev/null 2>&1; then
    echo "使用curl下载..."
    curl -fSL "$IPK_URL" -o "$IPK_FILE"
else
    echo "使用wget下载..."
    wget "$IPK_URL" -O "$IPK_FILE"
fi

# 3. 检查下载是否成功
if [ $? -ne 0 ] || [ ! -f "$IPK_FILE" ]; then
    echo "错误：IPK包下载失败！"
    echo "可能的原因："
    echo "  1. 网络连接问题"
    echo "  2. 下载链接失效"
    echo "  3. 域名解析失败"
    echo "请检查网络或下载链接，然后重试。"
    exit 1
fi

echo "下载成功。文件大小: $(du -h "$IPK_FILE" | cut -f1)"

# 4. 使用opkg安装IPK包
echo "正在使用opkg安装IPK包..."
opkg install "$IPK_FILE"

# 5. 检查安装是否成功
if [ $? -ne 0 ]; then
    echo "警告：opkg安装过程可能遇到问题。"
    echo "尝试强制安装..."
    opkg install --force-overwrite "$IPK_FILE"
fi

# 清理临时文件
rm -f "$IPK_FILE"
echo "临时文件已清理。"

# 6. 验证tailscale命令是否可用
if command -v tailscale >/dev/null 2>&1; then
    echo "✓ Tailscale 安装成功！"
else
    echo "错误：Tailscale 安装后命令仍不可用。"
    echo "请检查："
    echo "  1. IPK包是否适用于当前OpenWrt版本和架构"
    echo "  2. 系统日志：logread | tail -20"
    exit 1
fi

# ========== 第三部分：启动Tailscale ==========
echo ""
echo ">>> 启动Tailscale..."
echo "注意：此步骤将运行 'tailscale up'，可能会显示认证链接。"
echo "如果需特定参数（如路由通告），请修改脚本中的命令。"
echo "----------------------------------------"

# 运行tailscale up命令
tailscale up

# 提示用户
echo "----------------------------------------"
echo "脚本执行完毕！"
echo "如果上面显示了认证链接，请复制到浏览器中打开完成认证。"
echo "您可以使用 'tailscale status' 检查连接状态。"