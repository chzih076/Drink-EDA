// manifests — 生成 loongarch-eda/manifests/*.toml 安装清单
//
// 移植自 scripts/gen_manifests.py。
// 注意：以下路径均为构建机专用（本机 ~/.local/bin 等），
// 仅在构建机上运行，用 ldd 扫描
// 各 EDA 工具的共享库依赖，输出 TOML 格式安装清单。

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const MANIFEST_DIR: &str = "/home/lik/loongarch-eda/manifests";

/// 用 ldd 提取二进制的共享库依赖（绝对路径）。
fn get_deps(bin: &str) -> Vec<String> {
    let mut libs: Vec<String> = Vec::new();
    if let Ok(out) = Command::new("ldd").arg(bin).output() {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            if let Some(pos) = line.find("=> /") {
                let rest = &line[pos + 3..];
                let path: String = rest
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .to_string();
                if path.starts_with('/') && !libs.contains(&path) {
                    libs.push(path);
                }
            }
        }
    }
    libs
}

/// 列出目录下匹配前缀的文件（klayout 的 libklayout_*.so*）。
fn glob_prefix(dir: &str, prefix: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if name.starts_with(prefix) {
                out.push(e.path().to_string_lossy().to_string());
            }
        }
    }
    out.sort();
    out
}

struct ManifestSpec {
    name: String,
    version: String,
    desc: String,
    bin_src: String,
    bin_dst: String,
    extra: Vec<(String, String, String)>, // (src, dst, mode)
    libs: Vec<String>,
}

fn write_manifest(spec: &ManifestSpec) -> Result<usize, String> {
    let path = Path::new(MANIFEST_DIR).join(format!("{}.toml", spec.name));
    let mut s = String::new();
    s.push_str(&format!("name = \"{}\"\n", spec.name));
    s.push_str(&format!("version = \"{}\"\n", spec.version));
    s.push_str(&format!("desc = \"{}\"\n", spec.desc));
    s.push_str("deps = []\nprovides = []\nfiles = []\n\n");
    s.push_str("[install]\nfiles = [\n");
    s.push_str(&format!(
        "  {{ src = \"{}\", dst = \"{}\", mode = \"0o755\" }},\n",
        spec.bin_src, spec.bin_dst
    ));
    let mut count = 1;
    for (src, dst, mode) in &spec.extra {
        s.push_str(&format!("  {{ src = \"{src}\", dst = \"{dst}\", mode = \"{mode}\" }},\n"));
        count += 1;
    }
    for lib in &spec.libs {
        if Path::new(lib).is_file() {
            let base = lib.rsplit('/').next().unwrap_or(lib);
            s.push_str(&format!(
                "  {{ src = \"{lib}\", dst = \"/usr/lib/{base}\", mode = \"0o644\" }},\n"
            ));
            count += 1;
        }
    }
    s.push_str("]\n");
    fs::write(&path, s).map_err(|e| format!("写入 {path:?} 失败: {e}"))?;
    println!("  {}: {count} files", path.display());
    Ok(count)
}

pub fn run(_args: &[String]) -> Result<(), String> {
    fs::create_dir_all(MANIFEST_DIR).map_err(|e| format!("创建 manifests 目录失败: {e}"))?;

    println!("=== Generating manifests with full deps ===");

    let yosys_deps = {
        let mut d = get_deps("/home/lik/.local/bin/yosys");
        d.extend(get_deps("/home/lik/.local/bin/yosys-abc"));
        d.sort();
        d.dedup();
        d
    };
    let or_deps = get_deps("/home/lik/.local/bin/openroad");
    let magic_deps = get_deps("/home/lik/.local/bin/magic");
    let ngspice_deps = get_deps("/usr/bin/ngspice");
    let iv_deps = get_deps("/usr/bin/iverilog");

    write_manifest(&ManifestSpec {
        name: "yosys".into(),
        version: "0.67.0".into(),
        desc: "Yosys + ABC (LoongArch, hash fixed)".into(),
        bin_src: "/home/lik/.local/bin/yosys".into(),
        bin_dst: "/usr/local/bin/yosys".into(),
        extra: vec![
            ("/home/lik/.local/bin/yosys-abc".into(), "/usr/local/bin/yosys-abc".into(), "0o755".into()),
            ("/home/lik/.local/share/yosys".into(), "/usr/local/share/yosys".into(), "0o644".into()),
        ],
        libs: yosys_deps,
    })?;

    write_manifest(&ManifestSpec {
        name: "openroad".into(),
        version: "26Q3".into(),
        desc: "OpenROAD PnR (LoongArch, read_lef fixed)".into(),
        bin_src: "/home/lik/.local/bin/openroad".into(),
        bin_dst: "/usr/local/bin/openroad".into(),
        extra: vec![],
        libs: or_deps,
    })?;

    write_manifest(&ManifestSpec {
        name: "magic".into(),
        version: "8.3".into(),
        desc: "Magic VLSI Layout Tool".into(),
        bin_src: "/home/lik/.local/bin/magic".into(),
        bin_dst: "/usr/local/bin/magic".into(),
        extra: vec![],
        libs: magic_deps,
    })?;

    write_manifest(&ManifestSpec {
        name: "ngspice".into(),
        version: "46".into(),
        desc: "NGSPICE circuit simulator".into(),
        bin_src: "/usr/bin/ngspice".into(),
        bin_dst: "/usr/local/bin/ngspice".into(),
        extra: vec![],
        libs: ngspice_deps,
    })?;

    write_manifest(&ManifestSpec {
        name: "iverilog".into(),
        version: "12.0".into(),
        desc: "Icarus Verilog simulator".into(),
        bin_src: "/usr/bin/iverilog".into(),
        bin_dst: "/usr/local/bin/iverilog".into(),
        extra: vec![],
        libs: iv_deps,
    })?;

    // klayout（独立构建，无 Python/Ruby）
    let klayout_bin = "/home/lik/klayout/bin-release/klayout".to_string();
    let klayout_libs: Vec<String> = glob_prefix("/home/lik/klayout/bin-release", "libklayout_");
    let mut klayout_deps = get_deps(&klayout_bin);
    klayout_deps.extend(klayout_libs.clone());
    klayout_deps.sort();
    klayout_deps.dedup();

    let kpath = PathBuf::from(MANIFEST_DIR).join("klayout.toml");
    let mut ks = String::new();
    ks.push_str("name = \"klayout\"\n");
    ks.push_str("version = \"0.30.9\"\n");
    ks.push_str("desc = \"KLayout standalone (no Python/Ruby)\"\n");
    ks.push_str("deps = []\nprovides = []\nfiles = []\n\n");
    ks.push_str("[install]\nfiles = [\n");
    ks.push_str(&format!(
        "  {{ src = \"{klayout_bin}\", dst = \"/usr/local/bin/klayout\", mode = \"0o755\" }},\n"
    ));
    let mut kcount = 1;
    for lib in &klayout_libs {
        if Path::new(lib).is_file() {
            let base = lib.rsplit('/').next().unwrap_or(lib);
            ks.push_str(&format!(
                "  {{ src = \"{lib}\", dst = \"/usr/local/lib/{base}\", mode = \"0o644\" }},\n"
            ));
            kcount += 1;
        }
    }
    for lib in &klayout_deps {
        if Path::new(lib).is_file() && !lib.contains("klayout") {
            let base = lib.rsplit('/').next().unwrap_or(lib);
            ks.push_str(&format!(
                "  {{ src = \"{lib}\", dst = \"/usr/lib/{base}\", mode = \"0o644\" }},\n"
            ));
            kcount += 1;
        }
    }
    ks.push_str("]\n");
    fs::write(&kpath, ks).map_err(|e| format!("写入 klayout.toml 失败: {e}"))?;
    println!("  {}: {kcount} files", kpath.display());

    println!("\nDone");
    Ok(())
}
