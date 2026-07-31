#!/bin/sh
# build.sh — loong8-ws2812-rc2 完整 RTL→GDSII 构建脚本
# 用法: ./build.sh [synth|pnr|gds|all|clean]
# 目标环境: LoongArch64 Linux, AOSC OS
#
# 工具链:
#   Yosys 0.67+    (RTL 综合)
#   OpenROAD 26Q3  (布局布线, GPL+or-tools)
#   KLayout 0.30.9 (GDS 流片格式输出)
#   strm2gds       (KLayout 配套流工具, 已打后缀匹配补丁)
#
# PDK: SkyWater sky130A (open-source PDK)

set -e

# ─── 工具路径检测 ────────────────────────────────────────
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

YOSYS="${YOSYS_PATH:-$(find_tool yosys /usr/local/bin/yosys)}"
OPENROAD="${OPENROAD_PATH:-$(find_tool openroad /usr/local/bin/openroad)}"
STRM2GDS="${STRM2GDS_PATH:-$(find_tool strm2gds /usr/local/bin/strm2gds)}"

# ─── PDK 路径检测 ─────────────────────────────────────────
detect_pdk() {
    for d in "$PDK" \
        "$HOME/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"; do
        [ -f "$d/techlef/sky130_fd_sc_hd.tlef" ] && { echo "$d"; return 0; }
    done
    echo "错误: 找不到 sky130 PDK" >&2
    exit 1
}
PDK="$(detect_pdk)"
LIB_CLEAN="$PDK/lib/tt_025C_1v80.lib"
LIB_PNR="$PDK/lib/tt_025C_1v80.lib"
TECHLEF="$PDK/techlef/sky130_fd_sc_hd.tlef"
MACROLEF="$PDK/lef/sky130_fd_sc_hd.lef"
GDS_LIB="$PDK/gds"
if [ -f "$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map" ]; then
    MAP_FILE="${SKY130_MAP:-$HOME/.local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"
elif [ -f "/usr/local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map" ]; then
    MAP_FILE="${SKY130_MAP:-/usr/local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map}"
fi

# ─── KLayout 运行时 ───────────────────────────────────────
KLAYOUT_DIR="$(dirname "$KLAYOUT")"
export LD_LIBRARY_PATH="$KLAYOUT_DIR:$LD_LIBRARY_PATH"

# ─── 目录 ─────────────────────────────────────────────────
RTL="rtl"
SYNTH="synth"
PNR="pnr"
LOG="log"
mkdir -p "$SYNTH" "$PNR" "$LOG"

step() { echo ""; echo "▸ $1"; }

# ═══════════════════════════════════════════════════════════
#  主流程
# ═══════════════════════════════════════════════════════════

case "${1:-all}" in

synth|all)
    step "1/4  综合 (Yosys + ABC)"
    $YOSYS -l "$LOG/synth.log" -p "
      read_verilog $RTL/ws2812_led.v;
      synth -top ws2812b_ctrl -flatten;
      dfflibmap -liberty $LIB_CLEAN;
      abc -liberty $LIB_CLEAN;
      opt;
      write_verilog $SYNTH/ws2812_synth.v
    "
    # 网表映射: 将 Yosys 输出的通用单元替换为 sky130 PDK 单元名
    # Yosys 输出短名 (如 and3), 需要映射为带驱动强度的完整名 (如 and3_1)
    MAP_SYNTH="${MAP_SYNTH_PATH:-$(command -v map_synth)}"
    if [ -n "$MAP_SYNTH" ]; then
        $MAP_SYNTH "$SYNTH/ws2812_synth.v" "$SYNTH/ws2812_pnr.v"
    else
        cp "$SYNTH/ws2812_synth.v" "$SYNTH/ws2812_pnr.v"
        echo "  警告: 未找到 map_synth, 使用原始网表"
    fi

    cells=$(grep -c '^  [a-z].*_(' "$SYNTH/ws2812_pnr.v" 2>/dev/null || echo "?")
    echo "  单元数: ${cells:-N/A}"
    echo "  单元数: $cells"
    ;;&

pnr|all)
    step "2/4  布局布线 (OpenROAD)"
    echo "  工具: $OPENROAD"
    echo "  PDK:  $PDK"

    # 写入 PnR Tcl 脚本
    cat > "$LOG/pnr_run.tcl" << TCL
set PDK_DIR "$PDK"
set LIB_PNR "$LIB_PNR"
set TECHLEF "$TECHLEF"
set MACROLEF "$MACROLEF"

read_liberty \$LIB_PNR
read_lef \$TECHLEF
read_lef \$MACROLEF
read_verilog $SYNTH/ws2812_pnr.v
link_design "ws2812b_ctrl"

initialize_floorplan -die_area "0 0 100 100" -core_area "10 10 90 90" -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2

# GPL 全局布局 (需要 or-tools)
global_placement -skip_io -density 0.6
detailed_placement

# PDN
add_global_connection -net VPWR -inst_pattern {.*} -pin_pattern {VPWR} -power
add_global_connection -net VGND -inst_pattern {.*} -pin_pattern {VGND} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND
define_pdn_grid -name "Core" -voltage_domains CORE
add_pdn_stripe -grid "Core" -layer met1 -width 0.48 -pitch 10 -offset 0 -followpins
add_pdn_stripe -grid "Core" -layer met2 -width 0.48 -pitch 10 -offset 5
add_pdn_connect -grid "Core" -layers {met1 met2}
pdngen

# 特殊线网标记
set block [ord::get_db_block]
foreach net [\$block getNets] {
  set nname [\$net getName]
  if {[regexp {one_} \$nname] || [regexp {zero_} \$nname]} { \$net setSpecial }
}

global_route -congestion_iterations 100
detailed_route -output_drc $PNR/ws2812_drc.rpt
write_def $PNR/ws2812_routed.def
puts "=== ROUTED ==="
TCL

    $OPENROAD -no_init -no_splash -exit "$LOG/pnr_run.tcl" 2>&1 | tee "$LOG/route.log"

    violations=$(grep -oP 'violations\s*=\s*\K[0-9]+' "$LOG/route.log" | tail -1)
    echo "  DRC 违例: ${violations:-0}"
    ;;&

gds|all)
    step "3/4  GDS 生成 (strm2gds + 后缀匹配)"

    # strm2gds 现已直接链接所有格式插件，无需 Python
    # RPATH 包含 /usr/local/lib/klayout/db_plugins
    MAP_FILE="${SKY130_MAP:-$MAP_FILE}"

    $STRM2GDS \
      --lefdef-lefs "$TECHLEF,$MACROLEF" \
      --lefdef-lef-layouts-dir "$GDS_LIB" \
      --lefdef-macro-resolution-mode 2 \
      --lefdef-map "$MAP_FILE" \
      "$PNR/ws2812_routed.def" \
      "$PNR/ws2812b_ctrl.gds" 2>&1

    gds_size=$(ls -lh "$PNR/ws2812b_ctrl.gds" | awk '{print $5}')
    echo "  GDS: $gds_size"
    ;;&

verify|all)
    step "4/4  验证"

    # 检查 GDS 完整性
    if [ -f "$PNR/ws2812b_ctrl.gds" ]; then
        echo "  ✅ GDS 文件存在: $(ls -lh $PNR/ws2812b_ctrl.gds | awk '{print $5}')"
    else
        echo "  ❌ GDS 文件缺失"
    fi

    # 检查 DRC
    if [ -f "$PNR/ws2812_drc.rpt" ]; then
        drc=$(wc -c < "$PNR/ws2812_drc.rpt")
        if [ "$drc" -eq 0 ]; then
            echo "  ✅ DRC: 0 违例"
        else
            echo "  ⚠️  DRC 报告非空 ($drc 字节)"
            cat "$PNR/ws2812_drc.rpt"
        fi
    else
        echo "  ⚠️  无 DRC 报告"
    fi

    # 检查 DEF
    if [ -f "$PNR/ws2812_routed.def" ]; then
        cells=$(grep -oP 'COMPONENTS\s+\K[0-9]+' "$PNR/ws2812_routed.def" 2>/dev/null || echo "?")
        echo "  ✅ DEF: $cells 个标准单元实例"
    fi
    ;;&

sim)
    step "仿真 (iverilog)"
    mkdir -p sim
    iverilog -g2012 -o sim/ws2812b.vvp "$RTL/ws2812_led.v" sim/ws2812b_tb.v 2>&1
    vvp sim/ws2812b.vvp 2>&1 | head -5
    echo "  注: 测试台未开启 VCD 转储（$dumpvars），如需波形请在 TB 中启用"
    ;;&

clean)
    rm -rf "$SYNTH" "$PNR" "$LOG" sim/ws2812b.vcd sim/ws2812b.vvp
    echo "已清理"
    ;;&

all)
    echo ""
    echo "═══════════════════════════════════════"
    echo "  loong8-ws2812-rc2 构建完成"
    echo "  RTL:       $RTL/ws2812_led.v"
    echo "  PDK:       $PDK"
    drc_val=$(grep -oP 'violations\s*=\s*\K[0-9]+' "$LOG/route.log" 2>/dev/null | tail -1)
    echo "  DRC:       ${drc_val:-N/A}"
    gds=$(ls -lh "$PNR/ws2812b_ctrl.gds" 2>/dev/null | awk '{print $5}')
    echo "  GDS:       ${gds:-N/A}"
    echo "═══════════════════════════════════════"
    ;;
esac
