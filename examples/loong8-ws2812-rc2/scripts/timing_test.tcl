# timing_test.tcl — 多角时序分析测试
set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set LIB_TT  "$PDK_DIR/lib/tt_025C_1v80_pnr.lib"
set LIB_SS  "$PDK_DIR/lib/ss_n40C_1v60_ccsnoise.lib"
set LIB_FF  "$PDK_DIR/lib/ff_n40C_1v95_ccsnoise.lib"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"

# 检查可用的 SS/FF lib（先尝试非 ccsnoise 版本）
set LIB_SS  "$PDK_DIR/lib/ss_n40C_1v60_ccsnoise.lib"
set LIB_FF  "$PDK_DIR/lib/ff_n40C_1v95_ccsnoise.lib"

puts "=== 检查 lib 文件 ==="
puts "TT: $LIB_TT"
puts "SS: $LIB_SS"
puts "FF: $LIB_FF"

if {![file exists $LIB_TT]} { puts "ERROR: TT lib missing"; exit 1 }
if {![file exists $LIB_SS]} { puts "ERROR: SS lib missing"; exit 1 }
if {![file exists $LIB_FF]} { puts "ERROR: FF lib missing"; exit 1 }

# ─── 加载设计 ────────────────────────────────────────────
read_liberty $LIB_TT
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog synth/ws2812_pnr.v
link_design "ws2812b_ctrl"

# ─── Floorplan & placement ───────────────────────────────
initialize_floorplan -die_area "0 0 100 100" \
  -core_area "10 10 90 90" -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2
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

# Route
set block [ord::get_db_block]
foreach net [$block getNets] {
  set nname [$net getName]
  if {[regexp {one_} $nname] || [regexp {zero_} $nname]} { $net setSpecial }
}
global_route -congestion_iterations 100
detailed_route -output_drc pnr/ws2812_drc.rpt

puts "\n========================================"
puts "=== 1. TT 角 (典型) 时序分析 ==="
puts "========================================"
find_timing_paths -path_delay max
puts "TT setup worst_slack: [report_worst_slack -max -digits 3]"
find_timing_paths -path_delay min
puts "TT hold worst_slack:  [report_worst_slack -min -digits 3]"

puts "\n=== 尝试 set_operating_conditions 方法 ==="

# 尝试方法1: set_operating_conditions with bc_wc
puts "\n--- 方法1: set_operating_conditions -analysis_type bc_wc ---"
set_operating_conditions -analysis_type bc_wc -max_library $LIB_SS -min_library $LIB_FF
find_timing_paths -path_delay min_max
puts "SS (max) setup worst_slack: [report_worst_slack -max -digits 3]"
puts "FF (min) hold worst_slack:  [report_worst_slack -min -digits 3]"

# 尝试方法2: 仅 max 库替换
puts "\n--- 方法2: set_operating_conditions SS (max only) ---"
set_operating_conditions -max_library $LIB_SS
find_timing_paths -path_delay max
puts "SS setup worst_slack: [report_worst_slack -max -digits 3]"

puts "\n--- 方法3: set_operating_conditions FF (min only) ---"
set_operating_conditions -min_library $LIB_FF
find_timing_paths -path_delay min
puts "FF hold worst_slack:  [report_worst_slack -min -digits 3]"

puts "\n=== DONE ==="
