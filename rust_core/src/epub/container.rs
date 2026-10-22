//! 解析 `META-INF/container.xml`，定位 OPF 文件路径。
//!
//! EPUB 规范：container.xml 里至少一个 `<rootfile full-path="..." media-type="application/oebps-package+xml"/>`

use std::io::Read;
use zip::ZipArchive;

pub fn locate_opf(archive: &mut ZipArchive<std::fs::File>) -> Result<String, String> {
    let mut f = archive
        .by_name("META-INF/container.xml")
        .map_err(|e| format!("no META-INF/container.xml: {}", e))?;
    let mut xml = String::new();
    f.read_to_string(&mut xml).map_err(|e| e.to_string())?;

    // 直接用正则/字符串提取，避免 roxmltree 依赖完整文档
    // （container.xml 是固定 schema，简单 substring 足够）
    let needle = "full-path=\"";
    let mut start = 0usize;
    while let Some(i) = xml[start..].find(needle) {
        let abs_i = start + i + needle.len();
        let Some(end) = xml[abs_i..].find('"') else {
            break;
        };
        let candidate = &xml[abs_i..abs_i + end];
        if candidate.ends_with(".opf") || candidate.ends_with(".OPF") {
            return Ok(candidate.to_string());
        }
        start = abs_i + end + 1;
    }

    // 兜底：直接找第一个 .opf 的 full-path
    Err(format!("no OPF rootfile found in container.xml"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::tempdir;
    use zip::{write::SimpleFileOptions, ZipWriter};

    fn make_zip() -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.epub");
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = ZipWriter::new(file);
        // META-INF/container.xml
        zip.start_file("META-INF/container.xml", SimpleFileOptions::default()).unwrap();
        zip.write_all(br#"<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>"#).unwrap();
        zip.finish().unwrap();
        (dir, path)
    }

    #[test]
    fn find_opf_path() {
        let (_dir, path) = make_zip();
        let file = std::fs::File::open(&path).unwrap();
        let mut archive = ZipArchive::new(file).unwrap();
        let opf = locate_opf(&mut archive).unwrap();
        assert_eq!(opf, "OEBPS/content.opf");
    }

    #[test]
    fn missing_container_fails() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("empty.epub");
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = ZipWriter::new(file);
        zip.finish().unwrap();
        let file = std::fs::File::open(&path).unwrap();
        let mut archive = ZipArchive::new(file).unwrap();
        assert!(locate_opf(&mut archive).is_err());
    }
}
