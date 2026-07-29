set LIB "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
read_liberty $LIB/lib/tt_025C_1v80_pnr.lib
read_lef $LIB/techlef/sky130_fd_sc_hd.tlef
read_lef $LIB/lef/sky130_fd_sc_hd.lef
read_verilog synth/ws2812_pnr.v
link_design "ws2812b_ctrl"
initialize_floorplan -die_area "0 0 100 100" -core_area "10 10 90 90" -site unithd
make_tracks; place_pins -hor_layers met1 -ver_layers met2
set b [ord::get_db_block]; set x 15; set y 15
foreach i [$b getInsts] { place_inst -name [$i getName] -location "$x $y"
  set x [expr {$x + 5}]; if {$x > 85} { set x 15; set y [expr {$y + 6}] } }
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
foreach net [split [$block getNets] " "] {
  set nname [$net getName]
  if {[regexp {one_} $nname] || [regexp {zero_} $nname]} { $net setSpecial }
}
global_route -congestion_iterations 100
detailed_route -output_drc pnr/ws2812_drc.rpt
write_def pnr/ws2812_routed.def
puts "=== ROUTED ==="
