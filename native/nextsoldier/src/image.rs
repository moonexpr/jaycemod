//! A win64 image's C++ classes from its MSVC RTTI: server.dll exports no
//! symbols, but each class names itself in a type descriptor, and a vtable is
//! preceded by a pointer to its complete object locator. Works on a file's bytes
//! (the tests) and a mapped module's (the server), which differ only in where a
//! section starts.

use std::ops::Range;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Section {
    pub rva: usize,
    pub size: usize,
    /// Where it starts in the image's bytes.
    pub start: usize,
    pub executable: bool,
}

/// Why an image could not be read.
#[derive(Debug, PartialEq)]
pub enum ImageError {
    NotPe,
    NotWin64,
    NoClass(String),
}

pub struct Image<'a> {
    bytes: &'a [u8],
    /// What its absolute pointers are relative to.
    pub base: u64,
    sections: Vec<Section>,
}

fn u16_at(b: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(at..at + 2)?.try_into().ok()?))
}

fn u32_at(b: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(at..at + 4)?.try_into().ok()?))
}

fn u64_at(b: &[u8], at: usize) -> Option<u64> {
    Some(u64::from_le_bytes(b.get(at..at + 8)?.try_into().ok()?))
}

impl<'a> Image<'a> {
    pub fn new(bytes: &'a [u8], base: u64, sections: Vec<Section>) -> Self {
        Self {
            bytes,
            base,
            sections,
        }
    }

    /// Parses the headers of a PE32+ file (`mapped` None, its preferred base) or
    /// of a module mapped at `mapped`, whose sections sit at their RVAs.
    pub fn parse(bytes: &'a [u8], mapped: Option<u64>) -> Result<Self, ImageError> {
        let pe = u32_at(bytes, 0x3C).ok_or(ImageError::NotPe)? as usize;
        if bytes.get(pe..pe + 4) != Some(b"PE\0\0") {
            return Err(ImageError::NotPe);
        }
        if u16_at(bytes, pe + 24) != Some(0x20B) {
            return Err(ImageError::NotWin64);
        }
        let count = u16_at(bytes, pe + 6).ok_or(ImageError::NotPe)? as usize;
        let optional = u16_at(bytes, pe + 20).ok_or(ImageError::NotPe)? as usize;
        let preferred = u64_at(bytes, pe + 48).ok_or(ImageError::NotPe)?;
        let mut sections = Vec::with_capacity(count);
        for i in 0..count {
            let at = pe + 24 + optional + i * 40;
            let virtual_size = u32_at(bytes, at + 8).ok_or(ImageError::NotPe)? as usize;
            let rva = u32_at(bytes, at + 12).ok_or(ImageError::NotPe)? as usize;
            let raw_size = u32_at(bytes, at + 16).ok_or(ImageError::NotPe)? as usize;
            let raw = u32_at(bytes, at + 20).ok_or(ImageError::NotPe)? as usize;
            let flags = u32_at(bytes, at + 36).ok_or(ImageError::NotPe)?;
            sections.push(Section {
                rva,
                size: if mapped.is_some() {
                    virtual_size
                } else {
                    virtual_size.min(raw_size)
                },
                start: if mapped.is_some() { rva } else { raw },
                executable: flags & 0x2000_0000 != 0,
            });
        }
        Ok(Self::new(bytes, mapped.unwrap_or(preferred), sections))
    }

    fn at(&self, rva: usize) -> Option<usize> {
        let s = self
            .sections
            .iter()
            .find(|s| (s.rva..s.rva + s.size).contains(&rva))?;
        Some(s.start + rva - s.rva)
    }

    fn range(&self, s: &Section) -> Range<usize> {
        s.start..(s.start + s.size).min(self.bytes.len())
    }

    pub fn is_code(&self, rva: usize) -> bool {
        self.sections
            .iter()
            .any(|s| s.executable && (s.rva..s.rva + s.size).contains(&rva))
    }

    /// The vtables of the class whose decorated name is `name`
    /// (`.?AVCLuaNextBot@@`): (RVA, the offset in the object it sits at).
    pub fn vtables(&self, name: &str) -> Result<Vec<(usize, usize)>, ImageError> {
        let descriptor = self
            .descriptor(name)
            .ok_or_else(|| ImageError::NoClass(name.to_string()))?;
        let mut found = Vec::new();
        for s in self.sections.iter().filter(|s| !s.executable) {
            let bytes = &self.bytes[self.range(s)];
            for at in (0..bytes.len().saturating_sub(24)).step_by(4) {
                if u32_at(bytes, at) != Some(1) || u32_at(bytes, at + 12) != Some(descriptor as u32)
                {
                    continue;
                }
                // a locator names itself last: what tells it from any other data
                let own = s.rva + at;
                if u32_at(bytes, at + 20) != Some(own as u32) {
                    continue;
                }
                let offset = u32_at(bytes, at + 4).unwrap_or(0) as usize;
                if let Some(table) = self.pointer_to(own) {
                    found.push((table + 8, offset));
                }
            }
        }
        if found.is_empty() {
            return Err(ImageError::NoClass(name.to_string()));
        }
        found.sort_by_key(|&(_, offset)| offset);
        Ok(found)
    }

    fn descriptor(&self, name: &str) -> Option<usize> {
        let mut wanted = name.as_bytes().to_vec();
        wanted.push(0);
        for s in self.sections.iter().filter(|s| !s.executable) {
            let bytes = &self.bytes[self.range(s)];
            if let Some(at) = bytes.windows(wanted.len()).position(|w| w == wanted) {
                return Some(s.rva + at - 16);
            }
        }
        None
    }

    /// The first place in the image's data holding a pointer to `rva`.
    pub fn pointer_to(&self, rva: usize) -> Option<usize> {
        let value = self.base + rva as u64;
        for s in self.sections.iter().filter(|s| !s.executable) {
            let bytes = &self.bytes[self.range(s)];
            for at in (0..bytes.len().saturating_sub(8)).step_by(8) {
                if u64_at(bytes, at) == Some(value) {
                    return Some(s.rva + at);
                }
            }
        }
        None
    }

    /// The slots of the vtable at `rva`, as RVAs, up to the first not in code.
    pub fn slots(&self, rva: usize) -> Vec<usize> {
        let mut found = Vec::new();
        while let Some(value) = self
            .at(rva + 8 * found.len())
            .and_then(|at| u64_at(self.bytes, at))
        {
            let target = value.wrapping_sub(self.base) as usize;
            if !self.is_code(target) {
                break;
            }
            found.push(target);
        }
        found
    }

    /// The bytes at `rva`, for checking what a function does.
    pub fn code(&self, rva: usize, len: usize) -> Option<&[u8]> {
        let at = self.at(rva)?;
        self.bytes.get(at..at + len)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: u64 = 0x1_8000_0000;
    const NAME: &str = ".?AVWidget@@";

    /// .text at 0x1000, .rdata at 0x2000 holding a class: its descriptor, a
    /// locator at 0x2100, and a vtable of two code slots at 0x2208.
    fn widget() -> Vec<u8> {
        let mut b = vec![0u8; 0x3000];
        b[0x2010..0x2010 + NAME.len()].copy_from_slice(NAME.as_bytes());
        let locator = [1u32, 0x40, 0, 0x2000, 0, 0x2100];
        for (i, v) in locator.iter().enumerate() {
            b[0x2100 + 4 * i..0x2100 + 4 * i + 4].copy_from_slice(&v.to_le_bytes());
        }
        for (at, v) in [
            (0x2200, BASE + 0x2100),
            (0x2208, BASE + 0x1010),
            (0x2210, BASE + 0x1020),
        ] {
            b[at..at + 8].copy_from_slice(&v.to_le_bytes());
        }
        b
    }

    fn sections() -> Vec<Section> {
        vec![
            Section {
                rva: 0x1000,
                size: 0x1000,
                start: 0x1000,
                executable: true,
            },
            Section {
                rva: 0x2000,
                size: 0x1000,
                start: 0x2000,
                executable: false,
            },
        ]
    }

    #[test]
    fn a_class_is_found_by_its_name_with_its_vtable_and_slots() {
        let bytes = widget();
        let image = Image::new(&bytes, BASE, sections());
        assert_eq!(image.vtables(NAME).unwrap(), vec![(0x2208, 0x40)]);
        assert_eq!(
            image.slots(0x2208),
            vec![0x1010, 0x1020],
            "stops at the first not in code"
        );
    }

    #[test]
    fn a_class_it_does_not_hold_is_refused_by_name() {
        let bytes = widget();
        let image = Image::new(&bytes, BASE, sections());
        assert_eq!(
            image.vtables(".?AVGadget@@"),
            Err(ImageError::NoClass(".?AVGadget@@".into()))
        );
    }

    #[test]
    fn a_locator_must_name_itself() {
        let mut bytes = widget();
        bytes[0x2114..0x2118].copy_from_slice(&0x9999u32.to_le_bytes());
        let image = Image::new(&bytes, BASE, sections());
        assert!(image.vtables(NAME).is_err());
    }

    #[test]
    fn what_is_not_a_win64_pe_is_refused() {
        assert_eq!(
            Image::parse(&[0u8; 0x100], None).err(),
            Some(ImageError::NotPe)
        );
    }

    /// A section's zero-filled tail (a static like gEntList) exists only once mapped.
    #[test]
    fn a_mapped_section_runs_its_whole_virtual_size_and_a_files_only_what_it_stores() {
        let mut header = vec![0u8; 0x400];
        header[0x3C] = 0x80;
        header[0x80..0x84].copy_from_slice(b"PE\0\0");
        header[0x86] = 1; // one section
        header[0x94] = 0xF0; // the optional header's size
        header[0x98..0x9A].copy_from_slice(&0x20Bu16.to_le_bytes());
        let section = 0x80 + 24 + 0xF0;
        header[section + 8..section + 12].copy_from_slice(&0x3000u32.to_le_bytes()); // virtual size
        header[section + 12..section + 16].copy_from_slice(&0x1000u32.to_le_bytes()); // RVA
        header[section + 16..section + 20].copy_from_slice(&0x200u32.to_le_bytes()); // raw size
        header[section + 20..section + 24].copy_from_slice(&0x400u32.to_le_bytes()); // raw offset
        let file = Image::parse(&header, None).unwrap();
        assert_eq!(file.sections[0].size, 0x200);
        assert_eq!(file.sections[0].start, 0x400);
        let mapped = Image::parse(&header, Some(BASE)).unwrap();
        assert_eq!(mapped.sections[0].size, 0x3000);
        assert_eq!(mapped.sections[0].start, 0x1000);
    }

    /// The server's own binary, when this machine has it: what the layout was read from.
    #[test]
    fn the_servers_binary_has_the_classes_the_engine_binding_needs() {
        let Ok(home) = std::env::var("HOME") else {
            return;
        };
        let path = format!(
            "{home}/Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps/common/GarrysMod/garrysmod/bin/win64/server.dll"
        );
        let Ok(bytes) = std::fs::read(path) else {
            return;
        };
        let image = Image::parse(&bytes, None).unwrap();
        let action = image.vtables(crate::layout::ACTION_CLASS).unwrap();
        assert_eq!(image.slots(action[0].0).len(), crate::layout::ACTION_SLOTS);
        assert_eq!(image.slots(action[1].0).len(), crate::layout::QUERY_SLOTS);
        let intention = image.vtables(crate::layout::INTENTION_CLASS).unwrap();
        let first = image.slots(intention[0].0)[crate::layout::FIRST_CONTAINED];
        assert_eq!(
            image.code(first, 5),
            Some(&crate::layout::RETURNS_BEHAVIOR[..])
        );
        let bot = image.vtables(crate::layout::BOT_CLASS).unwrap();
        assert_eq!(bot[1].1, crate::layout::INEXTBOT_OFFSET);
        assert!(image.vtables(crate::layout::ENTITY_LIST_CLASS).is_ok());
        assert!(image.vtables(crate::layout::ROOT_CLASS).is_ok());
    }
}
