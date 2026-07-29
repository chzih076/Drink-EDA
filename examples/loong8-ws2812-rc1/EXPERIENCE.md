# loong8-ws2812-rc1 开发经验总结

> 从 RTL 到 GDSII 完整 EDA 流程的踩坑记录
> 2026-07-29, Drink-EDA Project

---

## 一、项目概览

**目标**：将 WS2812B LED 控制器的 RTL 设计，通过开源 EDA 工具链完成综合、布局布线、GDS 生成，在 LoongArch 平台上跑通完整 RTL→GDSII 流程。

**最终成果**：
- 188 标准单元（50 DFF + 138 组合门）
- 100×100μm die area，sky130A 工艺
- 0 DRC 违例
- 全流程约 70 秒
- 完整晶体管级 GDS（含 poly/diff/metal 所有层）

---

## 二、工具链

| 工具 | 版本 | 用途 | 注意事项 |
|------|------|------|----------|
| Yosys | 0.67+ | 逻辑综合 | 需 ABC SCL hash 补丁（LoongArch） |
| OpenROAD | 26Q3 | 布局布线 | 禁用 GPL 模块（-DENABLE_GPL=OFF） |
| KLayout | 0.30.9 | GDS 查看/转换 | 可用 strm2gds 命令行工具 |
| iverilog | 12.0 | 仿真 | 直接可用 |
| map_synth | 1.0 | ABC 网表重命名 | awk 脚本，给 cell 加 _1 后缀 |

**关键补丁**：
1. ABC SCL hash 修复 → `abc_scl_loongarch_hash_fix.patch`
2. OpenROAD read_lef → `openroad_readlef_update_lib.patch`
3. KLayout `--lefdef-lef-layouts-dir` 选项 → 批量加载 GDS 目录

---

## 三、RTL 设计

WS2812B 控制器是一个**不可编程的硬核**，核心逻辑：

```
50MHz → 800KHz 分频 → 24-bit 移位寄存器 → WS2812B 协议发生器 → GPIO
                                                      ↑
                                              呼吸灯亮度计数器
```

**关键参数**：
- Bit 0: T0H=3 时钟周期 = 60ns, T0L=13 周期 = 260ns
- Bit 1: T1H=9 时钟周期 = 180ns, T1L=7 周期 = 140ns
- 每 bit 总周期：16 × 62.5ns ≈ 1μs
- 24-bit 帧：~24μs
- 呼吸灯渐变：每 1ms 调整亮度，0→255→0 循环

**面积优化**：寄存器文件用 array 比 16 个独立 reg 更高效。

---

## 四、综合（Yosys + ABC）

### 4.1 ABC 崩溃（核心坑）

**现象**：
```
yosys-abc: .../mioUtils.c:751: int abc::Mio_CompareTwo2(): Assertion `0' failed.
ERROR: ABC failed with status 86
```

**根因**：LoongArch 上 ABC 的 SCL（Standard Cell Library）哈希函数极差，导致大量哈希碰撞，线性探测死循环。

**修复**：`abc_scl_loongarch_hash_fix.patch`，修改三处：
1. 哈希函数从 `s_Primes` 改为 `djb2`
2. 线性探测改为确定次数（`Counter < nBins`）
3. 同名 cell 跳过不 assert

### 4.2 Liberty 文件选择

**问题**：`tt_025C_1v80_pnr.lib` 有重复 cell（多个 PVT 角合并），导致 ABC 崩溃。

**解决**：用 `tt_025C_1v80_clean.lib`（gen_pdk_libs 去重后的 PVT 库）。

### 4.3 Cell 命名

ABC 输出的 cell 名不带 `_1` 后缀（如 `nand2`），但 PnR 库用的是 `nand2_1`。

**解决**：`map_synth` 脚本自动添加 `_1` 后缀。

---

## 五、布局布线（OpenROAD）

### 5.1 电源网络（PDN）

**核心经验**：PDN pitch 太密会占满 met1 轨道，导致信号线无路可走。

**对比**：
| PDN pitch | met1 拥塞 | 详细布线违规 |
|-----------|-----------|-------------|
| 5.44μm | 74% | 无法收敛 |
| 10μm | 50% | 19K→38K |
| 15μm | 45% | 15K→33K |

**结论**：对于小设计（<5000 cells），PDN pitch≥10μm 即可，不需要 met4/met5 高层电源。

### 5.2 布局方式

**手动网格布局**：
```tcl
set x 35; set y 35
foreach i [$b getInsts] {
    place_inst -name [$i getName] -location "$x $y"
    set x [expr {$x + 5}]
    if {$x > 550} { set x 35; set y [expr {$y + 6}] }
}
```

这种方法简单可靠，但会造成线长增加（HPWL 约 1M）。对于小设计可接受。

**随机簇布局**：HPWL 2.6M，比网格差，不推荐。

### 5.3 CTS（时钟树综合）

**问题**：CTS 添加的时钟缓冲器需要额外放置空间。网格布局没留空位 → 354 个 cell 无法 legalize。

**解决**：小设计（<500 cells）不需要 CTS。全局布线处理 411 扇出的 clk 即可。

**教训**：CTS 需要提前预留 20-30% 的 placement 空间。

### 5.4 高扇出网

OpenROAD 会警告 `Large net xxx has N pins`。对于 DRT-0120 警告：
- clk: 411 pins → 不需处理（小设计）
- rst_n: 355 pins → 不需处理
- 内部信号 >100 pins → 需要插缓冲树

**经验**：Yosys/ABC 不做 fanout 优化，高扇出网主要在**RTL 架构**层面解决（case 语句展开产生大量译码逻辑）。

### 5.5 one_/zero_ 网

Yosys 为常数 `1'h1` 和 `1'h0` 创建 `one_`/`zero_` net。OpenROAD 的 TritonRoute 会报：
```
Net one_ of signal type POWER is not routable. Move to special nets.
```

**解决**：
```tcl
foreach net [split [$block getNets] " "] {
    set nname [$net getName]
    if {[regexp {one_} $nname] || [regexp {zero_} $nname]} {
        $net setSpecial
    }
}
```

### 5.6 set_voltage_domain

必须在 `pdngen` 之前设置，否则 PDN 会检测到多个电源网（VPWR + one_）而出错。

```tcl
add_global_connection -net VPWR -inst_pattern {.*} -pin_pattern {VPWR} -power
add_global_connection -net VGND -inst_pattern {.*} -pin_pattern {VGND} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND
define_pdn_grid -name "Core" -voltage_domains CORE
```

---

## 六、GDS 合并

### 6.1 方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| strm2gds + LEF | 无依赖 | 只有 metal 抽象，无晶体管 |
| strm2gds + `--lefdef-lef-layouts-dir` | 可加载 GDS | sky130 无 FOREIGN 引用，不生效 |
| Python + KLayout API | 完整几何 | 需要 python3+klayout |
| C 手写 GDS 格式 | 零依赖 | GDS 二进制格式太复杂 |
| Rust 手写 GDS 格式 | 零依赖 | 同样 GDS 格式问题 |

**结论**：最可靠的是 **Python + KLayout API**。KLayout 的 Python 绑定正确处理了 GDS 的二进制格式和 layer 映射。

### 6.2 Cell 名映射

sky130 标准单元的 GDS 文件名格式：`sky130_fd_sc_hd__dfrtp_1.gds`，内部 cell 名同文件名。

DEF 中引用的是短名 `dfrtp_1`。GDS 合并时需要建立映射：

```python
short = tc.name
if short.startswith("sky130_fd_sc_hd__"):
    short = short[17:]  # 注意是 17 不是 18！
```

### 6.3 Layer 复制

KLayout API 复制 shapes 时的 layer 映射：

```python
for li in range(ly.layers()):
    info = ly.get_info(li)        # 返回 LayerInfo(layer, datatype)
    tli = layout.layer(info.layer, info.datatype)  # 保留 datatype
    for s in tc.shapes(li).each():
        layout.cell(ci).shapes(tli).insert(s)
```

**坑**：`layout.layer(info)` 在 KLayout Python API 中不接受 LayerInfo 对象，需要用 `info.layer, info.datatype`。

---

## 七、仿真

iverilog 直接可用。注意：
- `$dumpvars` 输出到当前工作目录（不是 testbench 目录）
- VCD 文件较大（5ms ≈ 14MB）
- `$monitor` 比 `always @(posedge clk) $display` 更简洁

---

## 八、包管理

`.drink` 包格式：
- `metadata.toml` 定义包信息
- `files/` 目录存放文件
- 用 `drink-pkg build <pkg>` 构建

**经验**：
- KLayout 包 269MB，包含 200+ .so 文件
- `strm2gds` 和 `strm2gdstxt` 需要包含在 KLayout 包中
- `drink-eda-tools` 包包含 `def2gds.sh` 等流程脚本

---

## 九、LoongArch 特有坑

1. **ABC SCL hash** → 必须打补丁，否则 ABC 崩溃
2. **GCC LTO bug** → `-DLINK_TIME_OPTIMIZATION=OFF`
3. **CUDD 符号** → ABC 用 `ABC_NAMESPACE=abc` 编译，OpenSTA 需要 `using namespace abc`
4. **KLayout Python API** → 正常工作（KLayout 编译时带了 Python 支持）
5. **magic** → 编译正常，但 PDK 的 mag 视图缺失

---

## 十、经验法则

| 场景 | 建议 |
|------|------|
| <500 cells | 不要 CTS，PDN pitch≥10μm |
| 500-5000 cells | CTS 需预留 20-30% 空间 |
| >5000 cells | 需要分层布局（CPU/内存/外设分区） |
| clk fanout <500 | 全局布线可以处理 |
| rst_n fanout <500 | 同上 |
| 内部信号>100 | RTL 插缓冲或加流水线 |
| die area | 利用率 25-40% 最舒服 |
| PDN | met1+met2 足矣，pitch≥10μm |

---

## 十一、一键流程

```bash
./build.sh          # 全自动（综合→布线→GDS→仿真）
./build.sh gds      # 仅 GDS
./build.sh sim      # 仅仿真
./build.sh clean    # 清理
```

环境变量覆盖：
```bash
PDK=/path  YOSYS_PATH=/path  OPENROAD_PATH=/path  ./build.sh
```
