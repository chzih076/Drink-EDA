# pnr_flow.tcl — OpenROAD PnR script for loong8-ws2812-rc2
# Usage: openroad -no_init -no_splash -exit pnr_flow.tcl
#
# PDK paths (edit these for your environment)
set PDK_DIR "/home/lik/.local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd"
set LIB_PNR "$PDK_DIR/lib/tt_025C_1v80_pnr.lib"
set TECHLEF "$PDK_DIR/techlef/sky130_fd_sc_hd.tlef"
set MACROLEF "$PDK_DIR/lef/sky130_fd_sc_hd.lef"

# ─── Read design data ───────────────────────────────────────
read_liberty $LIB_PNR
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog synth/ws2812_pnr.v
link_design "ws2812b_ctrl"

# ─── Floorplan ──────────────────────────────────────────────
initialize_floorplan -die_area "0 0 100 100" \
  -core_area "10 10 90 90" -site unithd
make_tracks

# ─── Pin placement ──────────────────────────────────────────
place_pins -hor_layers met1 -ver_layers met2

# ─── Global placement (RePlAce + or-tools) ──────────────────
global_placement -skip_io -density 0.6

# ─── Detailed placement ─────────────────────────────────────
detailed_placement

# ─── Power Distribution Network ─────────────────────────────
add_global_connection -net VPWR -inst_pattern {.*} -pin_pattern {VPWR} -power
add_global_connection -net VGND -inst_pattern {.*} -pin_pattern {VGND} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND
define_pdn_grid -name "Core" -voltage_domains CORE
add_pdn_stripe -grid "Core" -layer met1 -width 0.48 -pitch 10 -offset 0 -followpins
add_pdn_stripe -grid "Core" -layer met2 -width 0.48 -pitch 10 -offset 5
add_pdn_connect -grid "Core" -layers {met1 met2}
pdngen

# ─── Mark zero_/one_ nets as special (required by TritonRoute) ─
set block [ord::get_db_block]
foreach net [$block getNets] {
  set nname [$net getName]
  if {[regexp {one_} $nname] || [regexp {zero_} $nname]} {
    $net setSpecial
  }
}

# ─── Global route (FastRoute) ───────────────────────────────
global_route -congestion_iterations 100

# ─── Detailed route (TritonRoute) ───────────────────────────
detailed_route -output_drc pnr/ws2812_drc.rpt

# ─── Write output ───────────────────────────────────────────
write_def pnr/ws2812_routed.def
puts "=== ROUTED ==="
puts "DRC violations: [report_drc]"
