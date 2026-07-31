// package — 生成 sky130-pdk 分包目录树（核心 + 5 扩展）与 metadata.toml
//
// 移植自 scripts/package_sky130_split.py：
//   drink package [--pdk-root <sky130A>] [--out <PKGBASE>]
// 输出目录结构（供 drink-pkg build 使用）：
//   <out>/sky130-pdk/files/usr/local/share/pdk/sky130A/...   （核心）
//   <out>/sky130-pdk-extra-{hs,ls,ms,lp,misc}/files/...      （扩展）

use std::fs;
use std::path::{Path, PathBuf};

use crate::cli;

/// 每变体保留的 lib corner（tt 标称 + 1 个 ff + 1 个 ss，不含 ccsnoise）。
const CORE_LIBS: &[(&str, &[&str])] = &[
    ("sky130_fd_sc_hd",   &["tt_025C_1v80.lib", "ff_100C_1v95.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_hdll", &["tt_025C_1v80.lib", "ff_100C_1v95.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_hs",   &["tt_025C_1v80.lib", "ff_100C_1v95.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_lp",   &["ff_100C_1v95.lib", "ff_150C_2v05.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_ls",   &["tt_025C_1v80.lib", "ff_100C_1v95.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_ms",   &["tt_025C_1v80.lib", "ff_100C_1v95.lib", "ss_100C_1v60.lib"]),
    ("sky130_fd_sc_hvl",  &["tt_025C_3v30.lib", "ff_100C_5v50.lib", "ss_100C_3v00.lib"]),
    ("sky130_sram_macros", &[]), // SRAM 宏 lib 很少，全量保留
];

/// 扩展包：变体 -> 包名。
const EXTRA_PKGS: &[(&str, &[&str])] = &[
    ("sky130-pdk-extra-hs",   &["sky130_fd_sc_hs"]),
    ("sky130-pdk-extra-ls",   &["sky130_fd_sc_ls"]),
    ("sky130-pdk-extra-ms",   &["sky130_fd_sc_ms"]),
    ("sky130-pdk-extra-lp",   &["sky130_fd_sc_lp"]),
    ("sky130-pdk-extra-misc", &["sky130_fd_sc_hd", "sky130_fd_sc_hdll", "sky130_fd_sc_hvl"]),
];

fn core_libs_for(variant: &str) -> Option<&'static [&'static str]> {
    CORE_LIBS.iter().find(|(v, _)| *v == variant).map(|(_, l)| *l)
}

/// 递归复制目录（保留 symlink）。
fn copy_tree(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| format!("创建 {} 失败: {e}", dst.display()))?;
    for entry in fs::read_dir(src).map_err(|e| format!("读取 {} 失败: {e}", src.display()))? {
        let entry = entry.map_err(|e| e.to_string())?;
        let st = entry.file_type().map_err(|e| e.to_string())?;
        let s = entry.path();
        let d = dst.join(entry.file_name());
        if st.is_symlink() {
            let target = fs::read_link(&s).map_err(|e| format!("读链接 {} 失败: {e}", s.display()))?;
            std::os::unix::fs::symlink(&target, &d)
                .map_err(|e| format!("建链接 {d:?} 失败: {e}"))?;
        } else if st.is_dir() {
            copy_tree(&s, &d)?;
        } else {
            fs::copy(&s, &d).map_err(|e| format!("复制 {} 失败: {e}", s.display()))?;
        }
    }
    Ok(())
}

fn write_metadata(pkg_dir: &Path, name: &str, version: &str, desc: &str, install_src: &str) -> Result<(), String> {
    fs::create_dir_all(pkg_dir).map_err(|e| e.to_string())?;
    let meta = format!(
        "name = \"{name}\"\n\
         version = \"{version}\"\n\
         desc = \"{desc}\"\n\
         deps = [\"lib-src\"]\n\
         provides = []\n\
         license = \"Apache-2.0\"\n\
         files = []\n\
         \n\
         [install]\n\
         files = [\n\
         \x20 {{ src = \"{install_src}\", dst = \"/usr/local/share/pdk/sky130A\", mode = \"0o755\" }},\n\
         ]\n"
    );
    fs::write(pkg_dir.join("metadata.toml"), meta).map_err(|e| format!("写 metadata 失败: {e}"))
}

fn dir_size(path: &Path) -> Result<u64, String> {
    let mut total = 0u64;
    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let p = entry.path();
        if entry.file_type().map_err(|e| e.to_string())?.is_dir() {
            total += dir_size(&p)?;
        } else {
            total += entry.metadata().map_err(|e| e.to_string())?.len();
        }
    }
    Ok(total)
}

pub fn run(args: &[String]) -> Result<(), String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/home/lik".to_string());
    let mut pdk_root = PathBuf::from(&home).join(".local/share/pdk/sky130A");
    let mut pkg_base = PathBuf::from(&home).join("build-pkgs/sky130-pdk-split");

    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--pdk-root" => pdk_root = PathBuf::from(cli::next_val(&mut it, "--pdk-root")?),
            "--out" => pkg_base = PathBuf::from(cli::next_val(&mut it, "--out")?),
            _ => return Err(format!("未知参数: {a}")),
        }
    }

    if !pdk_root.is_dir() {
        return Err(format!("找不到 PDK 根: {}", pdk_root.display()));
    }
    let refs = pdk_root.join("libs.ref");

    // ── 1. 核心包 ───────────────────────────────────────────
    let core_install = pkg_base.join("sky130-pdk/files/usr/local/share/pdk/sky130A");
    if core_install.exists() {
        fs::remove_dir_all(&core_install).map_err(|e| e.to_string())?;
    }
    fs::create_dir_all(&core_install).map_err(|e| e.to_string())?;

    let mut variants: Vec<String> = Vec::new();
    let rd = fs::read_dir(&refs).map_err(|e| format!("读取 libs.ref 失败: {e}"))?;
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        if e.path().is_dir() {
            variants.push(name);
        }
    }
    variants.sort();

    for v in &variants {
        let sv = refs.join(v);
        let dv = core_install.join("libs.ref").join(v);
        fs::create_dir_all(&dv).map_err(|e| e.to_string())?;
        let subs = fs::read_dir(&sv).map_err(|e| e.to_string())?;
        for sub in subs.flatten() {
            let name = sub.file_name().to_string_lossy().to_string();
            let sp = sub.path();
            if name == "lib" {
                // 核心 lib：只保留 CORE_LIBS 明确列出的 corner；
                // sram_macros 特殊全量；io 等未列出的变体不复制 lib
                let dlib = dv.join("lib");
                fs::create_dir_all(&dlib).map_err(|e| e.to_string())?;
                if v == "sky130_sram_macros" {
                    // SRAM 宏 lib 很少（~200K），全量保留
                    let files: Vec<String> = fs::read_dir(&sp)
                        .map_err(|e| e.to_string())?
                        .flatten()
                        .map(|e| e.file_name().to_string_lossy().to_string())
                        .collect();
                    for f in files {
                        fs::copy(sp.join(&f), dlib.join(&f))
                            .map_err(|e| format!("复制 {f} 失败: {e}"))?;
                    }
                } else if let Some(keep) = core_libs_for(v) {
                    for f in keep {
                        let spf = sp.join(f);
                        if spf.is_file() {
                            fs::copy(&spf, dlib.join(f))
                                .map_err(|e| format!("复制 {f} 失败: {e}"))?;
                        } else {
                            eprintln!("  警告: {v}/lib/{f} 不存在");
                        }
                    }
                }
                // 其余变体（io 等）：lib 不进入核心包
            } else {
                copy_tree(&sp, &dv.join(&name))?;
            }
        }
    }
    copy_tree(&pdk_root.join("libs.tech"), &core_install.join("libs.tech"))?;
    if pdk_root.join(".config").is_dir() {
        copy_tree(&pdk_root.join(".config"), &core_install.join(".config"))?;
    }
    write_metadata(
        &pkg_base.join("sky130-pdk"),
        "sky130-pdk",
        "1.1",
        "SkyWater sky130A PDK core (all libs.ref types + tt/ff/ss lib + libs.tech + SRAM)",
        core_install.to_str().ok_or("路径非 UTF-8")?,
    )?;
    println!("核心包: {:.2} GB", dir_size(&core_install)? as f64 / 1e9);

    // ── 2. 扩展包 ───────────────────────────────────────────
    for (pkg_name, vs) in EXTRA_PKGS {
        let inst = pkg_base
            .join(pkg_name)
            .join("files/usr/local/share/pdk/sky130A");
        if inst.exists() {
            fs::remove_dir_all(&inst).map_err(|e| e.to_string())?;
        }
        fs::create_dir_all(&inst).map_err(|e| e.to_string())?;

        // 收集核心包已用的 corner（排除）
        let mut keep: Vec<&str> = Vec::new();
        for v in *vs {
            if let Some(l) = core_libs_for(v) {
                keep.extend(l.iter().copied());
            }
        }

        for v in *vs {
            let slib = refs.join(v).join("lib");
            let dlib = inst.join("libs.ref").join(v).join("lib");
            fs::create_dir_all(&dlib).map_err(|e| e.to_string())?;
            if !slib.is_dir() {
                continue;
            }
            let mut files: Vec<String> = fs::read_dir(&slib)
                .map_err(|e| e.to_string())?
                .flatten()
                .map(|e| e.file_name().to_string_lossy().to_string())
                .collect();
            files.sort();
            for f in files {
                if !keep.contains(&f.as_str()) {
                    fs::copy(slib.join(&f), dlib.join(&f))
                        .map_err(|e| format!("复制 {f} 失败: {e}"))?;
                }
            }
        }
        let desc = format!(
            "SkyWater sky130A PDK extra liberty corners: {}",
            vs.join(", ")
        );
        write_metadata(
            &pkg_base.join(pkg_name),
            pkg_name,
            "1.0",
            &desc,
            inst.to_str().ok_or("路径非 UTF-8")?,
        )?;
        println!("{pkg_name}: {:.2} GB", dir_size(&inst)? as f64 / 1e9);
    }
    println!("完成");
    Ok(())
}
