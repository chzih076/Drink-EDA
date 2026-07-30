set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set LIB_PNR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/tt_025C_1v80_pnr.lib"
set TECHLEF "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"

read_liberty $LIB_PNR
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog synth/ws2812_pnr.v
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
foreach net [$block getNets] {
  set nname [$net getName]
  if {[regexp {one_} $nname] || [regexp {zero_} $nname]} { $net setSpecial }
}

global_route -congestion_iterations 100
detailed_route -output_drc pnr/ws2812_drc.rpt
write_def pnr/ws2812_routed.def
puts "=== ROUTED ==="
