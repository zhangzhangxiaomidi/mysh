#!/bin/sh

# 定义文件 URL 和名称
IPK_URL="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/luci-app-openclash_0.47.055_all.ipk"
META_URL="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/clash_meta"
IPK_FILE="luci-app-openclash_0.47.055_all.ipk"
META_FILE="clash_meta"

# 定义目标路径
META_TARGET="/etc/openclash/core/clash_meta"

# 检查文件是否存在，若不存在则下载
download_if_not_exists() {
    local file=$1
    local url=$2
    if [ -f "$file" ]; then
        echo "✅ 文件 $file 已存在，跳过下载。"
    else
        echo "⬇️  正在下载 $file ..."
        wget -O --no-check-certificate "$file" "$url"
        if [ $? -eq 0 ]; then
            echo "✅ 下载 $file 成功。"
        else
            echo "❌ 下载 $file 失败，请检查网络或URL。"
            exit 1
        fi
    fi
}

# 1. 下载两个文件（当前目录）
echo "=== 开始检查并下载所需文件 ==="
download_if_not_exists "$IPK_FILE" "$IPK_URL"
download_if_not_exists "$META_FILE" "$META_URL"

# 2. 移动 clash_meta 到目标位置
echo "=== 准备移动 clash_meta 核心文件 ==="
if [ ! -d "/etc/openclash/core" ]; then
    echo "📁 目标目录 /etc/openclash/core 不存在，正在创建..."
    mkdir -p "/etc/openclash/core"
    if [ $? -ne 0 ]; then
        echo "❌ 创建目录失败，请检查权限。"
        exit 1
    fi
fi

if [ -f "$META_FILE" ]; then
    echo "🚚 正在移动 $META_FILE 到 $META_TARGET ..."
    mv "$META_FILE" "$META_TARGET"
    if [ $? -eq 0 ]; then
        echo "✅ 移动成功。"
        # 可选：设置可执行权限
        chmod +x "$META_TARGET"
    else
        echo "❌ 移动失败，请检查权限。"
        exit 1
    fi
else
    echo "❌ 未找到 $META_FILE，无法移动。"
    exit 1
fi

# 3. 安装 luci-app-openclash ipk 包
echo "=== 开始安装 OpenClash 插件 ==="
if [ -f "$IPK_FILE" ]; then
    echo "📦 正在使用 opkg 安装 $IPK_FILE ..."
    opkg install "$IPK_FILE"
    if [ $? -eq 0 ]; then
        echo "✅ OpenClash 安装成功。"
    else
        echo "❌ 安装失败，请检查依赖或手动安装。"
        exit 1
    fi
else
    echo "❌ 未找到 $IPK_FILE，无法安装。"
    exit 1
fi

echo "🎉 所有操作完成！"
