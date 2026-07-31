# 构建指南

## 构建顺序

```
1. yosys (ISC)
   ├── apply: abc_scl_loongarch_hash_fix.patch
   └── 编译: make -j$(nproc)

2. OpenROAD (BSD-3)
   ├── apply: openroad_readlef_update_lib.patch
   ├── apply: abc_CMakeLists.patch → third-party/abc/CMakeLists.txt
   ├── apply: src_CMakeLists.patch → src/CMakeLists.txt
   ├── apply: cut_CMakeLists.patch → src/cut/src/CMakeLists.txt
   ├── apply: sta_CMakeLists.patch → src/sta/CMakeLists.txt
   ├── deps: LEMON (allocator-patch.patch)
   └── cmake: -DENABLE_GPL=OFF -DENABLE_MPL=OFF -DENABLE_PAR=OFF -DENABLE_SYN=OFF

3. magic (BSD)
   ├── 直接编译: ./configure && make
   └── 需要 Tcl/Tk

4. KLayout (GPL - 单独分发)
   ├── ./build.sh -noruby -nopython
   └── 需要 Qt5

5. PDK
   ├── open_pdks → sky130A（make all-A）
   ├── drink lvs-models（生成 LVS 模型库 sky130A.lvs.spice）
   └── 打包裁剪（核心 tt/ff/ss，扩展全 corner；全量本地保留）

6. netgen（GPL-2.0，含源码修复）
   ├── apply: netgen_spice_parse_fixes.patch
   │   （spice.c: .model 卡跳过 + 顶层自引用检查限 subckt 内）
   └── apply: netgen_skipnewline_fix.patch
       （netfile.c: SpiceSkipNewLine 跳过续行间注释行）
```

## 包构建

```bash
# 1. 生成安装清单（Rust 统一工具，替代 Python）
drink manifests

# 2. 生成 PDK 分包目录树（Rust，替代 package_sky130_split.py）
drink package --pdk-root ~/.local/share/pdk/sky130A --out build-pkgs/sky130-pdk-split

# 3. 构建 .drink 包
drink-pkg build pkgdir

# 4. 部署到 rootfs
drink-pkg deploy -r /path/to/rootfs manifests/yosys.toml
```
