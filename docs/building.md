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
   ├── open_pdks → sky130A
   ├── gen_pdk_libs expand (裁剪多工艺角)
   └── 仅保留 tt_025C_1v80
```

## 包构建

```bash
# 1. 生成安装清单
python3 scripts/gen_manifests.py

# 2. 构建 .drink 包
drink-pkg build pkgdir

# 3. 部署到 rootfs
drink-pkg deploy -r /path/to/rootfs manifests/yosys.toml
```
