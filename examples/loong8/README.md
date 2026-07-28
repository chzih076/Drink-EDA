# loong8 — 16-bit MCU ASIC 版图验证

## 简介

loong8 是一颗自研 16-bit 自定义 ISA MCU，开发周期约 4 周。

- **自定义 16-bit ISA**：14 类指令（ALU/ALUI/LD/ST/Branch/JMP/JAL/CSR/MOVE/PAGE/STX/LDX/BL/SCMP）
- **单周期**：取指+译码+执行全在同一周期完成，无流水线
- **存储**：ROM 128B + SRAM 128B（ASIC 裁剪版）
- **外设**：UART 9600-8-N-1
- **寄存器**：16 × 8-bit（R0 硬连零）+ CSR
- **FPGA 验证**：达芬奇 Pro xc7a200t，Vivado 2025.2 JTAG 烧录

## EDA 流程验证

使用 Drink-EDA 工具链（lfl 流程控制器），在两个晚上内完成了从 RTL 到 ASIC 版图的完整流程。

### 流程

```bash
lfl config.yaml
```

等价于：

```bash
# 1. 综合（yosys + ABC，hash 已修）
yosys -p "read_verilog *.v; synth -top loong8_asic; abc -liberty ...; write_verilog synth.v"

# 2. 网表重命名（map_synth，自动加 _1 后缀）
map_synth synth.v pnr.v

# 3. 布局布线（OpenROAD，read_lef 已修）
openroad ...  # → loong8_asic.def
```

### 结果

| 指标 | 值 |
|------|------|
| 标准单元 | **6527 cells** |
| 互连线 | **6535 nets** |
| Die area | 400 × 400 µm |
| 工艺 | SkyWater 130nm (sky130A) |
| 综合库 | tt_025C_1v80 (典型工艺角) |

### 日志

- `synth.log` — yosys 综合日志
- `pnr.log` — OpenROAD PnR 日志
- `loong8_asic.def` — 最终版图（14520 行）

## 文件

| 文件 | 说明 |
|------|------|
| `loong8_asic.v` | ASIC 顶层 |
| `cpu_core.v` | CPU 核心（单周期） |
| `uart_tx.v` / `uart_rx.v` | UART 串口 |
| `defs.vh` | ISA 常量定义 |
| `firmware.hex` | 固件（ROM 初始化） |
| `config.yaml` | lfl 配置文件 |
| `loong8_asic.def` | 版图输出 |
| `loong8_asic_synth_pnr.v` | 重命名后网表 |

## 许可

Apache 2.0
