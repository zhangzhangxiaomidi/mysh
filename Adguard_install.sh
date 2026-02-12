#!/bin/sh

# AdGuardHome 快捷安装脚本（适用于 OpenWrt）
# 功能：下载三个必要文件 -> 安装 ipk 包 -> 解压并部署二进制 -> 清理

set -e

# 颜色提示（如果终端不支持，输出也会正常）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 文件与 URL 定义
URL1="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/adguardhome_1.1.1-r1_all.ipk"
URL2="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/adguardhome-zh-cn_all.ipk"
URL3="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/AdGuardHome_linux_mipsle_softfloat.tar.gz"

FILE1="adguardhome_1.1.1-r1_all.ipk"
FILE2="adguardhome-zh-cn_all.ipk"
FILE3="AdGuardHome_linux_mipsle_softfloat.tar.gz"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 用户执行此脚本。${NC}"
    exit 1
fi

# 检查必要命令
for cmd in wget opkg tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}错误：未找到命令 '$cmd'，请先安装对应的软件包。${NC}"
        exit 1
    fi
done

# 带重试功能的下载函数
# 参数1: URL  参数2: 输出文件名
download_with_retry() {
    local url="$1"
    local output="$2"
    local retry=5
    local delay=3

    while [ $retry -gt 0 ]; do
        echo -e "${YELLOW}[下载] 正在尝试下载 $output，剩余重试次数: $retry${NC}"
        # 使用 wget，忽略证书检查（OpenWrt 环境常见）
        wget --no-check-certificate -q -O "$output" "$url" 2>/dev/null
        if [ $? -eq 0 ] && [ -s "$output" ]; then
            echo -e "${GREEN}[下载] $output 下载成功${NC}"
            return 0
        else
            echo -e "${RED}[下载] $output 下载失败${NC}"
            rm -f "$output"
            retry=$((retry - 1))
            [ $retry -gt 0 ] && sleep $delay
        fi
    done
    echo -e "${RED}错误：多次重试后仍无法下载 $output，脚本终止。${NC}"
    exit 1
}

# ---------- 1. 下载文件 ----------
echo -e "${GREEN}========== 开始下载 AdGuardHome 安装文件 ==========${NC}"
download_with_retry "$URL1" "$FILE1"
download_with_retry "$URL2" "$FILE2"
download_with_retry "$URL3" "$FILE3"
echo -e "${GREEN}所有文件下载完成。${NC}"

# ---------- 2. 安装 ipk 包 ----------
echo -e "${GREEN}========== 安装 ipk 软件包 ==========${NC}"
opkg install "./$FILE1" "./$FILE2"
if [ $? -ne 0 ]; then
    echo -e "${RED}错误：ipk 包安装失败，请检查依赖或手动执行 opkg install。${NC}"
    exit 1
fi
echo -e "${GREEN}ipk 包安装成功。${NC}"

# ---------- 3. 解压并部署 AdGuardHome 二进制 ----------
echo -e "${GREEN}========== 部署 AdGuardHome 可执行文件 ==========${NC}"

# 创建临时解压目录（防止目录冲突）
TMP_DIR=$(mktemp -d -t adguard.XXXXXX)
tar -xzf "$FILE3" -C "$TMP_DIR"

if [ -f "$TMP_DIR/AdGuardHome/AdGuardHome" ]; then
    # 确保目标目录存在
    [ ! -d "/usr/bin" ] && mkdir -p /usr/bin
    # 移动并添加执行权限
    mv "$TMP_DIR/AdGuardHome/AdGuardHome" /usr/bin/AdGuardHome
    chmod +x /usr/bin/AdGuardHome
    echo -e "${GREEN}AdGuardHome 二进制已部署至 /usr/bin/AdGuardHome${NC}"
else
    echo -e "${RED}错误：解压后未找到 AdGuardHome 可执行文件，请检查压缩包内容。${NC}"
    rm -rf "$TMP_DIR"
    exit 1
fi

# 清理临时目录
rm -rf "$TMP_DIR"

# ---------- 4. 清理下载文件 ----------
echo -e "${GREEN}========== 清理临时文件 ==========${NC}"
rm -f "$FILE1" "$FILE2" "$FILE3"
echo -e "${GREEN}下载文件已删除。${NC}"

# ---------- 5. 完成提示 ----------
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AdGuardHome 安装成功！${NC}"
echo -e "你可以通过以下命令启动服务："
echo -e "  /usr/bin/AdGuardHome -s start"
echo -e "或配置为系统服务（视固件版本而定）。"
echo -e "${GREEN}========================================${NC}"
exit 0