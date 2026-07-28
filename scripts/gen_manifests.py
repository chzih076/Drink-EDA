#!/usr/bin/env python3
"""
生成 manifests/*.toml 安装清单。

仅在构建机上运行，读取宿主机已编译的二进制和动态库依赖，
自动输出 TOML 格式安装清单。

不进容器／不进 DrinkLinux 发行版。
依赖: python3, ldd
"""
import subprocess, os, glob, json

def get_deps(bin_path):
    """Get all shared library dependencies for a binary."""
    libs = set()
    r = subprocess.run(["ldd", bin_path], capture_output=True, text=True)
    for line in r.stdout.split("\n"):
        if "=> /" in line:
            parts = line.strip().split()
            for p in parts:
                if p.startswith("/"):
                    libs.add(p)
                    break
    return sorted(libs)

# === yosys ===
yosys_deps = get_deps("/home/lik/.local/bin/yosys")
yosys_deps += get_deps("/home/lik/.local/bin/yosys-abc")
yosys_deps = sorted(set(yosys_deps))

# === openroad ===
or_deps = get_deps("/home/lik/.local/bin/openroad")

# === magic ===
magic_deps = get_deps("/home/lik/.local/bin/magic")

# === klayout (standalone) ===
klayout_bin = "/home/lik/klayout/bin-release/klayout"
klayout_libs = sorted(glob.glob("/home/lik/klayout/bin-release/libklayout_*.so*"))
klayout_deps = sorted(set(get_deps(klayout_bin) + klayout_libs))

# === ngspice ===
ngspice_deps = get_deps("/usr/bin/ngspice")

# === iverilog ===
iv_deps = get_deps("/usr/bin/iverilog")

# Generate TOML manifest for each tool
def write_manifest(name, version, desc, bin_src, bin_dst, extra_files, lib_deps):
    path = f"/home/lik/loongarch-eda/manifests/{name}.toml"
    with open(path, "w") as f:
        f.write(f'name = "{name}"\n')
        f.write(f'version = "{version}"\n')
        f.write(f'desc = "{desc}"\n')
        f.write(f'deps = []\n')
        f.write(f'provides = []\n')
        f.write(f'files = []\n\n')
        f.write('[install]\n')
        f.write('files = [\n')
        # Main binary
        f.write(f'  {{ src = "{bin_src}", dst = "{bin_dst}", mode = "0o755" }},\n')
        # Extra files
        for src, dst, mode in extra_files:
            f.write(f'  {{ src = "{src}", dst = "{dst}", mode = "{mode}" }},\n')
        # Libraries
        for lib in lib_deps:
            if os.path.exists(lib) and os.path.isfile(lib):
                dst = os.path.join("/usr/lib", os.path.basename(lib))
                f.write(f'  {{ src = "{lib}", dst = "{dst}", mode = "0o644" }},\n')
        f.write(']\n')
    print(f"  {path}: {1 + len(extra_files) + len([l for l in lib_deps if os.path.isfile(l)])} files")

def write_klayout_manifest():
    path = "/home/lik/loongarch-eda/manifests/klayout.toml"
    with open(path, "w") as f:
        f.write('name = "klayout"\n')
        f.write('version = "0.30.9"\n')
        f.write('desc = "KLayout standalone (no Python/Ruby)"\n')
        f.write('deps = []\nprovides = []\nfiles = []\n\n')
        f.write('[install]\n')
        f.write('files = [\n')
        # Binary
        f.write(f'  {{ src = "{klayout_bin}", dst = "/usr/local/bin/klayout", mode = "0o755" }},\n')
        # KLayout-specific libs
        for lib in klayout_libs:
            if os.path.isfile(lib):
                f.write(f'  {{ src = "{lib}", dst = "/usr/local/lib/{os.path.basename(lib)}", mode = "0o644" }},\n')
        # System lib deps for klayout
        for lib in klayout_deps:
            if os.path.isfile(lib) and "klayout" not in lib:
                dst = os.path.join("/usr/lib", os.path.basename(lib))
                f.write(f'  {{ src = "{lib}", dst = "{dst}", mode = "0o644" }},\n')
        f.write(']\n')
    print(f"  {path}: {1 + len(klayout_libs) + len([l for l in klayout_deps if 'klayout' not in l])} files")

print("=== Generating manifests with full deps ===")
write_manifest("yosys", "0.67.0", "Yosys + ABC (LoongArch, hash fixed)",
    "/home/lik/.local/bin/yosys", "/usr/local/bin/yosys",
    [("/home/lik/.local/bin/yosys-abc", "/usr/local/bin/yosys-abc", "0o755"),
     ("/home/lik/.local/share/yosys", "/usr/local/share/yosys", "0o644")],
    yosys_deps)

write_manifest("openroad", "26Q3", "OpenROAD PnR (LoongArch, read_lef fixed)",
    "/home/lik/.local/bin/openroad", "/usr/local/bin/openroad",
    [], or_deps)

write_manifest("magic", "8.3", "Magic VLSI Layout Tool",
    "/home/lik/.local/bin/magic", "/usr/local/bin/magic",
    [], magic_deps)

write_manifest("ngspice", "46", "NGSPICE circuit simulator",
    "/usr/bin/ngspice", "/usr/local/bin/ngspice",
    [], ngspice_deps)

write_manifest("iverilog", "12.0", "Icarus Verilog simulator",
    "/usr/bin/iverilog", "/usr/local/bin/iverilog",
    [], iv_deps)

write_klayout_manifest()

print("\nDone")
