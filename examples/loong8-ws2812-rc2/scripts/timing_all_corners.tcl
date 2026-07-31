# timing_all_corners.tcl — 三角时序分析（TT + 近似 SS/FF）
# SS/FF 使用 timing derate 近似（基于 Sky130 典型工艺角差异）
if {[info exists ::env(PDK_DIR)]} {
    set PDK_DIR $::env(PDK_DIR)
} else {
    set PDK_DIR "/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
}
set LIB_TT  "$PDK_DIR/lib/tt_025C_1v80.lib"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"

# ─── PnR ───────────────────────────────────
read_liberty $LIB_TT
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog synth/ws2812_pnr.v
link_design "ws2812b_ctrl"

initialize_floorplan -die_area "0 0 100 100" \
  -core_area "10 10 90 90" -site unithd
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
foreach net [$block getNets] {
  set nname [$net getName]
  if {[regexp {one_} $nname] || [regexp {zero_} $nname]} { $net setSpecial }
}
global_route -congestion_iterations 100
detailed_route -output_drc pnr/ws2812_drc.rpt

create_clock -name clk -period 20 -waveform {0 10} [get_ports clk]

# =============================================
# 1. TT 角（典型 25°C 1.80V）
# =============================================
puts "\n========================================"
puts "【1/3】TT 角 (typ 25°C 1.80V)"
puts "========================================"
# 清除之前可能存在的 derate
unset_timing_derate

puts "--- Setup (max) ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3

puts "--- Hold (min) ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3

# =============================================
# 2. SS 角（最差 setup: slow -40°C 1.60V）
#    近似：单元延迟 × 1.25，互连线 × 1.20
# =============================================
puts "\n========================================"
puts "【2/3】SS 角 (slow -40°C 1.60V, 近似)"
puts "    单元 × 1.25, 互连线 × 1.20"
puts "========================================"
# 清除旧 derate
unset_timing_derate

# SS: 慢 corner — late path 更慢
set_timing_derate -late -cell_delay 1.25
set_timing_derate -late -net_delay 1.20
set_timing_derate -late -clock -cell_delay 1.15
set_timing_derate -late -clock -net_delay 1.10

puts "--- Setup (max) — SS corner ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3

puts "--- Hold (min) — SS corner ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3

# =============================================
# 3. FF 角（最差 hold: fast -40°C 1.95V）
#    近似：单元延迟 × 0.85，互连线 × 0.85
# =============================================
puts "\n========================================"
puts "【3/3】FF 角 (fast -40°C 1.95V, 近似)"
puts "    单元 × 0.85, 互连线 × 0.85"
puts "========================================"
unset_timing_derate

# FF: 快 corner — early path 更快（hold 更紧）
set_timing_derate -early -cell_delay 0.85
set_timing_derate -early -net_delay 0.85
set_timing_derate -early -clock -cell_delay 0.90
set_timing_derate -early -clock -net_delay 0.90

puts "--- Setup (max) — FF corner ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3

puts "--- Hold (min) — FF corner ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3

# =============================================
puts "\n========================================"
puts "三角时序分析完成"
puts "注意: SS/FF 为基于 TT 的 derate 近似值"
puts "========================================"
