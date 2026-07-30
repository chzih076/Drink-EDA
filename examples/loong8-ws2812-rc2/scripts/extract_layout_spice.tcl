# extract_layout_spice.tcl — OpenROAD layout SPICE extraction for LVS
# Usage: openroad -no_init -no_splash -exit extract_layout_spice.tcl

set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"
set ROUTED_DEF "pnr/ws2812_routed.def"
set SYNTH_NET "synth/ws2812_pnr.v"
set CDL_MASTER "/tmp/sky130_fd_sc_hd_short.cdl"
set OUT_CDL "/tmp/ws2812_layout_openroad.spice"

puts "=== Reading LEF ==="
read_lef $TECHLEF
read_lef $MACROLEF

puts "=== Reading DEF ==="
read_def $ROUTED_DEF

puts "=== Linking design ==="
read_verilog $SYNTH_NET
link_design "ws2812b_ctrl"

puts "=== Writing CDL (SPICE netlist) ==="
write_cdl -include_fillers -masters $CDL_MASTER $OUT_CDL

puts "=== Done ==="
puts "Output: $OUT_CDL"
