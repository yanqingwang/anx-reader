//! EPUB 解析内核。
//!
//! 整体思路：每次 API 调用独立打开 zip 文件，避免跨 FFI 持有 ZipArchive 句柄
//! （frb 不支持 opaque handle 的 Drop 自动释放）。每次打开的开销在秒级 EPUB
//! 上可接受，性能瓶颈不在 zip 解压，而在 Dart 层 XML 解析 —— 这正是本 Rust
//! 替换的收益点。

pub mod container;
pub mod opf;
pub mod sections;

use crate::models::*;
use std::io::Read;
use zip::ZipArchive;

/// 一个 EPUB 文档：持有 ZipArchive（打开一次，用完即 Drop）
pub struct EpubDoc {
    pub metadata: EpubMetadata,
    pub spine: Vec<SpineItem>,
    /// href -> 完整 XHTML 内容
    contents: Vec<(String, String)>,
}

impl EpubDoc {
    pub fn open(path: &str) -> Result<Self, String> {
        let file = std::fs::File::open(path).map_err(|e| format!("open: {}", e))?;
        let mut archive = ZipArchive::new(file).map_err(|e| format!("zip: {}", e))?;

        // 1. 读 META-INF/container.xml 找 OPF
        let opf_path = container::locate_opf(&mut archive)?;

        // 2. 读 OPF 拿 metadata + spine + manifest
        let opf_content = read_zip_string(&mut archive, &opf_path)?;
        let (metadata, _manifest, spine) = opf::parse_opf(&opf_content, &opf_path)?;

        // 3. 把 manifest 里所有 href 的 XHTML 章节读出来（预缓存，避免每次 section_paragraphs 都开 zip）
        let mut contents = Vec::new();
        for item in &spine {
            let resolved = resolve_href(&opf_path, &item.href);
            let Ok(mut f) = archive.by_name(&resolved) else {
                continue;
            };
            let mut buf = String::new();
            let _ = f.read_to_string(&mut buf);
            contents.push((item.href.clone(), buf));
        }

        Ok(EpubDoc {
            metadata,
            spine,
            contents,
        })
    }

    pub fn section_paragraphs(&self, section_href: &str) -> Result<Vec<String>, String> {
        let Some((_, html)) = self.contents.iter().find(|(h, _)| h == section_href) else {
            return Err(format!("section not found: {}", section_href));
        };
        Ok(sections::extract_paragraphs(html))
    }

    pub fn search(&self, query: &str) -> Result<Vec<SearchHit>, String> {
        let re = regex::Regex::new(&regex::escape(query))
            .map_err(|e| format!("regex: {}", e))?;
        let mut hits = Vec::new();
        for (href, html) in &self.contents {
            let paragraphs = sections::extract_paragraphs(html);
            for p in paragraphs {
                if let Some(m) = re.find(&p) {
                    let start = m.start();
                    let start_c = p.char_indices().nth(start).map(|(i, _)| i).unwrap_or(0);
                    let pre = &p[..start_c.min(p.len())];
                    let post = &p[m.end().min(p.len())..];
                    let snippet = format!(
                        "…{}…",
                        truncate(pre.chars().rev().collect(), 80)
                    );
                    let _ = post; // 用 pre 做左截断作为 snippet 核心
                    hits.push(SearchHit {
                        section_href: href.clone(),
                        offset: m.start(),
                        snippet: snippet,
                    });
                    if hits.len() > 50 {
                        return Ok(hits);
                    }
                }
            }
        }
        Ok(hits)
    }
}

fn truncate(s: String, max_chars: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    chars.into_iter().rev().take(max_chars).collect::<Vec<_>>().into_iter().rev().collect()
}

fn read_zip_string(archive: &mut ZipArchive<std::fs::File>, name: &str) -> Result<String, String> {
    let mut f = archive
        .by_name(name)
        .map_err(|e| format!("by_name {}: {}", name, e))?;
    let mut buf = String::new();
    f.read_to_string(&mut buf).map_err(|e| e.to_string())?;
    Ok(buf)
}

/// 把 OPF 相对路径里的 href 解析成 zip 内部绝对路径
///
/// 特殊处理 container.xml → 它永远在 META-INF/ 下，但它声明的 OPF full-path
/// 是 zip 根的绝对路径（如 `OEBPS/content.opf`），所以直接返回 href 即可。
fn resolve_href(opf_path: &str, href: &str) -> String {
    // container.xml 的 href 本身就是 zip 内部绝对路径
    if opf_path.ends_with("container.xml") {
        return href.to_string();
    }
    let slash = opf_path.rfind('/').map(|i| i + 1).unwrap_or(0);
    let dir = &opf_path[..slash];
    if dir.is_empty() {
        href.to_string()
    } else {
        format!("{}{}", dir, href)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_href_works() {
        assert_eq!(resolve_href("OEBPS/content.opf", "chapter1.xhtml"),
                   "OEBPS/chapter1.xhtml");
        assert_eq!(resolve_href("content.opf", "text/ch1.xhtml"),
                   "text/ch1.xhtml");
        assert_eq!(resolve_href("META-INF/container.xml", "OEBPS/content.opf"),
                   "OEBPS/content.opf");
    }
}
