# Drink-EDA 🍺

**LoongArch 芯片设计 EDA 工具链包管理器**

为 DrinkLinux 发行版打造，原生适配龙芯 CPU（LoongArch64），以 `.drink` 包格式分发，由 `drink-pkg` 包管理器声明式安装。

---

## 包一览

| 包 | 大小 | 许可证 | 说明 |
|------|------|--------|------|
| `lib-src` | 1.5MB | Apache-2.0 | 公共运行时（libstdc++/libm/libz/Tcl） |
| `drink-eda-tools` | 5KB | Apache-2.0 | `lfl` 流程控制器 + `map_synth` 网表重命名 |
| `yosys` | 30MB | ISC | Yosys 综合 + ABC（hash 已修） |
| `openroad` | 70MB | BSD-3 | OpenROAD 布局布线（read_lef 已修） |
| `klayout` | 269MB | GPL-3.0 | KLayout 版图编辑（standalone 无 Python） |
| `magic` | 6.6MB | BSD-3 | Magic VLSI 版图 |
| `ngspice` | 7.8MB | BSD-3 | ngspice 电路仿真 |
| `iverilog` | 28KB | GPL-2.0 | Icarus Verilog 仿真 |
| `sky130-pdk` | 78MB | Apache-2.0 | SkyWater 130nm PDK（HD/MS/HVL/IO/PR） |

## 状态

> **2026-07-29: 完整 RTL→GDSII 流程验证通过** ✅
>
> 首个参考设计已完成端到端验证：
>
> | 阶段 | 工具 | 结果 |
> |------|------|------|
> | RTL | Verilog | WS2812B LED 呼吸灯控制器 |
> | 逻辑综合 | Yosys 0.67+ | 188 cells（50 DFF + 138 combo） |
> | 布局布线 | OpenROAD 26Q3 | 0 DRC 违例，100×100μm |
> | GDS 合并 | KLayout + Python | 晶体管级完整版图 |
> | 一键流程 | `./build.sh` | ~70 秒 |
>
> 详见 [examples/loong8-ws2812-rc1/](examples/loong8-ws2812-rc1/)

## 快速开始

### 基础容器（25MB）

```bash
docker import rootfs-eda.tar.gz drinklinux-eda:latest
docker run -it --rm drinklinux-eda:latest /bin/sh -l
```

### 安装 EDA 工具

```bash
drink-pkg install lib-src-1.0.drink
drink-pkg install drink-eda-tools-1.0.drink
drink-pkg install yosys-0.67.0.drink
drink-pkg install openroad-26Q3.drink
drink-pkg install sky130-pdk-1.0.drink
```

### 运行参考设计

```bash
cd /opt/Drink-EDA/examples/loong8-ws2812-rc1
./build.sh    # 一键 RTL→GDSII
```

## 项目结构

```
Drink-EDA/
├── manifests/    ← 安装清单（TOML）
│   ├── yosys.toml
│   ├── openroad.toml
│   ├── klayout.toml
│   ├── magic.toml
│   ├── ngspice.toml
│   ├── iverilog.toml
│   ├── sky130-pdk.toml
│   ├── lib-src.toml
│   └── drink-eda-tools.toml
├── patches/      ← LoongArch 适配补丁
│   ├── abc_scl_loongarch_hash_fix.patch
│   ├── openroad_readlef_update_lib.patch
│   ├── gen_pdk_libs.patch
│   └── ...
├── scripts/      ← 流程工具（纯 sh）
│   ├── lfl              ← 流程控制器
│   ├── map_synth        ← 网表重命名
│   ├── gen_pdk_libs     ← PDK 维护
│   ├── gen_lib          ← Liberty 生成
│   ├── openlane-native  ← 一键 RTL→PnR
│   └── gen_manifests.py ← 构建机专用
├── examples/     ← 参考设计
│   └── loong8-ws2812-rc1/  ← WS2812B LED 控制器
│       ├── build.sh        ← 一键全流程
│       ├── rtl/            ← RTL 源码
│       ├── synth/          ← 综合输出
│       ├── pnr/            ← 版图文件（DEF+GDS）
│       └── log/            ← 运行日志
├── docs/         ← 编译指南
└── tools/        ← 独立工具
    ├── gdsmerge/           ← C 版 GDS 合并（开发中）
    └── gdsmerge-rs/        ← Rust 版 GDS 合并（开发中）
```

## 项目时间线

- **2026-06 底 ~ 2026-07-26** — loong8 16-bit MCU 自研（ISA + RTL + FPGA）
- **2026-07-27 ~ 2026-07-28** — Drink-EDA 工具链搭建
- **2026-07-29** — 首个参考设计 RTL→GDSII 验证通过

## 许可

仓库源码：Apache 2.0  
二进制包：遵循各上游项目许可证
