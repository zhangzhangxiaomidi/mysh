#!/bin/sh

# 文件下载地址（使用 ghproxy.com 代理）
IPK_URL="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/luci-app-openclash_0.47.055_all.ipk"
META_URL="https://gh-proxy.com/https://github.com/zhangzhangxiaomidi/mysh/raw/refs/heads/main/clash_meta"

IPK_FILE="luci-app-openclash_0.47.055_all.ipk"
META_FILE="clash_meta"
META_TARGET="/etc/openclash/core/clash_meta"

echo "=== 开始安装 OpenClash ==="

# 定义下载函数（为避免重复代码，此处使用函数，但函数非常基础，不影响整体简洁性）
download_with_retry() {
    local file=$1
    local url=$2
    local max_attempts=3
    local attempt=1

    if [ -f "$file" ]; then
        echo "✅ 文件 $file 已存在，跳过下载。"
        return 0
    fi

    while [ $attempt -le $max_attempts ]; do
        echo "⬇️  正在下载 $file (尝试 $attempt/$max_attempts) ..."
        wget --no-check-certificate -O "$file" "$url"
        if [ $? -eq 0 ]; then
            echo "✅ 下载 $file 成功。"
            return 0
        else
            echo "⚠️ 下载 $file 失败。"
            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ 等待 2 秒后重试..."
                sleep 2
            fi
        fi
        attempt=$((attempt + 1))
    done

    echo "❌ 下载 $file 失败，已达最大重试次数。"
    exit 1
}

# 1. 下载 ipk 文件
download_with_retry "$IPK_FILE" "$IPK_URL"

# 2. 下载 clash_meta 文件
download_with_retry "$META_FILE" "$META_URL"

# 3. 创建目标目录（如果不存在）
if [ ! -d "/etc/openclash/core" ]; then
    echo "📁 目录 /etc/openclash/core 不存在，正在创建..."
    mkdir -p /etc/openclash/core
    if [ $? -ne 0 ]; then
        echo "❌ 创建目录失败。"
        exit 1
    fi
fi

# 4. 移动 clash_meta 到目标位置
if [ -f "$META_FILE" ]; then
    echo "🚚 移动 $META_FILE 到 $META_TARGET ..."
    mv "$META_FILE" "$META_TARGET"
    if [ $? -eq 0 ]; then
        echo "✅ 移动成功。"
        chmod +x "$META_TARGET"
    else
        echo "❌ 移动失败。"
        exit 1
    fi
else
    echo "❌ 错误：$META_FILE 不存在，无法移动。"
    exit 1
fi

# 5. 安装 ipk 包
if [ -f "$IPK_FILE" ]; then
    echo "📦 安装 $IPK_FILE ..."
    opkg install "$IPK_FILE"
    if [ $? -eq 0 ]; then
        echo "✅ OpenClash 安装成功。"
    else
        echo "❌ 安装失败。"
        exit 1
    fi
else
    echo "❌ 错误：$IPK_FILE 不存在，无法安装。"
    exit 1
fi

echo "🎉 所有操作完成！"
