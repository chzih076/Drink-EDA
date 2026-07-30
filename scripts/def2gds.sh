#!/bin/sh
# scripts/def2gds.sh — DEF→GDS 转换 (带 sky130 图层映射和后缀匹配)
# 用法: scripts/def2gds.sh <input.def> [output.gds]
#
# 依赖: strm2gds (KLayout, 需要打后缀匹配补丁)
# 环境变量:
#   PDK           — sky130 PDK 路径 (默认自动检测)
#   STRM2GDS_PATH — strm2gds 路径
#   SKY130_MAP    — 图层映射文件路径

set -e

if [ $# -lt 1 ]; then
    echo "用法: $0 <input.def> [output.gds]"
    exit 1
fi

INDEF="$1"
OUTGDS="${2:-${INDEF%.def}.gds}"

# PDK 自动检测
detect_pdk() {
    for d in "$PDK" \
        "$HOME/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"; do
        [ -f "$d/techlef/sky130_fd_sc_hd.tlef" ] && { echo "$d"; return 0; }
    done
    echo "错误: 找不到 sky130 PDK" >&2
    exit 1
}
PDK_DIR="$(detect_pdk)"

# strm2gds 检测
STRM2GDS="${STRM2GDS_PATH:-$(command -v strm2gds)}"
if [ -z "$STRM2GDS" ]; then
    echo "错误: 找不到 strm2gds, 请设置 STRM2GDS_PATH" >&2
    exit 1
fi

# KLayout 运行时
KLAYOUT_DIR="$(dirname "$STRM2GDS")"
export LD_LIBRARY_PATH="$KLAYOUT_DIR:$LD_LIBRARY_PATH"

TECHLEF="$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
MACROLEF="$PDK_DIR/lef/sky130_fd_sc_hd.lef"
GDS_LIB="$PDK_DIR/gds"
MAP_FILE="${SKY130_MAP:-$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"

MAP_OPT=""
[ -f "$MAP_FILE" ] && MAP_OPT="--lefdef-map $MAP_FILE"

echo "DEF → GDS: $INDEF → $OUTGDS"
$STRM2GDS \
  --lefdef-lefs "$TECHLEF,$MACROLEF" \
  --lefdef-lef-layouts-dir "$GDS_LIB" \
  --lefdef-macro-resolution-mode 2 \
  $MAP_OPT \
  "$INDEF" \
  "$OUTGDS"

echo "GDS: $(ls -lh "$OUTGDS" | awk '{print $5}')"
