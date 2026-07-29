#!/bin/sh
# build.sh — loong8-ws2812-rc1 一键构建
# 用法: ./build.sh [synth|pnr|gds|clean|all]
# 默认: all（综合 → 布线 → GDS）
# 无硬编码路径，所有工具自动检测

set -e

# ─── 工具自动检测 ───────────────────────────────────────────
find_tool() {
    cmd="$1"
    shift
    for p in "$@"; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v "$cmd" 2>/dev/null && return 0
    echo "错误: 找不到 $cmd，请安装或设置 ${cmd^^}_PATH 环境变量" >&2
    exit 1
}

YOSYS="${YOSYS_PATH:-$(find_tool yosys /home/lik/.local/bin/yosys /usr/local/bin/yosys)}"
OPENROAD="${OPENROAD_PATH:-$(find_tool openroad /home/lik/.local/bin/openroad /usr/local/bin/openroad)}"
STRM2GDS="${STRM2GDS_PATH:-$(find_tool strm2gds /home/lik/klayout/bin-release/strm2gds /usr/local/bin/strm2gds)}"
MAP_SYNTH="${MAP_SYNTH_PATH:-$(find_tool map_synth /home/lik/.local/bin/map_synth /usr/local/bin/map_synth)}"

# ─── PDK 自动检测 ──────────────────────────────────────────
detect_pdk() {
    for d in \
        "$PDK" \
        "$HOME/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"; do
        [ -f "$d/techlef/sky130_fd_sc_hd.tlef" ] && { echo "$d"; return 0; }
    done
    echo "错误: 找不到 sky130 PDK，请设置 PDK 环境变量" >&2
    exit 1
}
PDK="$(detect_pdk)"
LIB_CLEAN="$PDK/lib/tt_025C_1v80_clean.lib"
LIB_PNR="$PDK/lib/tt_025C_1v80_pnr.lib"
TECHLEF="$PDK/techlef/sky130_fd_sc_hd.tlef"
MACROLEF="$PDK/lef/sky130_fd_sc_hd.lef"
GDS_LIB="$PDK/gds"

# ─── KLayout 运行时 ────────────────────────────────────────
KLAYOUT_DIR="$(dirname "$STRM2GDS")"
export LD_LIBRARY_PATH="$KLAYOUT_DIR:$LD_LIBRARY_PATH"

# ─── 目录 ───────────────────────────────────────────────────
RTL="rtl"
SYNTH="synth"
PNR="pnr"
LOG="log"
mkdir -p $SYNTH $PNR $LOG

step() { echo ""; echo "▸ $1"; }

# ─── 子命令 ────────────────────────────────────────────────
case "${1:-all}" in
synth|all)
    step "综合 (Yosys + ABC)"
    $YOSYS -l $LOG/synth.log -p "
      read_verilog $RTL/ws2812_led.v;
      synth -top ws2812b_ctrl -flatten;
      dfflibmap -liberty $LIB_CLEAN;
      abc -liberty $LIB_CLEAN;
      opt;
      write_verilog $SYNTH/ws2812_synth.v
    "
    $MAP_SYNTH $SYNTH/ws2812_synth.v $SYNTH/ws2812_pnr.v
    cells=$(grep -c '^  [a-z].*_(' $SYNTH/ws2812_pnr.v 2>/dev/null || echo "?")
    echo "  单元: $cells"
    ;;&

pnr|all)
    step "布局布线 (OpenROAD)"
    cat > /tmp/route_$$.tcl << TCL
set LIB "$LIB_PNR"
read_liberty \$LIB
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog $SYNTH/ws2812_pnr.v
link_design "ws2812b_ctrl"
initialize_floorplan -die_area "0 0 100 100" -core_area "10 10 90 90" -site unithd
make_tracks; place_pins -hor_layers met1 -ver_layers met2
set b [ord::get_db_block]; set x 15; set y 15
foreach i [\$b getInsts] { place_inst -name [\$i getName] -location "\$x \$y"
  set x [expr {\$x + 5}]; if {\$x > 85} { set x 15; set y [expr {\$y + 6}] } }
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
foreach net [split [\$block getNets] " "] {
  set nname [\$net getName]
  if {[regexp {one_} \$nname] || [regexp {zero_} \$nname]} { \$net setSpecial }
}
global_route -congestion_iterations 100
detailed_route -output_drc $PNR/ws2812_drc.rpt
write_def $PNR/ws2812_routed.def
puts "=== ROUTED ==="
TCL
    $OPENROAD -no_init -no_splash -exit /tmp/route_$$.tcl 2>&1 | tee $LOG/route.log
    rm -f /tmp/route_$$.tcl
    violations=$(grep "Number of violations" $LOG/route.log | tail -1 | grep -o '[0-9]*')
    echo "  DRC 违例: ${violations:-N/A}"
    ;;&

gds|all)
    step "GDS (strm2gds)"
    [ -f "$PNR/ws2812_routed.def" ] || { echo "错误: 请先执行 ./build.sh pnr"; exit 1; }
    $STRM2GDS \
      --lefdef-lefs "$TECHLEF,$MACROLEF" \
      $PNR/ws2812_routed.def \
      $PNR/ws2812b_ctrl.gds 2>&1 | tail -1
    echo "  GDS: $(ls -lh $PNR/ws2812b_ctrl.gds | awk '{print $5}')"
    ;;&

sim)
    step "仿真 (iverilog)"
    mkdir -p sim
    iverilog -g2012 -o sim/ws2812b.vvp $RTL/ws2812_led.v sim/ws2812b_tb.v 2>&1
    vvp sim/ws2812b.vvp 2>&1 | head -5
    echo "  波形: sim/ws2812b.vcd"
    ;;&

clean)
    rm -rf $SYNTH $PNR $LOG sim/*.vcd sim/*.vvp
    echo "已清理"
    ;;&

all)
    echo ""
    echo "═ loong8-ws2812-rc1 ═════════════════"
    echo "  RTL:       $RTL/ws2812_led.v"
    echo "  PDK:       $PDK"
    violations=$(grep "Number of violations" $LOG/route.log 2>/dev/null | tail -1 | grep -o '= [0-9]*' | tr -d '= ')
    echo "  DRC:       ${violations:-N/A}"
    gds=$(ls -lh $PNR/ws2812b_ctrl.gds 2>/dev/null | awk '{print $5}')
    echo "  GDS:       ${gds:-N/A}"
    echo "═════════════════════════════════════"
    ;;
esac
