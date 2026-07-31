#!/bin/sh
# flow.sh — 通用 RTL→GDSII 一键流程脚本
# 用法: ./flow.sh <顶层模块名> <rtl.v> [芯片宽度] [芯片高度]
# 示例: ./flow.sh top rtl/top.v 100 100

set -e

if [ $# -lt 2 ]; then
    echo "用法: $0 <顶层模块名> <rtl.v> [芯片宽um] [芯片高um]"
    echo "示例: $0 ws2812b_ctrl rtl/ws2812_led.v"
    exit 1
fi

TOP="$1"
RTL="$2"
DIE_W="${3:-100}"
DIE_H="${4:-100}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 工具检测 ──────────────────────────────────────────────
find_tool() {
    cmd="$1"
    shift
    for p in "$@"; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v "$cmd" 2>/dev/null && return 0
    echo "错误: 找不到 $cmd" >&2
    exit 1
}

YOSYS="${YOSYS_PATH:-$(find_tool yosys)}"
OPENROAD="${OPENROAD_PATH:-$(find_tool openroad)}"
STRM2GDS="${STRM2GDS_PATH:-$(find_tool strm2gds)}"

# ─── PDK ──────────────────────────────────────────────────
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

LIB_CLEAN="$PDK_DIR/lib/tt_025C_1v80.lib"
LIB_PNR="$PDK_DIR/lib/tt_025C_1v80.lib"
TECHLEF="$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
MACROLEF="$PDK_DIR/lef/sky130_fd_sc_hd.lef"
GDS_LIB="$PDK_DIR/gds"
# MAP 文件自动探测（环境变量优先，其次用户本地，最后系统安装）
if [ -f "$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map" ]; then
    MAP_FILE="${SKY130_MAP:-$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"
elif [ -f "/usr/local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map" ]; then
    MAP_FILE="${SKY130_MAP:-/usr/local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"
fi

# ─── 目录 ─────────────────────────────────────────────────
SYNTH_DIR="synth"
PNR_DIR="pnr"
LOG_DIR="log"
mkdir -p "$SYNTH_DIR" "$PNR_DIR" "$LOG_DIR"

step() { echo ""; echo "▸ $1"; }

# ─── 1. 综合 ──────────────────────────────────────────────
step "1/4 综合 (Yosys + ABC)"
$YOSYS -l "$LOG_DIR/synth.log" -p "
  read_verilog $RTL;
  synth -top $TOP -flatten;
  dfflibmap -liberty $LIB_CLEAN;
  abc -liberty $LIB_CLEAN;
  opt;
  write_verilog $SYNTH_DIR/${TOP}_synth.v
"

# 网表映射
map_synth "$SYNTH_DIR/${TOP}_synth.v" "$SYNTH_DIR/${TOP}_pnr.v" 2>/dev/null || \
  cp "$SYNTH_DIR/${TOP}_synth.v" "$SYNTH_DIR/${TOP}_pnr.v"

cells=$(grep -c '^  [a-z].*_(' "$SYNTH_DIR/${TOP}_pnr.v" 2>/dev/null || echo "?")
echo "  单元数: ${cells:-N/A}"

# ─── 2. 布局布线 ──────────────────────────────────────────
step "2/4 布局布线 (OpenROAD)"
cat > "$LOG_DIR/pnr_flow.tcl" << TCL
set LIB_PNR "$LIB_PNR"
set TECHLEF "$TECHLEF"
set MACROLEF "$MACROLEF"
set SYNTH "$SYNTH_DIR/${TOP}_pnr.v"
set TOP "$TOP"
set PNR "$PNR_DIR"

read_liberty \$LIB_PNR
read_lef \$TECHLEF
read_lef \$MACROLEF
read_verilog \$SYNTH
link_design \$TOP

initialize_floorplan -die_area "0 0 $DIE_W $DIE_H" \
  -core_area "[expr $DIE_W*0.1] [expr $DIE_H*0.1] [expr $DIE_W*0.9] [expr $DIE_H*0.9]" \
  -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2

global_placement -skip_io -density 0.6
detailed_placement

add_global_connection -net VPWR -inst_pattern {.*} -pin_pattern {VPWR} -power
add_global_connection -net VGND -inst_pattern {.*} -pin_pattern {VGND} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND
define_pdn_grid -name "Core" -voltage_domains CORE
add_pdn_stripe -grid "Core" -layer met1 -width 0.48 -pitch 10 -offset 0 -followpins
add_pdn_stripe -grid "Core" -layer met2 -width 0.48 -pitch 10 -offset 5
add_pdn_connect -grid "Core" -layers {met1 met2}
pdngen

set block [ord::get_db_block]
foreach net [\$block getNets] {
  set nname [\$net getName]
  if {[regexp {one_} \$nname] || [regexp {zero_} \$nname]} { \$net setSpecial }
}

global_route -congestion_iterations 100
detailed_route -output_drc \$PNR/${TOP}_drc.rpt
write_def \$PNR/${TOP}_routed.def
puts "=== ROUTED ==="
TCL

$OPENROAD -no_init -no_splash -exit "$LOG_DIR/pnr_flow.tcl" 2>&1 | tee "$LOG_DIR/route.log"

violations=$(grep -oP 'violations\s*=\s*\K[0-9]+' "$LOG_DIR/route.log" | tail -1)
echo "  DRC 违例: ${violations:-0}"

# ─── 3. GDS ──────────────────────────────────────────────
step "3/4 GDS 生成 (strm2gds)"

$STRM2GDS \
  --lefdef-lefs "$TECHLEF,$MACROLEF" \
  --lefdef-lef-layouts-dir "$GDS_LIB" \
  --lefdef-macro-resolution-mode 2 \
  --lefdef-map "$MAP_FILE" \
  "$PNR_DIR/${TOP}_routed.def" \
  "$PNR_DIR/${TOP}.gds" 2>&1

gds_size=$(ls -lh "$PNR_DIR/${TOP}.gds" | awk '{print $5}')
echo "  GDS: $gds_size"

# ─── 4. 验证 ──────────────────────────────────────────────
step "4/4 验证"
echo "  ✅ 单元: ${cells:-N/A}"
echo "  ✅ DRC:  ${violations:-0}"
echo "  ✅ GDS:  $gds_size"
echo ""
echo "════════════════════════════════"
echo "  设计:     $TOP"
echo "  RTL:      $RTL"
echo "  PDK:      $PDK_DIR"
echo "  芯片:     ${DIE_W}x${DIE_H} um"
echo "  DRC:      ${violations:-N/A}"
echo "  GDS:      $gds_size"
echo "════════════════════════════════"
