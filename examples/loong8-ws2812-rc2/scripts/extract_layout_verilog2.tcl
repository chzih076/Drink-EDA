# extract_layout_verilog2.tcl — OpenROAD layout Verilog extraction (no include_pwr_gnd)

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

puts "=== Writing Verilog ==="
write_verilog $OUT_V

puts "=== Done ==="
puts "Output: $OUT_V"
