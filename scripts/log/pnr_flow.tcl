set LIB_PNR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/tt_025C_1v80_pnr.lib"
set TECHLEF "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
set SYNTH "synth/ws2812b_ctrl_pnr.v"
set TOP "ws2812b_ctrl"
set PNR "pnr"

read_liberty $LIB_PNR
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog $SYNTH
link_design $TOP

initialize_floorplan -die_area "0 0 100 100"   -core_area "[expr 100*0.1] [expr 100*0.1] [expr 100*0.9] [expr 100*0.9]"   -site unithd
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
detailed_route -output_drc $PNR/ws2812b_ctrl_drc.rpt
write_def $PNR/ws2812b_ctrl_routed.def
puts "=== ROUTED ==="
