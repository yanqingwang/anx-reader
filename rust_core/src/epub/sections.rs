//! 从 XHTML 章节里提取段落文本。
//!
//! EPUB 的章节文件是 XHTML（application/xhtml+xml），段落通常在 `<p>` 或 `<h1-6>`
//! 里。我们只需要纯文本，用于：
//! - 章节正文渲染（WebView JS 侧还会做一遍 DOM，但 Rust 侧先把段落拆好）
//! - 搜索索引（全文搜索必须基于纯文本）
//!
//! 策略：用 roxmltree 把整棵文档树解析出来，然后对所有 `<p>/<h1>/<h2>/<h3>/<h4>/<h5>/<h6>/<li>`
//! 节点收集其后代文本（<br> 保留为换行），trim 后非空的就是段落。
//! 这样做比正则/字符串切片鲁棒得多，且 epub.js 最终也是这么干的。

use roxmltree::Document;

pub fn extract_paragraphs(xhtml: &str) -> Vec<String> {
    let doc = match Document::parse(xhtml) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("extract_paragraphs: xml parse failed: {}", e);
            return Vec::new();
        }
    };
    let root = doc.root_element(); // 真正的根元素（html），跳过虚拟 Root
    let mut out = Vec::new();
    collect_paragraphs(root, &mut out);
    out
}

fn collect_paragraphs(node: roxmltree::Node<'_, '_>, out: &mut Vec<String>) {
    if !node.is_element() {
        return;
    }
    let name = node.tag_name().name();
    if is_paragraph_tag(name) {
        let text = node_descendants_text(node);
        let cleaned = text.trim();
        if !cleaned.is_empty() {
            out.push(cleaned.to_string());
        }
        return; // 不递归进去（子元素的段落标签不会再被单独抓，因为 roxmltree 是树结构会走到它们 — 但我们已经返回，直接让父递归处理）
    }
    for child in node.children() {
        collect_paragraphs(child, out);
    }
}

fn is_paragraph_tag(name: &str) -> bool {
    matches!(name, "p" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "li")
}

fn node_descendants_text(node: roxmltree::Node<'_, '_>) -> String {
    let mut buf = String::new();
    walk_text(node, &mut buf, true);
    buf
}

fn walk_text(node: roxmltree::Node<'_, '_>, buf: &mut String, br_as_newline: bool) {
    for child in node.children() {
        if child.is_text() {
            let t = child.text().unwrap_or("");
            // 把连续空白折叠成一个空格
            let trimmed = t.split_whitespace().collect::<Vec<_>>().join(" ");
            if !trimmed.is_empty() {
                if !buf.is_empty() && !buf.ends_with(' ') && !buf.ends_with('\n') {
                    buf.push(' ');
                }
                buf.push_str(&trimmed);
            }
        } else if child.is_element() {
            let tag = child.tag_name().name();
            if tag == "br" && br_as_newline {
                buf.push('\n');
            } else if tag == "img" {
                // 忽略 <img>
                continue;
            } else {
                walk_text(child, buf, br_as_newline);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const XHTML_FIXTURE: &str = r#"<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<body>
<h1>第一章 开始</h1>
<p>这是<b>第一段</b>，包含<i>粗体斜体</i>。</p>
<p class="note">
  第二段跨<br/>换行。
</p>
<div><p>嵌套段落也能抓。</p></div>
<ul><li>列表项一</li><li>列表项二</li></ul>
<p>  多余   空白  会  被  折叠。  </p>
<script>console.log("ignore me");</script>
</body>
</html>"#;

    #[test]
    fn extract_paragraphs_normal() {
        // fixture: h1 + 4 p (含嵌套 p, 带 b/i 加粗、br 换行、空白折叠) + 2 li = 7 段
        let xhtml = r#"<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<body>
<h1>第一章 开始</h1>
<p>这是<b>第一段</b>，包含<i>粗体斜体</i>。</p>
<p class="note">
  第二段跨<br/>换行。
</p>
<div><p>嵌套段落也能抓。</p></div>
<ul><li>列表项一</li><li>列表项二</li></ul>
<p>  多余   空白  会  被  折叠。  </p>
<script>console.log("ignore me");</script>
</body>
</html>"#;
        let p = extract_paragraphs(xhtml);
        eprintln!("paragraphs got {:?}", p);
        assert_eq!(p.len(), 7, "got: {:?}", p);
        assert!(p.iter().any(|x| x.contains("第一段")));
        assert!(p.iter().any(|x| x.contains("列表项一")));
        assert!(p.iter().all(|x| !x.contains("<"))); // 无 HTML 残留
        assert!(p.iter().all(|x| !x.is_empty()));
    }

    #[test]
    fn empty_returns_empty() {
        let p = extract_paragraphs("");
        assert!(p.is_empty());
    }
}
