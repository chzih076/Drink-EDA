# Drink-EDA 用户指南

## 目录

1. [系统要求](#1-系统要求)
2. [安装](#2-安装)
3. [工具链概览](#3-工具链概览)
4. [快速开始：WS2812B LED 控制器](#4-快速开始ws2812b-led-控制器)
5. [分步教程](#5-分步教程)
6. [故障排除](#6-故障排除)
7. [附录](#7-附录)

---

## 1. 系统要求

### 硬件

| 项目 | 要求 |
|------|------|
| 架构 | **LoongArch64**（龙芯 3A5000/3B6000/3C5000+） |
| 内存 | ≥ 4GB（推荐 8GB） |
| 存储 | ≥ 2GB（工具链）+ 2GB（PDK） |

### 软件

| 项目 | 要求 |
|------|------|
| 内核 | Linux ≥ 5.19.0 |
| glibc | ≥ 2.38 |
| libstdc++ | ≥ GCC 13 (随系统自带) |
| Python | ❌ **不需要**（所有工具零 Python 依赖） |

### 发行版

已在以下系统验证：
- **AOSC OS 13.3+**（开发用）
- 其他 LoongArch Linux 发行版理论上兼容

---

## 2. 安装

### 2.1 安装 drink-pkg

从 [Releases 页面](https://gitcode.com/H076lik/Drink-EDA/releases) 下载 `drink-pkg` 和所有 `.drink` 包：

```bash
# 给 drink-pkg 执行权限
chmod +x drink-pkg

# 验证
./drink-pkg --help
```

### 2.2 安装运行时库

```bash
sudo ./drink-pkg install lib-src-1.0.drink
```

### 2.3 安装 EDA 工具

按依赖顺序安装：

```bash
# 1. 基础工具包（流程脚本）
sudo ./drink-pkg install drink-eda-tools-1.0.drink

# 2. Yosys 综合工具
sudo ./drink-pkg install yosys-0.67.0.drink

# 3. OpenROAD 布局布线（含 or-tools 9.15）
sudo ./drink-pkg install openroad-26Q3.drink

# 4. KLayout GDS 工具（strm2gds 已内嵌后缀匹配）
sudo ./drink-pkg install klayout-0.30.9.drink

# 5. PDK
sudo ./drink-pkg install sky130-pdk-1.0.drink
```

### 2.4 验证安装

```bash
# 验证各工具
yosys -V
openroad -version
strm2gds --help

# 验证 PDK
ls /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/
```

### 2.5 安装路径一览

| 组件 | 路径 |
|------|------|
| openroad | `/usr/local/bin/openroad` |
| yosys / yosys-abc | `/usr/local/bin/yosys` |
| klayout | `/usr/local/bin/klayout` |
| strm2gds | `/usr/local/bin/strm2gds` |
| map_synth | `/usr/local/bin/map_synth` |
| lfl | `/usr/local/bin/lfl` |
| PDK | `/usr/local/share/pdk/sky130A/` |
| 运行时库 | `/usr/local/lib/` |
| KLayout 插件 | `/usr/local/lib/klayout/db_plugins/` |

---

## 3. 工具链概览

### 3.1 设计流程

```
  Verilog RTL
      │
      ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐
│  Yosys      │────→│  OpenROAD    │────→│  strm2gds   │────→│  GDSII   │
│  RTL 综合   │     │  布局布线    │     │  GDS 转换   │     │  流片    │
│  + ABC 优化 │     │  GPL+DRT    │     │  后缀匹配   │     │  格式    │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────┘
      │                    │                      │
  188 cells             0 DRC                324 KB
```

### 3.2 Yosys（综合）

Yosys 将 Verilog RTL 代码综合为门级网表：

```
read_verilog design.v
synth -top top_module -flatten
dfflibmap -liberty <clean.lib>
abc -liberty <clean.lib>
opt
write_verilog synth_out.v
```

关键点：
- 使用 `tt_025C_1v80_clean.lib`（去除时序信息的 liberty 文件，适合综合）
- ABC 做逻辑优化和多级工艺映射
- 输出通用单元（如 `$_AND_`），需通过 `map_synth` 映射到 PDK 单元

### 3.3 OpenROAD（布局布线）

OpenROAD 将综合网表转为物理版图：

| 步骤 | 命令 | 模块 | 说明 |
|------|------|------|------|
| 读库 | `read_liberty` | sta | 时序库 |
| 读 LEF | `read_lef` | odb | 工艺/单元物理信息 |
| 读网表 | `read_verilog` | odb | 门级网表 |
| 布局规划 | `initialize_floorplan` | ifp | 芯片尺寸、核心区域 |
| 引脚摆放 | `place_pins` | ppl | IO 引脚自动摆放 |
| **全局布局** | **`global_placement`** | **gpl** | **RePlAce + or-tools 9.15** |
| 详细布局 | `detailed_placement` | dpl | 合法化+优化 |
| 电源网络 | `pdngen` | pdn | 自动生成电源条纹 |
| **全局布线** | **`global_route`** | **grt** | **FastRoute** |
| **详细布线** | **`detailed_route`** | **drt** | **TritonRoute** |

### 3.4 strm2gds（GDS 转换）

strm2gds 将布线后的 DEF 文件转换为 GDSII 格式：

```bash
strm2gds \
  --lefdef-lefs <techlef>,<macrolef> \
  --lefdef-lef-layouts-dir <gds_lib_dir> \
  --lefdef-macro-resolution-mode 2 \
  --lefdef-map <layer_map> \
  design.def design.gds
```

**后缀匹配**：DEF 中的 `and3_1` 自动匹配 GDS 库中 `sky130_fd_sc_hd__and3_1`，无需 LEF FOREIGN 声明。

**图层映射**：使用 `--lefdef-map sky130A.map` 将布线层映射到正确的 sky130 GDS 层号（met1→68/20, met2→69/20）。

---

## 4. 快速开始：WS2812B LED 控制器

一份完整的参考设计位于 `examples/loong8-ws2812-rc2/`。

### 4.1 一键运行

```bash
cd examples/loong8-ws2812-rc2
./build.sh                       # 一键全流程
```

### 4.2 分步执行

```bash
./build.sh clean                 # 清理
./build.sh synth                 # 仅综合
./build.sh pnr                   # 仅布局布线
./build.sh gds                   # 仅 GDS 生成
./build.sh verify                # 验证
```

### 4.3 指定工具路径

```bash
OPENROAD_PATH=/opt/openroad ./build.sh
```

工具搜索顺序：`$TOOL_PATH` 环境变量 → `$PATH` → `/usr/local/bin/<tool>`

### 4.4 使用通用流程脚本

对于自己的设计，可以直接用通用脚本：

```bash
# 用法: scripts/flow.sh <顶层模块> <rtl文件> [宽um] [高um]
scripts/flow.sh top rtl/top.v 100 100
```

它会自动完成综合→布局布线→GDS 全流程，结果输出在 `synth/`、`pnr/`、`log/` 目录。

```bash
# 3D 查看（需 GDS3D）
GDS3D -p /usr/local/share/gds3d/techfiles/sky130.txt -i pnr/ws2812b_ctrl.gds

# 2D 查看（需 OpenROAD GUI）
openroad -gui
read_lef /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef
read_lef /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
read_def pnr/ws2812_routed.def
fit
```

---

## 5. 分步教程

### 5.1 从头开始：创建自己的设计

```bash
# 1. 创建项目目录
mkdir my_design && cd my_design
mkdir rtl synth pnr log

# 2. 编写 RTL（Verilog）
cat > rtl/top.v << 'EOF'
module top(input clk, input rst_n, output reg led);
  reg [23:0] cnt;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) cnt <= 0;
    else cnt <= cnt + 1;
  assign led = &cnt;
endmodule
EOF

# 3. 综合
yosys -l log/synth.log -p "
  read_verilog rtl/top.v;
  synth -top top -flatten;
  dfflibmap -liberty /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/tt_025C_1v80_clean.lib;
  abc -liberty /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/tt_025C_1v80_clean.lib;
  opt;
  write_verilog synth/top_synth.v
"

# 4. 网表映射
map_synth synth/top_synth.v synth/top_pnr.v

# 5. 布局布线
openroad -no_init -no_splash -exit << TCL
  set PDK /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd
  read_liberty \$PDK/lib/tt_025C_1v80_pnr.lib
  read_lef \$PDK/techlef/sky130_fd_sc_hd.tlef
  read_lef \$PDK/lef/sky130_fd_sc_hd.lef
  read_verilog synth/top_pnr.v
  link_design "top"
  initialize_floorplan -die_area "0 0 50 50" -core_area "5 5 45 45" -site unithd
  make_tracks
  place_pins -hor_layers met1 -ver_layers met2
  global_placement -skip_io -density 0.6
  detailed_placement
  add_global_connection -net VCC -inst_pattern {.*} -pin_pattern {VCC} -power
  add_global_connection -net VSS -inst_pattern {.*} -pin_pattern {VSS} -ground
  set_voltage_domain -name CORE -power VCC -ground VSS
  define_pdn_grid -name "Core" -voltage_domains CORE
  add_pdn_stripe -grid "Core" -layer met1 -width 0.48 -pitch 10 -offset 0 -followpins
  add_pdn_stripe -grid "Core" -layer met2 -width 0.48 -pitch 10 -offset 5
  add_pdn_connect -grid "Core" -layers {met1 met2}
  pdngen
  set block [ord::get_db_block]
  global_route -congestion_iterations 100
  detailed_route -output_drc pnr/top_drc.rpt
  write_def pnr/top_routed.def
TCL

# 6. GDS 转换
strm2gds \
  --lefdef-lefs /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef,/usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef \
  --lefdef-lef-layouts-dir /usr/local/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds \
  --lefdef-macro-resolution-mode 2 \
  --lefdef-map /usr/local/share/pdk/sky130A/libs.tech/klayout/tech/sky130A.map \
  pnr/top_routed.def pnr/top.gds

# 7. 验证
echo "DRC: $(cat pnr/top_drc.rpt)"
echo "GDS: $(ls -lh pnr/top.gds)"
```

### 5.2 理解关键参数

#### 芯片尺寸

```tcl
initialize_floorplan -die_area "0 0 100 100" -core_area "10 10 90 90" -site unithd
```

- `die_area`：芯片物理尺寸（um）
- `core_area`：核心区域（放置标准单元）
- `site unithd`：sky130 标准单元行高

#### 密度设置

```tcl
global_placement -skip_io -density 0.6
```

- `density`：目标利用率（0.6 = 60%），越低布线越容易但芯片越大

#### 布线迭代

```tcl
global_route -congestion_iterations 100
detailed_route -output_drc pnr/design_drc.rpt
```

- `global_route` 迭代次数越多拥塞优化越好
- `output_drc` 报告 DRC 违例数量，0 为通过

### 5.3 时序约束

```tcl
create_clock -name clk -period 20 [get_ports clk]
set_propagated_clock [all_clocks]
report_timing -max_paths 5 -digits 3
```

- `-period 20`：时钟周期 20ns（50MHz）
- `report_timing` 显示建立时间余量（slack）

---

## 6. 故障排除

### 6.1 找不到工具

```bash
# 确认已安装
ls /usr/local/bin/openroad
ls /usr/local/bin/strm2gds

# 或在 PATH 中查找
which openroad
which strm2gds
```

### 6.2 strm2gds 报 "cannot open shared object file"

```bash
# 检查 RPATH
readelf -d /usr/local/bin/strm2gds | grep rpath
# 应为: /usr/lib:/usr/local/lib:/usr/local/lib/klayout/db_plugins

# 检查插件是否存在
ls /usr/local/lib/klayout/db_plugins/libgds2.so
```

### 6.3 OpenROAD GUI 不显示

```bash
QT_QPA_PLATFORM=xcb QT_PLUGIN_PATH=/usr/lib/qt5/plugins openroad -gui
```

### 6.4 布局布线 DRC 违例

常见原因：
- 密度过高（降低 `-density` 参数）
- PDN 条纹阻挡布线（调整 `add_pdn_stripe` 参数）
- 特殊线网未标记（`zero_/one_` 网络需要 `setSpecial`）

### 6.5 GDS 不包含标准单元

确认 strm2gds 使用了：
- `--lefdef-lef-layouts-dir` 指向标准单元 GDS 目录
- `--lefdef-macro-resolution-mode 2`（强制外部解析）
- strm2gds 版本 ≥ 2026-07-30（含后缀匹配补丁）

---

## 7. 附录

### 7.1 sky130 GDS 层号

| GDS 层/数 | 名称 | 用途 |
|-----------|------|------|
| 64/20, 64/16 | DIFF | 扩散（晶体管有源区） |
| 65/20 | POLY | 多晶硅栅 |
| 66/20, 66/44 | mcon | 接触孔 |
| 67/20, 67/16, 67/44 | li1 | 本地互连 |
| **68/20, 68/16** | **met1** | **金属 1（主要布线层）** |
| **69/20, 69/16** | **met2** | **金属 2（次要布线层）** |
| 70/20, 70/16 | met3 | 金属 3 |
| 71/20, 71/16 | met4 | 金属 4 |
| 72/20, 72/16 | met5 | 金属 5（顶层） |
| 122/16 | pwell | P 阱 |
| 235/4 | DIEAREA | 芯片轮廓 |

### 7.2 包版本对照

| 包 | 版本 | 大小 |
|----|------|------|
| lib-src | 1.0 | 4.4 MB |
| yosys | 0.67.0 | 30 MB |
| openroad | 26Q3 | 119 MB |
| klayout | 0.30.9 | 114 MB |
| sky130-pdk | 1.0 | 74 MB |
| drink-eda-tools | 1.0 | 6 KB |
| iverilog | 12.0 | 28 KB |
| magic | 8.3 | 6.5 MB |
| ngspice | 46 | 7.8 MB |
| gds3d | 1.8 | 1.6 MB |

### 7.3 许可

- 仓库内容：Apache 2.0
- 二进制包：遵循各上游项目许可证（BSD-3 / GPL-2.0 / GPL-3.0 / ISC / Apache-2.0）
