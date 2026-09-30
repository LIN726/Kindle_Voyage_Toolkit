#!/bin/bash
# ==============================================================================
# 从亚马逊官方 S3 服务器下载 Kindle Voyage 5.13.6 官方最终版固件
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET="$DIR/update_kindle_voyage_5.13.6.bin"

if [ -f "$TARGET" ]; then
    echo "✅ 本地已存在 5.13.6 官方固件文件 ($TARGET)！"
    exit 0
fi

echo "正在从亚马逊官方 S3 服务器高速下载 Kindle Voyage 5.13.6 官方固件 (约 235MB)..."
curl -L -o "$TARGET" https://s3.amazonaws.com/firmwaredownloads/update_kindle_voyage_5.13.6.bin
if [ $? -eq 0 ]; then
    echo "✅ 下载完成！固件已保存至: $TARGET"
else
    echo "❌ 下载失败，请检查网络连接。"
fi
