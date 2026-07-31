// cli — 公共命令行辅助（零依赖手写参数解析）

/// 从参数迭代器取下一个值；缺失时报错。
pub fn next_val<'a, I>(it: &mut I, flag: &str) -> Result<String, String>
where
    I: Iterator<Item = &'a String>,
{
    it.next()
        .cloned()
        .ok_or_else(|| format!("参数 {flag} 缺少值"))
}
