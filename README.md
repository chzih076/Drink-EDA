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

### 运行 RTL→GDSII 流程

```bash
# 创建设计
cat > counter.v << 'EOF'
module counter(input clk, input rst_n, output reg [7:0] count);
  always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0; else count <= count + 1;
endmodule
EOF

# 创建配置文件
cat > config.yaml << 'EOF'
DESIGN_NAME: "counter"
VERILOG_FILES: "counter.v"
TOP_MODULE: "counter"
CLOCK_PORT: "clk"
CLOCK_PERIOD: 10
EOF

# 一键流程
lfl config.yaml
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
├── scripts/      ← 流程工具（纯 sh，零 Python）
│   ├── lfl              ← 流程控制器
│   ├── map_synth        ← 网表重命名
│   ├── gen_pdk_libs     ← PDK 维护（sh + awk）
│   ├── gen_lib          ← Liberty 生成
│   ├── openlane-native  ← 一键 RTL→PnR
│   └── gen_manifests.py ← 构建机专用（不进容器）
├── docs/         ← 编译指南
└── patches/      ← 补丁文件
```

## 容器

```bash
docker build -f Dockerfile -t drinklinux-eda .
docker run -it --rm drinklinux-eda:latest
```

## 许可

仓库源码：Apache 2.0  
二进制包：遵循各上游项目许可证
