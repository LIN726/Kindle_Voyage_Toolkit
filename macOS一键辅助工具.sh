#!/bin/bash
# ==============================================================================
# Kindle Voyage 越狱与生态部署一键助手 (macOS 专属)
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
KINDLE_MOUNT="/Volumes/Kindle"

echo "=========================================================="
echo "    Kindle Voyage 越狱 + KOReader + 微信读书 一键辅助工具"
echo "=========================================================="

check_kindle() {
    if [ ! -d "$KINDLE_MOUNT" ]; then
        echo ""
        echo "❌ 未检测到挂载的 Kindle 设备（未找到 $KINDLE_MOUNT 目录）！"
        echo "👉 请用 USB 数据线连接 Kindle，并在 Kindle 屏幕上确认已进入【USB驱动器模式】。"
        echo ""
        return 1
    fi
    echo "✅ 已成功检测到 Kindle 挂载点: $KINDLE_MOUNT"
    return 0
}

while true; do
    echo ""
    echo "请选择要执行的操作："
    echo "  [0] 检查 Kindle 连接状态"
    echo "  [1] 升级/恢复官方 5.13.6 固件 (适用于固件低于 5.12.2.2 的设备)"
    echo "  [2] 写入第1步越狱文件 (.demo 文件夹，默认 5.13.6 固件)"
    echo "  [3] 写入第1步越狱收尾补丁 (Update_hotfix_watchthis_custom.bin)"
    echo "  [4] 写入第2步环境与启动器 (MRPI + KUAL + 持久化Hotfix)"
    echo "  [5] 写入第3步阅读器与插件 (KOReader + 觅阅 MiuRead 微信读书)"
    echo "  [6] 一键完成第2步与第3步写入 (KUAL + KOReader + 觅阅 一并拷贝)"
    echo "  [7] 一键将微信读书插件切换为【WeRead 原版】(更轻量稳定，更适合 Voyage)"
    echo "  [8] 一键切回【觅阅 MiuRead 插件】"
    echo "  [q] 退出"
    echo ""
    read -p "请输入选项编号: " choice

    case $choice in
        0)
            check_kindle
            ;;
        1)
            check_kindle || continue
            echo "正在拷贝官方 5.13.6 固件到 Kindle 根目录..."
            cp -v "$DIR/00_备用官方固件_5.13.6/update_kindle_voyage_5.13.6.bin" "$KINDLE_MOUNT/"
            sync
            echo "✅ 固件拷贝完成！请在 Mac 上安全弹出 Kindle，进入 Kindle【设置】->【更新您的 Kindle】。"
            ;;
        2)
            check_kindle || continue
            echo "请确认您的 Kindle Voyage 固件版本："
            echo "  1) 5.13.6 (默认，绝大多数机器)"
            echo "  2) 5.13.5"
            echo "  3) 5.13.4"
            read -p "请选择 (默认 1): " fw_choice
            fw_dir="固件_5.13.6_适用(最常见)"
            if [ "$fw_choice" == "2" ]; then
                fw_dir="固件_5.13.5_适用"
            elif [ "$fw_choice" == "3" ]; then
                fw_dir="固件_5.13.4_适用"
            fi
            echo "正在拷贝 $fw_dir 下的 .demo 目录到 Kindle 根目录..."
            rm -rf "$KINDLE_MOUNT/.demo"
            cp -r "$DIR/01_第一步_WatchThis越狱文件/按固件版本选取写入Kindle根目录的.demo文件夹/$fw_dir/.demo" "$KINDLE_MOUNT/"
            sync
            echo "✅ .demo 目录及文件拷贝成功！"
            echo "👉 请在 Mac 上安全弹出 Kindle，然后在 Kindle 屏幕上点击【Done】继续完成越狱。"
            ;;
        3)
            check_kindle || continue
            echo "正在拷贝 WatchThis 收尾补丁到 Kindle 根目录..."
            cp -v "$DIR/01_第一步_WatchThis越狱文件/越狱触发后放入Kindle根目录/Update_hotfix_watchthis_custom.bin" "$KINDLE_MOUNT/"
            sync
            echo "✅ 补丁拷贝完成！"
            echo "👉 请在 Mac 上安全弹出 Kindle，在 Kindle 搜索框输入 ;dsts 并回车，点击【Update Your Kindle】。"
            ;;
        4)
            check_kindle || continue
            echo "正在拷贝 MRPI、KUAL 与持久化 Hotfix 到 Kindle 根目录..."
            cp -r "$DIR/02_第二步_环境与安装器_MRPI与KUAL/直接复制到Kindle根目录/"* "$KINDLE_MOUNT/"
            sync
            echo "✅ 拷贝完成！"
            echo "👉 请安全弹出 Kindle，然后在搜索框输入 ;log mrpi 并回车触发自动安装！"
            ;;
        5)
            check_kindle || continue
            echo "正在拷贝 KOReader 及已集成的觅阅插件到 Kindle 根目录..."
            cp -r "$DIR/03_第三步_阅读器与微信读书插件_KOReader与觅阅/直接复制到Kindle根目录/"* "$KINDLE_MOUNT/"
            sync
            echo "✅ 拷贝完成！"
            echo "👉 请安全弹出 Kindle，打开书架上的 KUAL 图标，即可看到 KOReader 启动入口！"
            ;;
        6)
            check_kindle || continue
            echo "正在批量拷贝 MRPI + KUAL + KOReader + 觅阅插件..."
            cp -r "$DIR/02_第二步_环境与安装器_MRPI与KUAL/直接复制到Kindle根目录/"* "$KINDLE_MOUNT/"
            cp -r "$DIR/03_第三步_阅读器与微信读书插件_KOReader与觅阅/直接复制到Kindle根目录/"* "$KINDLE_MOUNT/"
            sync
            echo "✅ 全部文件已成功写入 Kindle！"
            echo "👉 接下来只需两步："
            echo "   1. 安全弹出 Kindle，搜索框输入 ;log mrpi 回车安装 KUAL。"
            echo "   2. 安装完成后打开 KUAL，点击 KOReader 启动，右上角齿轮打开觅阅扫码登录！"
            ;;
        7)
            check_kindle || continue
            echo "正在将 Kindle 上的微信读书插件切换为【WeRead 原版】..."
            plugins_dir="$KINDLE_MOUNT/koreader/plugins"
            if [ ! -d "$plugins_dir" ]; then
                echo "❌ 未在 Kindle 上找到 $plugins_dir 目录，请先确保已安装 KOReader！"
                continue
            fi
            # 移除旧插件并放入 weread
            rm -rf "$plugins_dir/miuread.koplugin" "$plugins_dir/weread.koplugin"
            cp -r "$DIR/备选插件_WeRead原版/weread.koplugin" "$plugins_dir/"
            sync
            echo "✅ 已成功切换为 WeRead 原版插件！"
            echo "👉 请安全弹出 Kindle，进入 KOReader 重新打开右上角微信读书即可重新扫码使用！"
            ;;
        8)
            check_kindle || continue
            echo "正在将 Kindle 上的微信读书插件切回【觅阅 MiuRead】..."
            plugins_dir="$KINDLE_MOUNT/koreader/plugins"
            if [ ! -d "$plugins_dir" ]; then
                echo "❌ 未在 Kindle 上找到 $plugins_dir 目录，请先确保已安装 KOReader！"
                continue
            fi
            rm -rf "$plugins_dir/miuread.koplugin" "$plugins_dir/weread.koplugin"
            cp -r "$DIR/03_第三步_阅读器与微信读书插件_KOReader与觅阅/直接复制到Kindle根目录/koreader/plugins/miuread.koplugin" "$plugins_dir/"
            sync
            echo "✅ 已成功切回 觅阅 MiuRead 插件！"
            echo "👉 请安全弹出 Kindle，进入 KOReader 即可重新使用！"
            ;;
        q|Q)
            echo "已退出助手。"
            break
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
done
