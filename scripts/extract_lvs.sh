#!/bin/sh
# extract_lvs.sh — OpenROAD 版图提取 + Netgen LVS (零 Python)
# 用法: ./extract_lvs.sh <设计目录> <顶层模块> <pnr网表.v> <routed.def>

set -e
DESIGN_DIR="${1:?用法: extract_lvs.sh <设计目录> <顶层模块> <pnr网表.v> <routed.def>}"
TOP="${2:?请指定顶层模块名}"
SYNTH_V="${3:?请指定综合网表路径}"
ROUTED_DEF="${4:?请指定布线后 DEF 路径}"
PDK_DIR="${PDK_DIR:-/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd}"
OPENROAD="${OPENROAD_PATH:-$(command -v openroad)}"
NETGEN="${NETGEN_PATH:-$(command -v netgen)}"

if [ -z "$OPENROAD" ]; then echo "Error: openroad not found"; exit 1; fi

step() { echo ""; echo "▸ $1"; }

# ─── 1. OpenROAD 提取 CDL ──────────────────────────────────
step "1/4 OpenROAD CDL 提取"

cat > /tmp/extract_cdl.tcl << TCL
set PDK_DIR "$PDK_DIR"
set TOP "$TOP"
set DEF "$ROUTED_DEF"
set NET "$SYNTH_V"
set CDL_MASTER "/tmp/sky130_fd_sc_hd_short.cdl"

read_liberty \$PDK_DIR/lib/tt_025C_1v80_pnr.lib
read_lef \$PDK_DIR/techlef/sky130_fd_sc_hd.tlef
read_lef \$PDK_DIR/lef/sky130_fd_sc_hd.lef
read_def \$DEF
read_verilog \$NET
link_design \$TOP
write_cdl -include_fillers -masters \$CDL_MASTER /tmp/${TOP}_layout.raw.cdl
puts "CDL written"
TCL

# 确保短名 CDL 模型存在
SHORT_CDL="/tmp/sky130_fd_sc_hd_short.cdl"
if [ ! -f "$SHORT_CDL" ]; then
    while IFS= read -r line; do
        case "$line" in
            *sky130_fd_sc_hd__*) echo "${line//sky130_fd_sc_hd__/}" ;;
            *) echo "$line" ;;
        esac
    done < "$PDK_DIR/cdl/sky130_fd_sc_hd.cdl" > "$SHORT_CDL"
fi

$OPENROAD -no_init -no_splash -exit /tmp/extract_cdl.tcl 2>&1 | grep -E "CDL|Error|error"

$OPENROAD -no_init -no_splash -exit /tmp/extract_cdl.tcl 2>&1 | grep -E "CDL|Error|error"

# ─── 2. 网表后处理 ─────────────────────────────────────────
step "2/4 网表后处理"

# 端口命名: debug[0] → debug_0
tr '[]' '_' < /tmp/${TOP}_layout.raw.cdl > /tmp/${TOP}_layout.fix.cdl

# 电源修复: VNB→VGND, VPB→VPWR
awk '{gsub(/\<VNB\>/, "VGND"); gsub(/\<VPB\>/, "VPWR"); print}' \
  /tmp/${TOP}_layout.fix.cdl > /tmp/${TOP}_layout.cdl

echo "  Layout CDL: $(wc -l < /tmp/${TOP}_layout.cdl) lines"

# ─── 3. 原理图 SPICE ──────────────────────────────────────
step "3/4 原理图 SPICE 生成"
if [ -x "$(dirname "$0")/v2spice.sh" ]; then
    sh "$(dirname "$0")/v2spice.sh" "$SYNTH_V" /tmp/${TOP}_schematic.cdl 2>/dev/null
else
    echo "Warning: v2spice.sh not found, copy schematic manually"
fi
echo "  Schematic CDL: $(wc -l < /tmp/${TOP}_schematic.cdl 2>/dev/null || echo 0) lines"

# ─── 4. LVS ───────────────────────────────────────────────
step "4/4 LVS 比对"
if [ -z "$NETGEN" ]; then
    echo "Warning: netgen not found, skipping LVS"
    exit 0
fi

cat > /tmp/lvs_run.tcl << TCL
lvs /tmp/${TOP}_layout.cdl $TOP /tmp/${TOP}_schematic.cdl $TOP
puts "=== LVS DONE ==="
exit
TCL

$NETGEN -batch /tmp/lvs_run.tcl 2>&1 | grep -E "Circuits|match|failed|Error|Cells|Devices" | head -10

echo ""
echo "═══════════════════════════════"
echo "  版图: /tmp/${TOP}_layout.cdl"
echo "  原理图: /tmp/${TOP}_schematic.cdl"
echo "═══════════════════════════════"
