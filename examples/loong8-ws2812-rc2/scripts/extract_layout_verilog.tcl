# extract_layout_verilog.tcl — OpenROAD layout Verilog extraction for LVS
# Exports Verilog with power/ground, then v2spice.sh converts to SPICE

set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"
set ROUTED_DEF "pnr/ws2812_routed.def"
set OUT_V "pnr/ws2812_layout.v"

puts "=== Reading LEF ==="
read_lef $TECHLEF
read_lef $MACROLEF

puts "=== Reading DEF ==="
read_def $ROUTED_DEF

puts "=== Writing Verilog with power/ground ==="
write_verilog -include_pwr_gnd $OUT_V

puts "=== Done ==="
puts "Output: $OUT_V"
