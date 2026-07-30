# OpenROAD LoongArch 源码仓库地址

> 所有 GitHub 仓库使用 gitcode 镜像加速访问

## 主仓库

| 项目 | 地址 |
|------|------|
| **OpenROAD** | `https://gitcode.com/gh_mirrors/op/OpenROAD.git` |

## 子模块（`git submodule update --init --recursive` 自动拉取）

| 子模块 | 位置 | 原始地址 |
|--------|------|----------|
| OpenSTA | `src/sta` | https://github.com/The-OpenROAD-Project/OpenSTA.git |
| ABC | `third-party/abc` | https://github.com/The-OpenROAD-Project/abc.git |
| slang-elab | `third-party/slang-elab` | https://github.com/MikePopoloski/slang-elab.git |

## slang 子模块的依赖（SYN 模块需要）

若需编译 SYN 模块，需要初始化 slang 的 git 子模块（位于 `third-party/slang-elab/third_party/slang/`）：

```bash
cd third-party/slang-elab
git submodule update --init --recursive
```

或从镜像手动 clone：

| 依赖 | 镜像地址 |
|------|----------|
| slang 主库 | `https://gitcode.com/gh_mirrors/slan/slang.git` |
| fmt | `https://gitcode.com/gh_mirrors/fm/fmt.git` |

## 额外依赖（external/ 目录下的子模块）

slang 的 `external/` 目录包含多个子模块，需镜像 clone 放入对应目录：

| 依赖 | 镜像地址 |
|------|----------|
| unordered_dense | `https://gitcode.com/gh_mirrors/un/unordered_dense.git` |
| miniz | `https://gitcode.com/gh_mirrors/mi/miniz.git` |
| lz4 | `https://gitcode.com/GitHub_Trending/lz/lz4.git` |
| cmark | `https://gitcode.com/gh_mirrors/cm/cmark.git` |
| glslang | `https://gitcode.com/gh_mirrors/gl/glslang.git` |
| tinyobjloader | `https://gitcode.com/gh_mirrors/ti/tinyobjloader.git` |
| glm | `https://gitcode.com/gh_mirrors/gl/glm.git` |
| imgui | `https://gitcode.com/GitHub_Trending/im/imgui.git` |
| SPIRV-Tools | `https://gitcode.com/gh_mirrors/sp/SPIRV-Tools.git` |
| SPIRV-Headers | `https://gitcode.com/gh_mirrors/sp/SPIRV-Headers.git` |
| DirectXShaderCompiler | `https://gitcode.com/gh_mirrors/di/DirectXShaderCompiler.git` |
| DirectX-Headers | `https://gitcode.com/gh_mirrors/di/DirectX-Headers.git` |
| nlohmann/json | `https://gitcode.com/GitHub_Trending/js/json.git` |
| xxhash | xxHash-dev.zip（见 /home/lik/下载/） |

> ⚠️ SYN 模块因 slang 依赖过多（DXC/SPIRV/Vulkan/MoltenVK）不建议启用。

## or-tools 依赖

| 依赖 | 镜像地址 |
|------|----------|
| **or-tools** | `https://gitcode.com/gh_mirrors/or/or-tools.git` |
| abseil-cpp | `https://gitcode.com/GitHub_Trending/ab/abseil-cpp.git` |
| protobuf | `https://gitcode.com/GitHub_Trending/pr/protobuf.git` |
| zlib | `https://gitcode.com/gh_mirrors/zl/zlib.git` |
| bzip2 | `https://gitlab.com/bzip2/bzip2.git` |
| re2 | `https://gitcode.com/gh_mirrors/re23/re2.git` |
| Eigen3 | `https://gitlab.com/libeigen/eigen.git`（需 checkout 3.4.0） |
| HiGHS | `https://gitcode.com/GitHub_Trending/hi/HiGHS.git` |

## 其他工具

| 工具 | 地址 |
|------|------|
| Yosys | `https://github.com/YosysHQ/yosys.git`（需 ABC hash 补丁） |
| KLayout | `https://github.com/KLayout/klayout.git` |
| GDS3D | `https://gitcode.com/gh_mirrors/tr/GDS3D.git`（原版：https://sourceforge.net/projects/gds3d） |
| skywater-pdk | `https://gitcode.com/google/skywater-pdk.git` |
| open_pdks | `https://github.com/fossi-foundation/open-pdks.git` |
| magic | `https://github.com/RTimothyEdwards/magic.git` |
| netgen | `https://github.com/RTimothyEdwards/netgen.git`（LVS 用） |
| ngspice | `https://gitcode.com/gh_mirrors/ng/ngspice.git` |
| iverilog | `https://gitcode.com/gh_mirrors/iv/iverilog.git` |
| Kokkos | `https://gitcode.com/GitHub_Trending/ko/kokkos.git` |

## 补丁文件位置

| 补丁 | 路径 |
|------|------|
| ABC SCL hash 修复（LoongArch） | `patches/abc_scl_loongarch_hash_fix.patch` |
| OpenROAD read_lef 修复 | `patches/openroad_readlef_update_lib.patch` |
| OpenROAD CMakeLists 顺序修复 | 手动修改：`target_compile_definitions` → `add_compile_definitions` |

## 构建顺序

```bash
# 1. or-tools（最核心，最难适配）
git clone https://gitcode.com/gh_mirrors/or/or-tools.git
# 在 CMakeLists.txt 中设置 FETCHCONTENT_SOURCE_DIR_* 指向本地 clone
# 需要打 3 处 LoongArch 补丁（见 EXPERIENCE.md）

# 2. OpenROAD
git clone https://gitcode.com/gh_mirrors/op/OpenROAD.git
cd OpenROAD
git submodule update --init --recursive
# 打 read_lef 补丁
# 修 CMakeLists 中的 target_compile_definitions 顺序
# 编译: cmake .. -DENABLE_GPL=ON ...
```

> 📌 完整搭建过程见 `examples/loong8-ws2812-rc2/EXPERIENCE.md`
