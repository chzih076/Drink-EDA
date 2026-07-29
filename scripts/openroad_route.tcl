# openroad_route.tcl — 通用 OpenROAD 布线脚本
# 用法: openroad -exit openroad_route.tcl
# 环境变量: LIB, TECHLEF, MACROLEF, VERILOG, TOP, DIE_W, DIE_H, CORE_MARGIN

set LIB          ${LIB:?}
set TECHLEF      ${TECHLEF:?}
set MACROLEF     ${MACROLEF:?}
set VERILOG      ${VERILOG:?}
set TOP          ${TOP:?}
set DIE_W        ${DIE_W:-100}
set DIE_H        ${DIE_H:-100}
set CORE_MARGIN  ${CORE_MARGIN:-10}

read_liberty $LIB
read_lef $TECHLEF
read_lef $MACROLEF
read_verilog $VERILOG
link_design $TOP

initialize_floorplan -die_area "0 0 $DIE_W $DIE_H" \
  -core_area "$CORE_MARGIN $CORE_MARGIN [expr {$DIE_W - $CORE_MARGIN}] [expr {$DIE_H - $CORE_MARGIN}]" \
  -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2

set b [ord::get_db_block]; set x [expr {$CORE_MARGIN + 5}]; set y [expr {$CORE_MARGIN + 5}]
foreach i [$b getInsts] {
  place_inst -name [$i getName] -location "$x $y"
  set x [expr {$x + 5}]
  if {$x > [expr {$DIE_W - $CORE_MARGIN - 5}]} { set x [expr {$CORE_MARGIN + 5}]; set y [expr {$y + 6}] }
}
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
detailed_route -output_drc [file rootname $VERILOG]_drc.rpt
write_def [file rootname $VERILOG]_routed.def
puts "=== ROUTED ==="
