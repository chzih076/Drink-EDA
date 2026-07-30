# ============================================================
# OpenLane 等价原生流程 (LoongArch native)
# 替代 docker-based OpenLane，用本地编译的工具链
# 用法: openroad -exit openlane_compat.tcl
# ============================================================

set pdk_root "/home/lik/.local/share/pdk"
set pdk "sky130A"
set lib_dir "$pdk_root/$pdk/libs.ref/sky130_fd_sc_hd"
set design_dir [file dirname [info script]]

# ---- 1. 读入 PDK ----
read_liberty $lib_dir/lib/tt_025C_1v80_pnr.lib
read_lef $lib_dir/techlef/sky130_fd_sc_hd.tlef
read_lef $lib_dir/lef/sky130_fd_sc_hd.lef

# ---- 2. 读入综合网表（由 yosys 预先综合） ----
read_verilog $design_dir/counter_synth_fixed.v
link_design "counter"
puts "=== [llength [get_cells -hierarchical]] cells linked ==="

# ---- 3. 布图规划 ----
initialize_floorplan -die_area "0 0 100 100" \
                     -core_area "10 10 90 90" -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2
puts "=== Floorplan done ==="

# ---- 4. 布局 ----
global_placement -skip_io -density 0.6
detailed_placement
puts "=== Placement done ==="

# ---- 5. 时钟树综合（可选，小设计跳过） ----
puts "=== CTS skipped (small design) ==="

# ---- 6. 布线 ----
global_route
detailed_route
puts "=== Routing done ==="

# ---- 7. 输出 ----
write_def $design_dir/results/counter.def
write_verilog $design_dir/results/counter.v
puts "=== RESULTS written to results/ ==="

# 用 magic 转 GDS（需 magic 安装且 DISPLAY 可用）
# exec magic -dnull -noconsole <<< "gds readonly true; def read results/counter.def; gds write results/counter.gds"
puts "=== GDS: run 'magic -dnull -noconsole' to convert DEF to GDS ==="
