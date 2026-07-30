# OpenROAD 龙芯编译指南 (2026-07-30)

## 环境
- 架构: LoongArch (loongarch64)
- 系统: AOSC OS 13.3+
- GCC: 15.3.0
- CMake: 3.31+

## 关键修复

### CUDD 兼容层
OpenSTA 需要 CUDD BDD 库。ABC 内置了 CUDD 但符号在 abc:: 命名空间。
创建独立 libcudd.a (无命名空间) + extern "C" 包裹头文件。

### KLayout strm2gds 后缀匹配补丁
修改 `dbLEFDEFImporter.cc` 的 `finish()` 函数，在匹配标准单元 GDS 时
增加后缀匹配。DEF 中的 `and3_1` 自动匹配 GDS 中的 `sky130_fd_sc_hd__and3_1`。
补丁位置: `patches/klayout_suffix_match.patch`

### OpenROAD CMake 配置
```
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_TESTS=OFF \
  -DLINK_TIME_OPTIMIZATION=ON \
  -DUSE_SYSTEM_BOOST=ON \
  -DBUILD_PYTHON=OFF \
  -DCUDD_LIB=$(pwd)/../cudd_build/build/libcudd.a \
  -DCUDD_INCLUDE=$(pwd)/build/third-party/include \
  -Dspdlog_DIR=/usr/lib64/cmake/spdlog \
  -DLEMON_DIR=$HOME/.local/share/lemon/cmake \
  -DCMAKE_CXX_FLAGS="-DHAS_GPL=1"
```
