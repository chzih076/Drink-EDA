# OpenROAD 龙芯编译指南

## 环境
- 架构: LoongArch (loongarch64)
- 系统: AOSC OS 13.3+
- GCC: 15.3.0
- CMake: 3.31+

## 依赖

```bash
oma install tcl-devel swig eigen-5 spdlog boost bison flex zlib \
  readline-devel libffi-devel qt5-devel
```

## 编译步骤

```bash
git clone https://gitcode.com/gh_mirrors/op/OpenROAD.git
cd OpenROAD

# 克隆子模块
git clone https://gitcode.com/gh_mirrors/op/OpenSTA.git src/sta
git clone https://gitcode.com/gh_mirrors/ab/abc.git third-party/abc
git clone https://gitee.com/jmh520/yosys-slang.git third-party/slang-elab
cd third-party/slang-elab/third_party
git clone https://gitcode.com/gh_mirrors/fm/fmt.git fmt
git clone https://gitcode.com/gh_mirrors/sl/slang.git slang
cd /home/lik/OpenROAD

# LEMON 图库 (需 C++20 补丁)
wget http://lemon.cs.elte.hu/pub/sources/lemon-1.3.1.tar.gz
tar xzf lemon-1.3.1.tar.gz
cd lemon-1.3.1
cmake -B build -DCMAKE_INSTALL_PREFIX=~/.local
cmake --build build -j$(nproc)
cmake --install build
# 应用 C++20 补丁
cd /home/lik/OpenROAD
patch -p0 < third-party/lemon/patches/allocator-patch.patch \
  -d ~/.local/include
cd /home/lik/OpenROAD
```

## CUDD 兼容层

OpenSTA 需要 CUDD 库（BCD 决策图）。ABC 内置了 CUDD 但符号在 abc:: 命名空间。

创建包装文件 `src/sta/cudd_wrap.cpp`:

```cpp
#define ABC_NAMESPACE abc
#include "sta/cudd_compat.h"

extern "C" {
DdManager* Cudd_Init(...) { return abc::Cudd_Init(...); }
void Cudd_Ref(DdNode* n) { abc::Cudd_Ref(n); }
// ... 所有 OpenSTA 使用的 CUDD 函数
}
```

## CMake 配置

关键选项（禁用 LTO 和不需要的模块）：

```bash
mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_TESTS=OFF \
  -DLINK_TIME_OPTIMIZATION=OFF \
  -DUSE_SYSTEM_BOOST=ON \
  -Dspdlog_DIR=/usr/lib/cmake/spdlog \
  -DLEMON_DIR=~/.local/share/lemon/cmake \
  -DENABLE_GPL=OFF -DENABLE_MPL=OFF -DENABLE_PAR=OFF -DENABLE_SYN=OFF \
  -DBUILD_PYTHON=OFF \
  -DCUDD_INCLUDE=/home/lik/OpenROAD/third-party/abc/src \
  -DCUDD_LIB=/tmp/cudd_build/build/libcudd.a
```

## 已知问题及修复

### 1. static lib 循环链接
`openroad` 链接时报 `undefined reference to sta::*`。
**修复**: `src/CMakeLists.txt` 末尾加 `target_link_libraries(openroad OpenSTA)`

### 2. CUDD 符号找不到
ABC 用 `ABC_NAMESPACE=abc` 编译，符号在 `abc::`。OpenSTA 需要裸 C 符号。
**修复**: `src/sta/include/sta/cudd_compat.h` 用 `using namespace abc;`

### 3. -fno-exceptions 传播
ABC 的 `-fno-exceptions` 通过 PUBLIC 传播给 cut 等模块。
**修复**: 改 `third-party/abc/CMakeLists.txt`，compile_options 用 PRIVATE

### 4. 3dblox 链接顺序
**修复**: `src/CMakeLists.txt` 的 target_link_libraries 中 `odb` 放 `OpenSTA` 前

### 5. GPL 模块缺 or-tools
**修复**: 用 `option(ENABLE_GPL OFF)` 禁用，对应代码用 `#ifdef HAS_GPL` 包裹

### 6. gcc LTO 在 LoongArch 上 bug
**修复**: `-DLINK_TIME_OPTIMIZATION=OFF` 且 `-DCMAKE_CXX_FLAGS="-fno-lto"`

### 7. read_lef 二次调用创建重复库

连续调用 `read_lef`（先读 techlef 再读 macro lef）时，第二个 lef 因同名库已存在而静默丢弃，导致 LEF macro 未注册。

**现象**: `[WARNING ODB-0229] Error: library (sky130_fd_sc_hd) already exists`
→ `link_design` 时报 `LEF master xxx not found`

**根因**: `OpenRoad.cc:readLef()` 对 `make_library=true` 的分支固定调用
`lef_reader.createLib()`，该函数检查 `db_->findLib(name)` 后直接 return nullptr。

**修复**: 当库已存在时改用 `lef_reader.updateLib()`:

```diff
-    lef_reader.createLib(tech, lib_name, filename);
+    odb::dbLib* lib = db_->findLib(lib_name);
+    if (lib) {
+      lef_reader.updateLib(lib, filename);
+    } else {
+      lef_reader.createLib(tech, lib_name, filename);
+    }
```
