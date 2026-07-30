# loong8-ws2812-rc2 开发经验总结

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
| OpenROAD | 26Q3 | 布局布线 | GPL+or-tools+LTO（全功能） |
| KLayout | 0.30.9 | GDS 查看/转换 | strm2gds 已内嵌后缀匹配 |
| iverilog | 12.0 | 仿真 | 直接可用 |
| map_synth | 1.0 | ABC 网表重命名 | awk 脚本，给 cell 加 _1 后缀 |

**关键补丁**：
1. ABC SCL hash 修复 → `abc_scl_loongarch_hash_fix.patch`
2. OpenROAD read_lef → `openroad_readlef_update_lib.patch`
3. KLayout 后缀匹配 → `klayout_suffix_match.patch`（strm2gds 直接链接所有格式插件）

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

**手动网格布局（早期版本）**：
```tcl
set x 35; set y 35
foreach i [$b getInsts] {
    place_inst -name [$i getName] -location "$x $y"
    set x [expr {$x + 5}]
    if {$x > 550} { set x 35; set y [expr {$y + 6}] }
}
```
这种方法简单但线长不可控。

**自动布局（当前方案）**：改用 RePlAce 引擎（or-tools 9.15 后端）：
```tcl
global_placement -skip_io -density 0.6
detailed_placement
```
375 轮迭代后 HPWL 2457um，平均位移仅 2.8um，0 DRC。gpl 模块通过 `-DHAS_GPL=1` 启用。

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

### 6.1 方案演进

**阶段一：Python + KLayout API（早期）**
最初用 KLayout Python 绑定手动读取 DEF + 合并标准单元 GDS。工作正常但有 Python 依赖。

**阶段二：strm2gds + 后缀匹配（当前）**
修改 KLayout 源码的 `dbLEFDEFImporter.cc`，在 `finish()` 函数中增加**后缀匹配**：
当精确匹配失败时，遍历宏布局库寻找以目标名结尾的 cell。这样 DEF 中的 `and3_1` 自动匹配 GDS 中的 `sky130_fd_sc_hd__and3_1`，无需 FOREIGN 声明。

同时重构 strm2gds 编译，直接链接所有格式插件（liblefdef、libgds2、liboasis 等），RPATH 包含 `/usr/local/lib/klayout/db_plugins`，安装即用，零 Python 依赖。

```bash
strm2gds \
  --lefdef-lefs <techlef>,<macrolef> \
  --lefdef-lef-layouts-dir <gds_dir> \
  --lefdef-macro-resolution-mode 2 \
  --lefdef-map sky130A.map \
  design.def design.gds
```

### 6.2 图层映射

必须使用 `--lefdef-map sky130A.map` 将 LEF 布线层映射到正确的 sky130 GDS 层号：

| LEF 层 | map 前 (默认) | map 后 (正确) |
|--------|--------------|--------------|
| met1   | 3/0 | **68/20** |
| met2   | 4/0 | **69/20** |

不使用 map 的话 GDS 层号是错的，KLayout/GDS3D 无法正确显示。

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
- KLayout 包 114MB（链接所有格式插件后略增）
- strm2gds 已直接链接 liblefdef.so，RPATH 含 `/usr/local/lib/klayout/db_plugins`
- `drink-pkg build` 需 `follow_symlinks(false)` 防止软链接被展开（已修）

---

## 九、LoongArch 特有坑

1. **ABC SCL hash** → 必须打补丁，否则 ABC 崩溃
2. **GCC LTO** → GCC 15.3.0 已修复，LTO 可正常启用
3. **CUDD 符号** → ABC 用 `ABC_NAMESPACE=abc` 编译，OpenSTA 需 C 链接包裹
4. **strm2gds 插件加载** → 直接链接所有格式插件到 strm2gds，RPATH 含 db_plugins
5. **HAS_GPL** → 需 `-DHAS_GPL=1` 编译 OpenROAD 以启用 gpl 模块

---


## or-tools 编译（LoongArch）

or-tools 是 Google 的运筹优化库，OpenROAD 的 GPL 模块（全局布局、write_gds）依赖它。

### 依赖

| 依赖 | 用途 | 获取方式 |
|------|------|----------|
| abseil-cpp | Google 基础库 | git clone (gitcode 镜像) |
| protobuf | 序列化 | git clone (gitcode 镜像) |
| zlib | 压缩 | git clone (gitcode 镜像) |
| bzip2 | 压缩 | git clone (gitlab) |
| re2 | 正则 | git clone (gitcode 镜像) |
| Eigen3 | 线性代数 | git clone (gitlab), 需删 bench/ demos/ |
| HiGHS | 线性规划 | git clone (gitcode 镜像) |

### 编译命令

```bash
cd or-tools && mkdir build && cd build
cmake ..   -DCMAKE_INSTALL_PREFIX=$HOME/.local   -DBUILD_DEPS=ON -DBUILD_PYTHON=OFF   -DBUILD_TESTING=OFF -DBUILD_SAMPLES=OFF   -DFETCHCONTENT_SOURCE_DIR_ABSL=...   -DFETCHCONTENT_SOURCE_DIR_PROTOBUF=...   ... (所有依赖的 FETCHCONTENT_SOURCE_DIR)
make -j$(nproc)
make install
```

### 补丁

or-tools 在 LoongArch 上需要 3 处源码修改（不纳入仓库，仅编译时本地应用）：
1. `constraint_solver/constraint_solveri.h` — 添加 `__loongarch64` 到 64 位检测
2. `base/source_location.h` — 检测 abseil 已提供时跳过自带定义
3. 各依赖的 CMakeLists 中注释掉有问题的 subdirectory

### 注意事项

- 不联网编译需预先 clone 所有依赖到 _deps/ 目录
- GitHub 不可用时使用 gitcode 镜像
- Eigen 必须删除 bench/ 和 demos/ 目录

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
