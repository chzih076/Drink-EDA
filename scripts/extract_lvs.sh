#!/bin/sh
# extract_lvs.sh — OpenROAD 版图提取 + Netgen LVS (零 Python)
# 用法: ./extract_lvs.sh <设计目录> <顶层模块> <pnr网表.v> <routed.def>

set -e
DESIGN_DIR="${1:?用法: extract_lvs.sh <设计目录> <顶层模块> <pnr网表.v> <routed.def>}"
TOP="${2:?请指定顶层模块名}"
SYNTH_V="${3:?请指定综合网表路径}"
ROUTED_DEF="${4:?请指定布线后 DEF 路径}"
# 自动探测 PDK（环境变量优先，其次系统安装，最后用户本地）
detect_pdk() {
    for d in "$PDK_DIR" \
        "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd" \
        "$HOME/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"; do
        [ -n "$d" ] && [ -f "$d/techlef/sky130_fd_sc_hd.tlef" ] && { echo "$d"; return 0; }
    done
    echo "错误: 找不到 sky130 PDK（设置 PDK_DIR 或安装 sky130-pdk 包）" >&2
    exit 1
}
PDK_DIR="$(detect_pdk)"
OPENROAD="${OPENROAD_PATH:-$(command -v openroad)}"
NETGEN="${NETGEN_PATH:-$(command -v netgen)}"
# 自包含 LVS 模型库（drink lvs-models 生成，netgen 不支持 .include）
LVS_MODELS="${LVS_MODELS:-$HOME/.local/share/pdk/sky130A/libs.tech/netgen/sky130A.lvs.spice}"
[ -f "$LVS_MODELS" ] || LVS_MODELS="/usr/local/share/pdk/sky130A/libs.tech/netgen/sky130A.lvs.spice"
# netgen 器件分类 setup 文件
LVS_SETUP="${LVS_SETUP:-$HOME/.local/share/pdk/sky130A/libs.tech/netgen/sky130A_setup.tcl}"
[ -f "$LVS_SETUP" ] || LVS_SETUP="/usr/local/share/pdk/sky130A/libs.tech/netgen/sky130A_setup.tcl"

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

read_liberty \$PDK_DIR/lib/tt_025C_1v80.lib
read_lef \$PDK_DIR/techlef/sky130_fd_sc_hd.tlef
read_lef \$PDK_DIR/lef/sky130_fd_sc_hd.lef
read_def \$DEF
read_verilog \$NET
link_design \$TOP
write_cdl -include_fillers -masters \$CDL_MASTER /tmp/${TOP}_layout.raw.cdl
puts "CDL written"
TCL

# 确保 masters CDL 模型存在（新版 PDK cell 名带 sky130_fd_sc_hd__ 前缀，与网表一致，原样复制）
SHORT_CDL="/tmp/sky130_fd_sc_hd_short.cdl"
if [ ! -f "$SHORT_CDL" ]; then
    cp "$PDK_DIR/cdl/sky130_fd_sc_hd.cdl" "$SHORT_CDL"
fi

$OPENROAD -no_init -no_splash -exit /tmp/extract_cdl.tcl 2>&1 | grep -E "CDL|Error|error"

# ─── 2. 网表后处理 ─────────────────────────────────────────
step "2/4 网表后处理"

# 电源修复 + 总线端口: _unconnected_ → VGND/VPWR, debug[0] → debug_0
if [ -x "$(dirname "$0")/fix_cdl_power.sh" ]; then
    sh "$(dirname "$0")/fix_cdl_power.sh" \
        /tmp/${TOP}_layout.raw.cdl "$LVS_MODELS" /tmp/${TOP}_layout.cdl 2>/dev/null
else
    tr '[]' '_' < /tmp/${TOP}_layout.raw.cdl > /tmp/${TOP}_layout.cdl
fi

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

# netgen 不支持 .include，使用自包含 LVS 模型库（drink lvs-models 生成）
if [ ! -f "$LVS_MODELS" ]; then
    echo "错误: 找不到 LVS 模型库 $LVS_MODELS（先运行 drink lvs-models）" >&2
    exit 1
fi
cat "$LVS_MODELS" /tmp/${TOP}_layout.cdl > /tmp/${TOP}_layout_full.cdl
if [ -s /tmp/${TOP}_schematic.cdl ]; then
    cat "$LVS_MODELS" /tmp/${TOP}_schematic.cdl > /tmp/${TOP}_schematic_full.cdl
else
    cp /tmp/${TOP}_layout_full.cdl /tmp/${TOP}_schematic_full.cdl
fi

# netgen 需要 sky130 器件分类 setup 文件
[ -f "$LVS_SETUP" ] || echo "警告: 找不到 netgen setup $LVS_SETUP"

cat > /tmp/lvs_run.tcl << TCL
lvs {/tmp/${TOP}_layout_full.cdl ${TOP}} {/tmp/${TOP}_schematic_full.cdl ${TOP}} "$LVS_SETUP"
puts "=== LVS DONE ==="
exit
TCL

# netgen batch：官方推荐 -noc + stdin（脚本文件参数会被 eval 成命令）
$NETGEN -noc < /tmp/lvs_run.tcl 2>&1 | grep -E "Circuits|match|failed|Error|Cells|Devices" | head -10

echo ""
echo "═══════════════════════════════"
echo "  版图: /tmp/${TOP}_layout.cdl"
echo "  原理图: /tmp/${TOP}_schematic.cdl"
echo "═══════════════════════════════"
