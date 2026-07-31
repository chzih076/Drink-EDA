# Drink-EDA 🍺

**LoongArch 的芯片设计 EDA 工具链**
**loongArch-Oriented EDA Toolchain for IC Design**

原生适配龙芯 CPU（LoongArch64），以 `.drink` 包格式分发，由 `drink-pkg` 包管理器声明式安装。

> **💾 下载 / Download**：所有 `.drink` 包和 `drink-pkg` 均在右侧「发行版本」中。  
> 下载后把所有文件放在同一目录，按下方说明安装。  
> All `.drink` packages and `drink-pkg` are in the **Releases** section on the right.  
> Download them to the same directory and follow the instructions below.  
> https://gitcode.com/H076lik/Drink-EDA  <--实际仓库地址，包也在里面，github不上传预编译包
> https://gitcode.com/H076lik/Drink-EDA  <-- Actual repository (pre-compiled packages included; not uploaded to GitHub)

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 架构 | `loongarch64`（推荐 3B6000，兼容 3A5000/3C5000+） |
| 内核 | ≥ 5.19.0 |
| glibc | ≥ 2.38 |
| 运行时 | `lib-src-1.0.drink`（libstdc++/libm/libz/Tcl） |
| 存储 | 核心 PDK 约 1.7GB（全 7 变体 + SRAM）；扩展包补齐全部时序 corner（合计约 9GB，可选） |

## 包一览

| 包 | 大小 | 许可证 | 说明 |
|------|------|--------|------|
| `lib-src` | 4.4MB | Apache-2.0 | 公共运行时（libstdc++/libm/libz/libgcc_s/Tcl） |
| `drink-eda-tools` | 0.5MB | Apache-2.0 | Rust 统一工具 `drink`（map-synth/manifests/lvs-models/pdk-libs）+ 流程脚本 |
| `yosys` | 30MB | ISC | Yosys 综合 + ABC（hash 已修） |
| `openroad` | 119MB | BSD-3 | OpenROAD 布局布线（GPL+or-tools+LTO, read_lef已修） |
| `klayout` | 114MB | GPL-3.0 | KLayout 版图工具（strm2gds 含后缀匹配，零 Python） |
| `magic` | 11MB | BSD-3 | Magic VLSI 版图（OpenGL+NULL 双驱动） |
| `netgen` | 606KB | GPL-2.0 | Netgen LVS 版图比对（含 3 处解析器修复） |
| `ngspice` | 7.8MB | BSD-3 | ngspice 电路仿真 |
| `iverilog` | 28KB | GPL-2.0 | Icarus Verilog 仿真 |
| `sky130-pdk`（核心） | 291MB | Apache-2.0 | SkyWater 130nm PDK：7 标准单元变体（hd/hdll/hs/lp/ls/ms/hvl）+ SRAM 宏 + libs.tech |
| `sky130-pdk-extra-hs/ls/ms/lp/misc` | 194–404MB | Apache-2.0 | 扩展包：补齐各变体全部时序 corner（含 ccsnoise 签核库） |
| `drink-pkg` | 8.3MB | GPL-2.0 |来自https://gitcode.com/H076lik/DrinkLinux的包管理器，安全快捷 |
| `gds3d-1.8.drink` | 1.6MB | GPL-2.0 |3D看你的gds版图|
>drink-pkg 是 DrinkLinux 项目自研的 Rust 包管理器，专为 LoongArch64 离线/轻量场景设计。如需了解其实现原理或贡献代码，请访问上游仓库[https://gitcode.com/H076lik/DrinkLinux]。

> 补丁文件位于 [`patches/`](patches/)，详见各补丁头部的说明。

## 状态

> **2026-08-01: 完整 PDK 重建 + LVS 闭环验证通过** ✅
>
> - 完整重建 sky130 PDK：**7 个标准单元变体**（hd/hdll/hs/lp/ls/ms/hvl）
>   全部构建安装（此前 hdll/hs/lp/ls 为空目录的根因已修复），
>   新增 **SRAM 宏库**（1k/2k）
> - **netgen LVS 全流程闭环**：netgen 源码 3 处解析器修复 +
>   Rust 工具 `drink lvs-models` 生成自包含模型库；
>   counter 与 WS2812B 设计均 **Circuits match uniquely**
> - 工具链脚本全面适配新版 PDK（flow/v2spice/extract_lvs/fix_cdl_power）
> - 统一 Rust 工具 `drink`（map-synth / manifests / lvs-models / pdk-libs，零依赖）
>
> 首个参考设计端到端验证（v1.0 起）：
>
> | 阶段 | 工具 | 结果 |
> |------|------|------|
> | RTL | Verilog | WS2812B LED 呼吸灯控制器 |
> | 逻辑综合 | Yosys 0.67+ | 189 cells（50 DFF + 139 combo） |
> | 布局布线 | OpenROAD 26Q3 | 0 DRC 违例，100×100μm |
> | GDS 合并 | KLayout strm2gds | 晶体管级完整版图 |
> | LVS | Netgen（修复版） | Circuits match uniquely |
> | 一键流程 | `./build.sh` | ~70 秒 |
>
> 详见 [examples/loong8-ws2812-rc2/](examples/loong8-ws2812-rc2/)

![GDS3D 3D 芯片渲染](examples/loong8-ws2812-rc2/GDS3D_examples_loong8-ws2812-rc2.png)
*GDS3D 3D 立体渲染（295,692 个三角面）*

![KLayout GDS 版图](examples/loong8-ws2812-rc2/KLayout_examples_loong8-ws2812-rc2.png)
*GDS 完整版图（189 cells，0 DRC）*

![OpenROAD 布局](examples/loong8-ws2812-rc2/openROAD_examples_loong8-ws2812-rc2.png)  
*OpenROAD GUI 布局布线视图*

## 快速开始 / Quick Start

### 安装方式 / Installation

安装后各工具路径：

| 包 / Package | 安装路径 / Install Path |
|----|----------|
| `openroad` | `/usr/local/bin/openroad` |
| `yosys` | `/usr/local/bin/yosys` + `/usr/local/bin/yosys-abc` |
| `klayout` | `/usr/local/bin/klayout` + **`/usr/local/bin/strm2gds`** |
| `drink-eda-tools` | `/usr/local/bin/drink`（统一 CLI）+ `/usr/local/share/drink-eda/scripts/` |
| `sky130-pdk` | `/usr/local/share/pdk/sky130A/`（核心 + 5 扩展包） |
| `lib-src` | `/usr/lib/libstdc++.so.6` etc. |

All tools are in `PATH` after installation. No environment variables needed.

>把drink-pkg下载下来(在发行版本里面)和其他.drink文件放在同一目录下面，演示：
```bash
lik@aosc-lik [ ~ ] ! sudo /home/lik/桌面/drink-pkg install /home/lik/桌面/drink-eda-tools-1.2.drink 
Installed: drink-eda-tools v1.2
  /./
  /usr
  /usr/local
  /usr/local/bin
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
lik@aosc-lik [ ~ ] ! map_synth                   # 兼容 wrapper → drink map-synth
lik@aosc-lik [ ~ ] ! 


# 按需安装
drink-pkg install lib-src 
drink-pkg install yosys 
drink-pkg install openroad 
drink-pkg install sky130-pdk-1.1.drink 
# 可选扩展包：sky130-pdk-extra-{hs,ls,ms,lp,misc}
......

# 一键流程（RTL→GDSII，替代旧 lfl）
sh /usr/local/share/drink-eda/scripts/flow.sh <顶层模块> <rtl.v> [宽um] [高um]

# LVS 验证
sh /usr/local/share/drink-eda/scripts/extract_lvs.sh <设计目录> <顶层> <网表.v> <routed.def>
         
祝你好运！
有问题请提Issuse。
Please open an issue for questions.
```

### 安装 EDA 工具

```bash
drink-pkg install lib-src-1.0.drink
drink-pkg install drink-eda-tools-1.2.drink
drink-pkg install yosys-0.67.0.drink
drink-pkg install openroad-26Q3.drink
drink-pkg install sky130-pdk-1.1.drink
# 可选：扩展包补齐全部时序 corner
drink-pkg install sky130-pdk-extra-hs-1.0.drink
drink-pkg install sky130-pdk-extra-ls-1.0.drink
drink-pkg install sky130-pdk-extra-ms-1.0.drink
drink-pkg install sky130-pdk-extra-lp-1.0.drink
drink-pkg install sky130-pdk-extra-misc-1.0.drink
```

### 运行参考设计

```bash
cd examples/loong8-ws2812-rc2
./build.sh    # 一键 RTL→GDSII
```
>另外GDS3D \
     -p /usr/local/share/gds3d/techfiles/sky130.txt \
     -i XXX.gds

>#_#

## 项目结构

```
Drink-EDA/
├── manifests/    ← 安装清单（TOML）
│   ├── yosys.toml
│   ├── openroad.toml
│   ├── klayout.toml
│   ├── magic.toml
│   ├── netgen.toml
│   ├── ngspice.toml
│   ├── iverilog.toml
│   ├── sky130-pdk.toml
│   ├── lib-src.toml
│   └── drink-eda-tools.toml
├── patches/      ← LoongArch 适配补丁
│   ├── abc_scl_loongarch_hash_fix.patch
│   ├── abc_CMakeLists.patch
│   ├── sta_CMakeLists.patch
│   ├── openroad_cmake.patch
│   ├── openroad_readlef_update_lib.patch
│   ├── klayout_suffix_match.patch
│   ├── allocator-patch.patch
│   ├── cut_CMakeLists.patch
│   ├── netgen_spice_parse_fixes.patch
│   └── netgen_skipnewline_fix.patch
├── scripts/      ← 流程工具（sh，构建机工具 Python）
│   ├── flow.sh           ← 通用 RTL→GDSII 流程
│   ├── def2gds.sh        ← DEF→GDS 转换（sky130 图层映射）
│   ├── extract_lvs.sh    ← LVS 一键流程
│   ├── v2spice.sh        ← Verilog→SPICE 转换
│   ├── fix_cdl_power.sh  ← CDL 电源引脚修复
│   └── convert_libjson.py← .lib.json→.lib（官方转换器包装，构建机；分包见 drink package）
├── examples/     ← 参考设计
│   └── loong8-ws2812-rc2/  ← WS2812B LED 控制器 (v1.0-rc2)
│       ├── build.sh        ← 一键全流程
│       ├── rtl/            ← RTL 源码
│       ├── synth/          ← 综合输出
│       ├── pnr/            ← 版图文件（DEF+GDS）
│       └── log/            ← 运行日志
├── docs/         ← 使用/编译指南
└── tools/        ← 独立工具
    ├── drink/            ← Rust 统一工具（map-synth/manifests/lvs-models/pdk-libs，零依赖）
    ├── gdsmerge/         ← C 版 GDS 合并（开发中）
    └── merge2gds/        ← DEF+GDS 合并（klayout API）
```

## 项目时间线

- **2026-07-27 ~ 2026-07-28** — Drink-EDA 工具链搭建
- **2026-07-29** — 首个简单且完整的参考设计 RTL→GDSII 验证通过
- **2026-08-01** — 完整 PDK 重建（7 变体 + SRAM）+ netgen LVS 闭环 + Rust 统一工具 drink；发布 v1.1（核心+扩展 6 包方案）

## 许可

仓库源码：Apache 2.0  
二进制包：遵循各上游项目许可证
