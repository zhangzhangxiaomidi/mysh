#!/bin/sh

# ========================================
# OpenWrt 一键安装脚本
# 作者：clearlove
# ========================================

# 显示菜单函数
show_menu() {
    clear
    echo "========================================"
    echo "           OpenWrt 一键安装脚本"
    echo "               作者：clearlove"
    echo "========================================"
    echo "请选择安装选项："
    echo "1. 安装 Xray"
    echo "2. 安装 Passwall2"
    echo "3. 同时安装 Xray 和 Passwall2"
    echo "4. 退出"
    echo "========================================"
    printf "请输入选择 [1-4]: "
}

# 检查Xray是否已安装
check_xray_installed() {
    # 使用更可靠的方法检查Xray是否已安装
    if opkg list-installed | grep -E "xray-core|Xray" >/dev/null 2>&1; then
        echo "检测到 Xray 已安装，跳过安装。"
        return 0
    elif which xray >/dev/null 2>&1; then
        echo "检测到 Xray 已安装，跳过安装。"
        return 0
    else
        return 1
    fi
}

# 安装Xray函数
install_xray() {
    # 检查是否已安装
    if check_xray_installed; then
        return 0
    fi
    
    echo "开始安装 Xray..."
    echo "下载 Xray 安装包..."
    wget -O xray-core.ipk "https://ghfast.top/https://github.com/Crying-Center/uni-demo1/blob/master/xray-core_25.1.30-r1_mipsel_24kc.ipk"
    
    if [ $? -eq 0 ]; then
        echo "下载完成，开始安装..."
        opkg install xray-core.ipk
        if [ $? -eq 0 ]; then
            echo "Xray 安装成功！"
            rm -f xray-core.ipk
        else
            echo "Xray 安装失败！"
            return 1
        fi
    else
        echo "下载失败，请检查网络连接！"
        return 1
    fi
    return 0
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
        else
            echo "解压失败！"
            return 1
        fi
    else
        echo "下载失败，请检查网络连接！"
        return 1
    fi
    return 0
}

# 清理函数
cleanup() {
    echo "清理安装文件..."
    rm -f xray-core.ipk pw2-install.tar.gz 2>/dev/null
    rm -rf pw2-install-mipsel_24kc 2>/dev/null
    echo "清理完成！"
}

# 自删除函数
self_cleanup() {
    echo "脚本执行完成，正在删除自身..."
    rm -f "$0"
    echo "脚本已删除。感谢使用！"
    exit 0
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1)
            install_xray
            if [ $? -eq 0 ]; then
                cleanup
                self_cleanup
            else
                echo "Xray 安装失败，请检查日志！"
            fi
            ;;
        2)
            install_pw2
            if [ $? -eq 0 ]; then
                cleanup
                self_cleanup
            else
                echo "Passwall2 安装失败，请检查日志！"
            fi
            ;;
        3)
            install_xray
            xray_success=$?
            install_pw2
            pw2_success=$?
            
            if [ $xray_success -eq 0 ] && [ $pw2_success -eq 0 ]; then
                cleanup
                self_cleanup
            else
                echo "部分安装失败，Xray: $([ $xray_success -eq 0 ] && echo "成功" || echo "失败")"
                echo "Passwall2: $([ $pw2_success -eq 0 ] && echo "成功" || echo "失败")"
                echo "请检查日志获取详细信息。"
            fi
            ;;
        4)
            echo "退出安装脚本"
            exit 0
            ;;
        *)
            echo "无效选择，请重新输入！"
            sleep 2
            ;;
    esac
    
    echo ""
    echo "按回车键返回主菜单..."
    read dummy
done
