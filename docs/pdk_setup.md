# sky130 PDK 龙芯安装指南

## 需求

- open_pdks 1.0.605+
- magic 8.3+（已编译）
- skywater-pdk 源文件（从 gitee 镜像克隆）
- 1TB 硬盘（用于存放源文件，可选）

## 源文件获取

由于 GitHub 在中国访问不稳定，使用镜像：

```bash
# 主仓库
git clone https://gitcode.com/google/skywater-pdk.git

# 标准单元库
git clone https://gitee.com/mirrors_google/skywater-pdk-libs-sky130_fd_sc_hd.git
git clone https://gitee.com/mirrors_google/skywater-pdk-libs-sky130_fd_pr.git
git clone https://gitee.com/mirrors_google/skywater-pdk-libs-sky130_fd_io.git
# ... 其他库

# KLayout 技术文件
git clone https://gitee.com/deanyou/sky130_klayout_pdk.git
```

## 安装 open_pdks

```bash
# 下载
# 从 https://github.com/fossi-foundation/open-pdks 获取

# 解压
unzip open-pdks-main.zip
cd open-pdks-main

# 配置
./configure \
  --enable-sky130-pdk=/path/to/skywater-pdk \
  --enable-io-sky130=/path/to/sky130_fd_io/latest \
  --enable-primitive-sky130=/path/to/sky130_fd_pr/latest \
  --prefix=$HOME/.local

# 确保 sources/ 目录有各库的链接
mkdir -p sources
ln -sf /path/to/sky130_fd_sc_hd/latest sources/sky130_fd_sc_hd
ln -sf /path/to/sky130_fd_sc_hs/latest sources/sky130_fd_sc_hs
# ... 等

# 编译（用 xvfb-run 防止 magic 弹窗）
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
xvfb-run -a make -j$(nproc)
xvfb-run -a make install
```

## 网表重命名工具

合成后用 ABC 生成的网表使用短 cell 名（`and2`），需要重命名为
PnR LIB 格式（`and2_1`）：

```bash
# 安装
cp map_synth ~/.local/bin/

# 使用
map_synth synth.v synth_pnr.v
```

## 一键流程脚本

```bash
# 安装
cp lfl ~/.local/bin/

# 使用（在 design 目录下）
lfl config.yaml
```

## Liberty 维护

```bash
# 安装
cp gen_pdk_libs ~/.local/bin/

# 展开 PnR LIB
gen_pdk_libs expand

# 恢复原始 LIB
gen_pdk_libs copy

# 同时做
gen_pdk_libs both
```

> **注意**: `gen_pdk_libs` v1 在展开 LIB 时对每个原始 cell 独立展开，
> 如果用 `all_seen` 全局去重可避免同名 cell 重复（如 `buf_1` 出现 9 次）。
> 已修复：在循环外用 `all_seen = set()` 追踪已生成的 cell。

## ABC SCL Hash 修复（LoongArch 必须）

LoongArch 上 yosys 内嵌的 ABC 在加载 >200 cell 的 Liberty 文件时，
因 `sclLibUtil.c:Abc_SclHashString` 哈希函数极差导致大量碰撞，
且 `Abc_SclHashLookup` 的线性探测 `for (i = hash; i < nBins; i = (i+1)%nBins)`
是死循环（条件永远为真）。修复三处：

```diff
// 1. 替换哈希函数为 djb2
-    Key += s_Primes[i%10]*pName[i]*pName[i];
+    hash = ((hash << 5) + hash) + c;

// 2. 修复线性探测为确定次数
-    for ( i = hash; i < nBins; i = (i+1)%nBins )
+    for ( Counter = 0; Counter < nBins; Counter++ )
+        i = (hash + Counter) % nBins;

// 3. 跳过同名 cell（不 assert）
-    assert(*pPlace == -1);
+    if (*pPlace != -1) continue;
```

**重编 yosys**:
```bash
git clone https://github.com/YosysHQ/yosys.git
cd yosys
git submodule update --init abc
# 应用上述三处补丁到 abc/src/map/scl/sclLibUtil.c
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DYOSYS_DISABLE_THREADS=ON \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_CXX_FLAGS="-Wno-error=unused-parameter"
make -j$(nproc)
make install DESTDIR=~/.local
```

> **注意**: yosys 0.67+ 移除了 `-y`(Python script) 支持，librelane 依赖此功能。
> 如果用 librelane 流程，需保留系统 yosys 0.66 版本。

## 配置修复

PDK 安装后需修 `config.tcl` 防止 `DEFAULT_CORNER` 被截断：

```tcl
# 在 libs.tech/librelane/config.tcl 末尾加：
set ::env(LIB) [dict create]
dict set ::env(LIB) "*_tt_025C_1v80" "$::env(PDK_ROOT)/..."
dict set ::env(LIB_SYNTH) "$::env(PDK_ROOT)/..."
```

## OpenROAD PnR 流程（完整 RTL→GDSII）

### 已知问题

1. **LEF site 未注册**: 先读 techlef 再读 macro lef 时，因同名库已存在，
   `read_lef` 静默跳过 → `initialize_floorplan -site unithd` 报 IFP-0018。
   **修复**: OpenROAD `src/OpenRoad.cc` 中改调 `lef_reader.updateLib()`。

2. **routing track 缺失**: `global_route` 报 `GRT-0701 Missing track structure`。
   **修复**: `initialize_floorplan` 后加 `make_tracks`（无参数自动生成）。

3. **Pin 无几何信息**: `global_route` 报 `GRT-0042 Pin clk no valid routing layer`。
   **修复**: 布线前用 `place_pins -hor_layers met1 -ver_layers met2`。

### 完整示例脚本

```tcl
read_liberty $pdk/libs.ref/sky130_fd_sc_hd/lib/tt_025C_1v80_pnr.lib
read_lef $pdk/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef
read_lef $pdk/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
read_verilog design_synth.v
link_design "top"

initialize_floorplan -die_area "0 0 100 100" \
                     -core_area "10 10 90 90" -site unithd
make_tracks
place_pins -hor_layers met1 -ver_layers met2

# 放置实例（简化：全部堆在左下角，detailed_placement 会 legalize）
set block [ord::get_db_block]
foreach inst [$block getInsts] {
    place_inst -name [$inst getName] -location "12 12"
}
detailed_placement
global_route
detailed_route
write_def output.def
write_verilog output.v
```
