# Drink-EDA v1.1 — LoongArch 原生 EDA 工具链 🍺

## 内容

完整 RTL→GDSII + LVS 闭环的 LoongArch64 工具链包：

### EDA 工具包

- `yosys-0.67.0.drink` — Yosys 综合 + ABC（LoongArch hash 修复）
- `openroad-26Q3.drink` — OpenROAD 布局布线（read_lef 修复，GPL+or-tools+LTO）
- `klayout-0.30.9.drink` — KLayout 版图编辑（standalone，无 Python/Ruby，strm2gds 内嵌后缀匹配）
- `magic-8.3.drink` — Magic VLSI 版图工具（OpenGL+NULL 双驱动）
- `ngspice-46.drink` — ngspice 电路仿真
- `iverilog-12.0.drink` — Icarus Verilog 仿真
- `gds3d-1.8.drink` — 3D 查看你的 GDS 版图
- `netgen-1.5.323.drink` — LVS（Layout vs. Schematic）比对工具
  > **含三处解析器修复**：顶层自引用误报、`.model` 卡跳过、续行注释处理，
  > 可正确解析 skywater PDK spice 格式（counter / WS2812B 均验证
  > Circuits match uniquely）

### 运行时工具

- `lib-src-1.0.drink` — 公共运行时库（libstdc++/libm/libz/libgcc_s/Tcl）
- `drink-eda-tools-1.2.drink` — Rust 统一工具 `drink`
  （map-synth / manifests / lvs-models / pdk-libs，零依赖）+ 全套流程脚本
  （flow.sh / extract_lvs.sh / v2spice.sh / fix_cdl_power.sh / def2gds.sh）

### PDK（sky130A，6 包方案）

- `sky130-pdk-1.1.drink`（核心，~1.7GB 解压）— **7 个标准单元变体**
  （hd / hdll / hs / lp / ls / ms / hvl）全部 gds/lef/cdl/spice/verilog/mag/maglef/techlef
  + tt/ff/ss 常用 corner + **SRAM 宏库**（1k/2k）+ libs.tech 全套
- `sky130-pdk-extra-{hs,ls,ms,lp,misc}-1.0.drink`（扩展，可选）— 补齐
  各变体**全部时序 corner**（含 ccsnoise 签核库）；核心 + 扩展 = 完整 PDK（~9GB）

> TT/SS/FF 工艺角说明：
>
> | 角 | 含义 | 电压 | 温度 |
> |----|------|------|------|
> | tt | Typical-Typical（典型） | 1.80V | 25°C |
> | ss | Slow-Slow（慢） | 1.60V | -40°C |
> | ff | Fast-Fast（快） | 1.95V | 100°C |
>
> 核心包已含常用角，可完成综合→布局→LVS 全流程；签收（signoff）用
> 扩展包的全角（含 ccsnoise）。各速度档库：
>
> | 库 | 速度 | 密度 | 场景 |
> |----|------|------|------|
> | HD | 标准 | 高 | 默认主力 |
> | HDLL | 标准 | 更高（低功耗） | 高密度场景 |
> | HS | 高速 | 低 | 高性能场景 |
> | MS | 中速 | 中 | 需要更高性能时 |
> | LP/LS | 低功耗/低速 | - | 低功耗场景 |

### 安装方式

```bash
快速开始——把 drink-pkg 和其他 .drink 文件放在同一目录，演示：

lik@aosc-lik [ ~ ] ! sudo drink-pkg install /path/to/drink-eda-tools-1.2.drink
Installed: drink-eda-tools v1.2
  /usr/local/bin/drink
  /usr/local/bin/gen_lvs_models
  /usr/local/share/drink-eda/scripts/{flow.sh,extract_lvs.sh,v2spice.sh,...}
lik@aosc-lik [ ~ ] $ drink help
drink — Drink-EDA 统一工具
  map-synth <in.v> <out.v>   合成网表 cell 名映射
  manifests                   生成工具安装清单
  lvs-models                  生成 LVS 模型库
  pdk-libs <copy|expand|all>  PDK Liberty 维护
  package [--pdk-root <sky130A>] [--out <dir>]  生成 PDK 分包目录树

# 按依赖顺序安装
sudo drink-pkg install lib-src-1.0.drink
sudo drink-pkg install drink-eda-tools-1.2.drink
sudo drink-pkg install yosys-0.67.0.drink
sudo drink-pkg install openroad-26Q3.drink
sudo drink-pkg install klayout-0.30.9.drink
sudo drink-pkg install magic-8.3.drink
sudo drink-pkg install netgen-1.5.323.drink
sudo drink-pkg install sky130-pdk-1.1.drink
# 可选：扩展包补齐全部时序 corner
sudo drink-pkg install sky130-pdk-extra-hs-1.0.drink
sudo drink-pkg install sky130-pdk-extra-ls-1.0.drink
sudo drink-pkg install sky130-pdk-extra-ms-1.0.drink
sudo drink-pkg install sky130-pdk-extra-lp-1.0.drink
sudo drink-pkg install sky130-pdk-extra-misc-1.0.drink

# 一键流程（RTL→GDSII）
sh /usr/local/share/drink-eda/scripts/flow.sh <顶层模块> <rtl.v> [宽um] [高um]

# LVS 验证
sh /usr/local/share/drink-eda/scripts/extract_lvs.sh <设计目录> <顶层> <网表.v> <routed.def>
```

> 升级提示：drink-pkg 不清理目标目录旧文件，干净升级请先
> `sudo rm -rf /usr/local/share/pdk/sky130A`。

### 架构

- 纯 LoongArch64 原生编译，零 x86 模拟
- 工具链运行时零 Python：流程脚本 bash + awk + Tcl；构建/打包工具 Rust + Python（构建机专用）
- ABC SCL hash 已修，支持 465 cell Liberty 文件
- OpenROAD read_lef 已修，支持多 LEF 文件加载
- Rust 统一工具 `drink`（零第三方依赖，单二进制）

### 许可

- 仓库源码：Apache 2.0
- 各二进制包遵循上游项目许可证
