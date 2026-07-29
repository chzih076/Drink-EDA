#!/bin/sh
# def2gds.sh — DEF → GDS 转换
# 用法: ./def2gds.sh <输入.def> [输出.gds]
# 依赖: strm2gds (KLayout 自带工具)

if [ $# -lt 1 ]; then
    echo "用法: $0 <输入.def> [输出.gds]"
    exit 1
fi

DEF="$1"
GDS="${2:-${DEF%.def}.gds}"
PDK="${PDK:-/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd}"
export LD_LIBRARY_PATH="${KLAYOUT_DIR:-/home/lik/klayout/bin-release}:$LD_LIBRARY_PATH"
STRM2GDS="${STRM2GDS:-/home/lik/klayout/bin-release/strm2gds}"

[ -f "$DEF" ] || { echo "错误: 文件不存在: $DEF"; exit 1; }
[ -f "$STRM2GDS" ] || { echo "错误: strm2gds 不存在: $STRM2GDS"; exit 1; }

echo "DEF -> GDS: $DEF -> $GDS"
$STRM2GDS \
  --lefdef-lefs "$PDK/techlef/sky130_fd_sc_hd.tlef,$PDK/lef/sky130_fd_sc_hd.lef" \
  "$DEF" "$GDS"
echo "GDS: $(ls -lh $GDS | awk '{print $5}')"
