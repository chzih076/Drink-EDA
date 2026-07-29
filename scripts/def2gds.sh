#!/bin/sh
# def2gds.sh — DEF → GDS 转换（strm2gds）
# 用法: def2gds.sh <输入.def> [输出.gds]
# 依赖: strm2gds (KLayout)
# 环境变量: PDK, STRM2GDS, KLAYOUT_DIR

DEF="${1:?用法: def2gds.sh <输入.def> [输出.gds]}"
GDS="${2:-${DEF%.def}.gds}"
PDK="${PDK:-/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd}"
KLAYOUT_DIR="${KLAYOUT_DIR:-/home/lik/klayout/bin-release}"
export LD_LIBRARY_PATH="$KLAYOUT_DIR:$LD_LIBRARY_PATH"
STRM2GDS="${STRM2GDS:-$KLAYOUT_DIR/strm2gds}"

[ -f "$DEF" ] || { echo "错误: 文件不存在: $DEF"; exit 1; }
[ -x "$STRM2GDS" ] || { echo "错误: 找不到 strm2gds"; exit 1; }

echo "DEF -> GDS: $DEF -> $GDS"
$STRM2GDS \
  --lefdef-lefs "$PDK/techlef/sky130_fd_sc_hd.tlef,$PDK/lef/sky130_fd_sc_hd.lef" \
  "$DEF" "$GDS"
