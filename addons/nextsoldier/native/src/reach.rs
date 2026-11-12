//! What a soldier's head reaches in the engine with no Lua in between, read from the Lua
//! methods' own C functions, which are the binary's answer to where each thing is. The
//! virtual slots and the field are checked against their calls; the function behind
//! SetEyeAngles, which no vtable holds, is read from its.

use crate::image::Image;
use crate::layout::{ENTITY_TEAM, EYE_ANGLES, EYE_POSITION, IS_ALIVE, IS_PLAYER};

#[derive(Debug, PartialEq)]
pub struct Reach {
    /// CBasePlayer's, as an RVA: (this, const QAngle*).
    pub set_eye_angles: usize,
}

fn method(image: &Image, name: &str, within: usize) -> Result<Vec<u8>, String> {
    let rva = image
        .lua_method(name)
        .ok_or_else(|| format!("{name} is not among server.dll's Lua methods"))?;
    let code = image
        .code(rva, within)
        .ok_or_else(|| format!("{name}'s function is not in the image"))?;
    Ok(code.to_vec())
}

/// `call qword ptr [reg + slot * 8]`, whichever of rax to rbx or r8 to r11 it goes through.
fn calls_slot(code: &[u8], slot: usize) -> bool {
    let displacement = ((slot * 8) as u32).to_le_bytes();
    code.windows(6)
        .any(|w| w[0] == 0xFF && (0x90..=0x93).contains(&w[1]) && w[2..6] == displacement)
}

fn needs(code: &[u8], name: &str, slot: usize) -> Result<(), String> {
    if calls_slot(code, slot) {
        Ok(())
    } else {
        Err(format!("{name} no longer calls virtual slot {slot}"))
    }
}

/// Where the nth relative call in code lands, as an RVA, from the code's own RVA.
fn nth_call(code: &[u8], from: usize, nth: usize) -> Option<usize> {
    let mut calls = code.windows(5).enumerate().filter(|(_, w)| w[0] == 0xE8);
    let (at, w) = calls.nth(nth)?;
    let relative = i32::from_le_bytes([w[1], w[2], w[3], w[4]]);
    Some((from as i64 + at as i64 + 5 + relative as i64) as usize)
}

const GLUE_BYTES: usize = 200;
/// What the field's getter is: `mov eax, dword ptr [rcx + field]; ret`.
const GET_TEAM: [u8; 7] = [0x8B, 0x81, 0xA4, 0x02, 0x00, 0x00, 0xC3];

pub fn read(image: &Image) -> Result<Reach, String> {
    let eye_pos = method(image, "EyePos", GLUE_BYTES)?;
    needs(&eye_pos, "EyePos", EYE_POSITION)?;
    let eye_angles = method(image, "EyeAngles", GLUE_BYTES)?;
    needs(&eye_angles, "EyeAngles", EYE_ANGLES)?;
    let alive = method(image, "Alive", GLUE_BYTES)?;
    needs(&alive, "Alive", IS_ALIVE)?;
    let team_rva = image
        .lua_method("Team")
        .ok_or("Team is not among server.dll's Lua methods")?;
    let team = method(image, "Team", GLUE_BYTES)?;
    let getter = nth_call(&team, team_rva, 1).ok_or("Team calls nothing")?;
    if image.code(getter, GET_TEAM.len()) != Some(&GET_TEAM[..]) {
        return Err(format!(
            "Team no longer reads its field at {ENTITY_TEAM:#x}"
        ));
    }
    let set_rva = image
        .lua_method("SetEyeAngles")
        .ok_or("SetEyeAngles is not among server.dll's Lua methods")?;
    let set = method(image, "SetEyeAngles", GLUE_BYTES)?;
    needs(&set, "SetEyeAngles", IS_PLAYER)?;
    // its own helpers come first: the player, then the angle, then the setter
    let set_eye_angles = nth_call(&set, set_rva, 2).ok_or("SetEyeAngles calls nothing")?;
    if !image.is_code(set_eye_angles) {
        return Err("SetEyeAngles's call lands outside code".into());
    }
    Ok(Reach { set_eye_angles })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_image_without_the_methods_is_refused_by_name() {
        let image = Image::new(&[], 0x1_8000_0000, vec![]);
        let why = read(&image).unwrap_err();
        assert!(why.contains("EyePos"), "{why}");
    }

    #[test]
    fn the_servers_binary_has_what_a_head_reaches() {
        let Ok(home) = std::env::var("HOME") else {
            return;
        };
        let path = format!(
            "{home}/Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps/common/GarrysModServer/garrysmod/bin/win64/server.dll"
        );
        let Ok(bytes) = std::fs::read(path) else {
            return;
        };
        let image = Image::parse(&bytes, None).unwrap();
        let reach = read(&image).unwrap();
        assert_eq!(
            reach.set_eye_angles, 0x3F_8390,
            "the build these were read from"
        );
    }
}
