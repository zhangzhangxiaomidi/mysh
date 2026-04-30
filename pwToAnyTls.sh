#!/bin/sh

# 定义文件名和下载地址
SINGBOX_IPK="sing-box_1.12.15-r1_mipsel_24kc.ipk"
PASSWALL_IPK="23.05-24.10_luci-app-passwall_26.4.15-r1_all.ipk"
LANG_IPK="23.05-24.10_luci-i18n-passwall-zh-cn_26.4.15_all.ipk"

URL_PREFIX="https://gh-proxy.com/https://raw.githubusercontent.com/zhangzhangxiaomidi/mysh/refs/heads/main"

URL_SINGBOX="$URL_PREFIX/$SINGBOX_IPK"
URL_PASSWALL="$URL_PREFIX/$PASSWALL_IPK"
URL_LANG="$URL_PREFIX/$LANG_IPK"

echo "------------------------------------------------"
echo "开始执行 PassWall & Sing-box 升级脚本 (AnyTLS 支持)"
echo "------------------------------------------------"

# 1. 检查并清理旧文件
echo "[1/4] 正在检查并清理残留安装包..."
for file in "$SINGBOX_IPK" "$PASSWALL_IPK" "$LANG_IPK"; do
    if [ -f "$file" ]; then
        echo "发现旧文件 $file，正在删除..."
        rm -f "$file"
    fi
done

# 2. 下载文件
echo "[2/4] 正在下载最新安装包..."

download_file() {
    echo "正在下载: $1"
    wget --show-progress -O "$1" "$2"
    if [ $? -ne 0 ]; then
        echo "错误: $1 下载失败，请检查网络连接。"
        exit 1
    fi
}

download_file "$SINGBOX_IPK" "$URL_SINGBOX"
download_file "$PASSWALL_IPK" "$URL_PASSWALL"
download_file "$LANG_IPK" "$URL_LANG"

# 3. 安装软件
echo "[3/4] 正在开始安装程序..."

# 先安装 Sing-box
echo "正在安装 Sing-box核心..."
opkg install "$SINGBOX_IPK"
if [ $? -ne 0 ]; then
    echo "警告: Sing-box 安装可能存在依赖问题，请检查输出。"
fi

# 安装 PassWall 及其语言包
echo "正在安装 PassWall 插件及中文语言包..."
opkg install "$PASSWALL_IPK" "$LANG_IPK"

# 4. 清理工作
echo "[4/4] 正在进行后期清理..."

# 删除安装包
rm -f "$SINGBOX_IPK" "$PASSWALL_IPK" "$LANG_IPK"
echo "已删除安装包。"

echo "------------------------------------------------"
echo "安装完成！请前往路由器后台刷新查看。"
echo "脚本即将自毁..."
echo "------------------------------------------------"

# 删除脚本自身
rm -- "$0"