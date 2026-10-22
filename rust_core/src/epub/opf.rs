//! OPF (Open Packaging Format) 解析。
//!
//! OPF 结构（epub3）：
//! ```xml
//! <package version="3.0" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">
//!   <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
//!     <dc:title>...</dc:title>
//!     <dc:creator>...</dc:creator>
//!     <dc:description>...</dc:description>
//!     <dc:language>...</dc:language>
//!     <meta name="cover" content="cover-image-id"/>
//!   </metadata>
//!   <manifest>
//!     <item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>
//!     <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
//!   </manifest>
//!   <spine>
//!     <itemref idref="ch1"/>
//!   </spine>
//! </package>
//! ```

use crate::models::*;
use roxmltree::Document;

pub fn parse_opf(
    xml: &str,
    _opf_path: &str,
) -> Result<(EpubMetadata, Vec<ManifestItem>, Vec<SpineItem>), String> {
    let doc = Document::parse(xml).map_err(|e| format!("xml parse: {}", e))?;
    let root = doc.root_element();

    let ns_opf = root.lookup_namespace_uri(Some("opf")).or_else(|| root.default_namespace());
    let _ = ns_opf; // 预留：后续用于更严格的 OPF 命名空间校验
    let ns_dc = "http://purl.org/dc/elements/1.1/";

    // metadata
    let mut metadata = EpubMetadata::default();
    let metadata_elem = root
        .children()
        .find(|n| n.is_element() && n.tag_name().name() == "metadata")
        .ok_or_else(|| "no <metadata>".to_string())?;

    for child in metadata_elem.children().filter(|n| n.is_element()) {
        let tag = child.tag_name();
        if tag.namespace() == Some(ns_dc) {
            match tag.name() {
                "title" => metadata.title = child.text().unwrap_or("").to_string(),
                "creator" => metadata.author = child.text().unwrap_or("").to_string(),
                "description" => metadata.description = child.text().unwrap_or("").to_string(),
                "language" => metadata.language = child.text().unwrap_or("").to_string(),
                _ => {}
            }
        }
        if tag.name() == "meta" {
            if let (Some(name), Some(content)) = (
                child.attribute("name"),
                child.attribute("content"),
            ) {
                if name == "cover" {
                    // cover 是 manifest item 的 id
                    metadata.cover_path = Some(content.to_string());
                }
            }
        }
    }

    metadata.opf_path = _opf_path.to_string();

    // manifest
    let manifest_elem = root
        .children()
        .find(|n| n.is_element() && n.tag_name().name() == "manifest")
        .ok_or_else(|| "no <manifest>".to_string())?;
    let mut manifest = Vec::new();
    let mut cover_id: Option<String> = None;
    if let Some(cov) = &metadata.cover_path {
        cover_id = Some(cov.clone());
        // 把 cover_path 从 id 改成 zip 内部 href（manifest 里找）
        metadata.cover_path = None;
    }
    for item in manifest_elem.children().filter(|n| n.is_element()) {
        if item.tag_name().name() != "item" {
            continue;
        }
        let (Some(id), Some(href), Some(mt)) = (
            item.attribute("id"),
            item.attribute("href"),
            item.attribute("media-type"),
        ) else {
            continue;
        };
        // 如果这个 item 是封面，记录 zip 内部 path
        if cover_id.as_deref() == Some(id) && mt.starts_with("image/") {
            metadata.cover_path = Some(href.to_string());
        }
        manifest.push(ManifestItem {
            id: id.to_string(),
            href: href.to_string(),
            media_type: mt.to_string(),
        });
    }

    // spine
    let spine_elem = root
        .children()
        .find(|n| n.is_element() && n.tag_name().name() == "spine")
        .ok_or_else(|| "no <spine>".to_string())?;
    let mut spine = Vec::new();
    for itemref in spine_elem.children().filter(|n| n.is_element()) {
        if itemref.tag_name().name() != "itemref" {
            continue;
        }
        let Some(idref) = itemref.attribute("idref") else {
            continue;
        };
        let linear = itemref.attribute("linear").map(|v| v != "no").unwrap_or(true);
        // 从 manifest 里找 href
        let href = manifest
            .iter()
            .find(|m| m.id == idref)
            .map(|m| m.href.clone())
            .unwrap_or_default();
        spine.push(SpineItem {
            idref: idref.to_string(),
            href,
            linear,
        });
    }

    let _ = ns_opf; // 只是检查时存下来用

    Ok((metadata, manifest, spine))
}

#[derive(Debug, Clone)]
pub struct ManifestItem {
    pub id: String,
    pub href: String,
    pub media_type: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    const OPF_FIXTURE: &str = r#"<?xml version="1.0"?>
<package version="3.0" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书籍</dc:title>
    <dc:creator>张三</dc:creator>
    <dc:description>一本小测试书</dc:description>
    <dc:language>zh-CN</dc:language>
    <meta name="cover" content="ci"/>
  </metadata>
  <manifest>
    <item id="ci" href="images/cover.jpg" media-type="image/jpeg"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2" linear="yes"/>
    <itemref idref="toc" linear="no"/>
  </spine>
</package>"#;

    #[test]
    fn parse_metadata() {
        let (meta, _man, _spine) = parse_opf(OPF_FIXTURE, "OEBPS/content.opf").unwrap();
        assert_eq!(meta.title, "测试书籍");
        assert_eq!(meta.author, "张三");
        assert_eq!(meta.language, "zh-CN");
        assert_eq!(meta.description, "一本小测试书");
        assert_eq!(meta.cover_path.as_deref(), Some("images/cover.jpg"));
        assert_eq!(meta.opf_path, "OEBPS/content.opf");
    }

    #[test]
    fn parse_spine() {
        let (_m, _man, spine) = parse_opf(OPF_FIXTURE, "OEBPS/content.opf").unwrap();
        assert_eq!(spine.len(), 3);
        assert_eq!(spine[0].idref, "ch1");
        assert_eq!(spine[0].href, "text/ch1.xhtml");
        assert_eq!(spine[2].linear, false);
    }
}
