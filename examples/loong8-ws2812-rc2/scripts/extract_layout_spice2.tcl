# extract_layout_spice2.tcl — OpenROAD layout SPICE extraction with power connections

set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"
set ROUTED_DEF "pnr/ws2812_routed.def"
set CDL_MASTER "/tmp/sky130_fd_sc_hd_short.cdl"
set OUT_CDL "/tmp/ws2812_layout_openroad.spice"

puts "=== Reading LEF ==="
read_lef $TECHLEF
read_lef $MACROLEF

puts "=== Reading DEF ==="
read_def $ROUTED_DEF

puts "=== Setting up global power connections ==="
add_global_connection -net VPWR -inst_pattern {.*} -pin_pattern {VPWR} -power
add_global_connection -net VGND -inst_pattern {.*} -pin_pattern {VGND} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND

puts "=== Writing CDL (SPICE netlist) ==="
write_cdl -include_fillers -masters $CDL_MASTER $OUT_CDL

puts "=== Done ==="
puts "Output: $OUT_CDL"
