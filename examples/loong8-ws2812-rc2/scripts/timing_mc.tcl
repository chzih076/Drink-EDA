# timing_mc.tcl — 多角时序分析（setup/hold）
# 完整 PnR + 多角 STA
set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set LIB_TT  "$PDK_DIR/lib/tt_025C_1v80_pnr.lib"
set LIB_SS  "$PDK_DIR/lib/ss_n40C_1v60_ccsnoise.lib"
set LIB_FF  "$PDK_DIR/lib/ff_n40C_1v95_ccsnoise.lib"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"

# ─── PnR 流程 ─────────────────────────────
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

# ─── 时钟约束 ─────────────────────────────
puts "\n=== 创建时钟约束 (50MHz) ==="
create_clock -name clk -period 20 -waveform {0 10} [get_ports clk]

# ============================================
# 1. TT 角（典型）
# ============================================
puts "\n========================================"
puts "=== 1. TT 角 (typ 25C 1.80V) ==="
puts "========================================"
puts "--- Setup (max path) ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3
puts "--- Hold (min path) ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3

# ============================================
# 2. SS 角（最差 setup：slow -40C 1.60V）
# ============================================
puts "\n========================================"
puts "=== 2. SS 角 (slow -40C 1.60V) ==="
puts "=== read_liberty -max 替换为 SS ==="
puts "========================================"
read_liberty -max $LIB_SS
puts "--- Setup (max) — 使用 SS 库 ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3
puts "--- Hold (min) — 仍用 SS 库 ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3

# ============================================
# 3. FF 角（最差 hold：fast -40C 1.95V）
# ============================================
puts "\n========================================"
puts "=== 3. FF 角 (fast -40C 1.95V) ==="
puts "=== read_liberty -min 替换为 FF ==="
puts "========================================"
read_liberty -min $LIB_FF
puts "--- Hold (min) — 使用 FF 库 ---"
find_timing_paths -path_delay min
report_worst_slack -min -digits 3
puts "--- Setup (max) — 仍用 FF 库 ---"
find_timing_paths -path_delay max
report_worst_slack -max -digits 3

puts "\n========================================"
puts "=== 所有角时序分析完成 ==="
puts "========================================"
