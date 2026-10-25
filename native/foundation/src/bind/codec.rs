//! file.buffer and encoding.utf16, cursor, keyvalues, consolecfg, cvarfile
//! and gma, native: the Lua twins' contracts (foundation/file/,
//! foundation/encoding/), byte for byte. The cursor's patterns are Lua's
//! own (string.find), as the Lua twin matches them.

use super::slots::fresh_environment;
use super::util::{boolean, each_item, env_field, nothing, number, number_at};
use crate::lua::{api, raise_where, string_at, tostring, CFunction, GLOBALSINDEX, L, TNIL, TSTRING, TTABLE};
use crate::module;
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

extern "C" {
    fn frexp(x: f64, exponent: *mut c_int) -> f64;
    fn ldexp(x: f64, exponent: c_int) -> f64;
}

/// Pushes `bytes` as a Lua string; one result.
unsafe fn bytes(l: L, data: &[u8]) -> c_int {
    (api().pushlstring)(l, data.as_ptr().cast(), data.len());
    1
}

/// The string at `index` (a number reads as Lua's tostring of it), or a
/// Lua error naming what was wanted.
unsafe fn text_at<'a>(l: L, index: c_int, what: &str) -> &'a [u8] {
    let api = api();
    if (api.type_of)(l, index) == crate::lua::TNUMBER {
        let mut len = 0usize;
        let s = (api.tolstring)(l, index, &mut len);
        return std::slice::from_raw_parts(s.cast::<u8>(), len);
    }
    match string_at(l, index) {
        Some(s) => s,
        None => raise_where(l, format!("{what} is a string")),
    }
}

// file.buffer: writing ------------------------------------------------------

/// Lua's floored n % m.
fn modulo(n: f64, m: f64) -> f64 {
    n - (n / m).floor() * m
}

fn byte_of(n: f64) -> u8 {
    n as i64 as u8
}

fn int16(n: f64) -> [u8; 2] {
    let n = modulo(n, 65536.0);
    [byte_of(modulo(n, 256.0)), byte_of(modulo((n / 256.0).floor(), 256.0))]
}

fn int32(n: f64) -> [u8; 4] {
    let n = modulo(n, 4_294_967_296.0);
    [
        byte_of(modulo(n, 256.0)),
        byte_of(modulo((n / 256.0).floor(), 256.0)),
        byte_of(modulo((n / 65536.0).floor(), 256.0)),
        byte_of(modulo((n / 16_777_216.0).floor(), 256.0)),
    ]
}

const MANTISSA: f64 = 8_388_608.0; // 2^23

/// The Lua twin's Float32: frexp, round half up, the carry into the next
/// power of two.
fn float32(x: f64) -> [u8; 4] {
    if x == 0.0 {
        return [0; 4];
    }
    let (sign, x) = if x < 0.0 { (128.0, -x) } else { (0.0, x) };
    let mut e: c_int = 0;
    // SAFETY: frexp writes the exponent through the pointer it is given.
    let m = unsafe { frexp(x, &mut e) };
    let mut exponent = (e + 126) as f64;
    let mut mantissa = if exponent <= 0.0 {
        // SAFETY: plain libm call.
        let scaled = unsafe { ldexp(m, 23 + exponent as c_int) };
        exponent = 0.0;
        (scaled + 0.5).floor()
    } else {
        ((m * 2.0 - 1.0) * MANTISSA + 0.5).floor()
    };
    if mantissa == MANTISSA {
        mantissa = 0.0;
        exponent += 1.0;
    }
    [
        byte_of(modulo(mantissa, 256.0)),
        byte_of(modulo((mantissa / 256.0).floor(), 256.0)),
        byte_of(modulo(exponent, 2.0) * 128.0 + modulo((mantissa / 65536.0).floor(), 128.0)),
        byte_of(sign + (exponent / 2.0).floor()),
    ]
}

fn utf8(code: f64, out: &mut Vec<u8>) {
    let code = code as u32;
    if code < 0x80 {
        out.push(code as u8);
    } else if code < 0x800 {
        out.extend([0xC0 + (code / 0x40) as u8, 0x80 + (code % 0x40) as u8]);
    } else if code < 0x10000 {
        out.extend([0xE0 + (code / 0x1000) as u8, 0x80 + (code / 0x40 % 0x40) as u8, 0x80 + (code % 0x40) as u8]);
    } else {
        out.extend([
            0xF0 + (code / 0x40000) as u8,
            0x80 + (code / 0x1000 % 0x40) as u8,
            0x80 + (code / 0x40 % 0x40) as u8,
            0x80 + (code % 0x40) as u8,
        ]);
    }
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 == 1 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

/// The varint of n, or the Lua twin's refusal.
unsafe fn varint(l: L, index: c_int, out: &mut Vec<u8>) {
    let n = number_at(l, index).filter(|n| *n >= 0.0 && n.fract() == 0.0);
    let Some(mut n) = n else {
        let given = tostring(l, index);
        raise_where(l, format!("a varint is a whole number >= 0, not {given}"));
    };
    loop {
        let group = modulo(n, 128.0);
        n = (n / 128.0).floor();
        out.push(if n > 0.0 { group + 128.0 } else { group } as u8);
        if n == 0.0 {
            break;
        }
    }
}

unsafe fn byte_value(l: L, index: c_int) -> u8 {
    let n = (api().checknumber)(l, index);
    if !(0.0..256.0).contains(&n) {
        raise_where(l, "bad argument to 'char' (invalid value)".into());
    }
    n as u8
}

unsafe extern "C-unwind" fn buffer_byte(l: L) -> c_int {
    let b = byte_value(l, 1);
    bytes(l, &[b])
}

unsafe extern "C-unwind" fn buffer_int16(l: L) -> c_int {
    bytes(l, &int16((api().checknumber)(l, 1)))
}

unsafe extern "C-unwind" fn buffer_int32(l: L) -> c_int {
    bytes(l, &int32((api().checknumber)(l, 1)))
}

unsafe extern "C-unwind" fn buffer_float32(l: L) -> c_int {
    bytes(l, &float32((api().checknumber)(l, 1)))
}

unsafe extern "C-unwind" fn buffer_varint(l: L) -> c_int {
    let mut out = Vec::new();
    varint(l, 1, &mut out);
    let pushed = bytes(l, &out);
    drop(out);
    pushed
}

unsafe extern "C-unwind" fn buffer_string(l: L) -> c_int {
    let s = text_at(l, 1, "a buffer's string");
    let mut out = Vec::with_capacity(s.len() + 5);
    (api().pushnumber)(l, s.len() as f64);
    varint(l, -1, &mut out);
    out.extend_from_slice(s);
    let pushed = bytes(l, &out);
    drop(out);
    pushed
}

unsafe extern "C-unwind" fn buffer_utf8(l: L) -> c_int {
    let mut out = Vec::with_capacity(4);
    utf8((api().checknumber)(l, 1), &mut out);
    let pushed = bytes(l, &out);
    drop(out);
    pushed
}

unsafe extern "C-unwind" fn buffer_crc32(l: L) -> c_int {
    let s = text_at(l, 1, "Crc32's argument");
    number(l, crc32(s) as f64)
}

// file.buffer: the writer ---------------------------------------------------

#[derive(Default)]
pub struct Writer {
    data: Vec<u8>,
}

impl Native for Writer {
    const NAME: &'static CStr = c"foundation.file.buffer.writer";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Byte", writer_byte),
        (c"Int16", writer_int16),
        (c"Int32", writer_int32),
        (c"Float32", writer_float32),
        (c"Varint", writer_varint),
        (c"String", writer_string),
        (c"Bytes", writer_bytes),
        (c"Size", writer_size),
    ];
}

unsafe extern "C-unwind" fn buffer_writer(l: L) -> c_int {
    userdata::push(l, Writer::default());
    1
}

unsafe extern "C-unwind" fn writer_byte(l: L) -> c_int {
    let b = byte_value(l, 2);
    userdata::check::<Writer>(l, 1).data.push(b);
    0
}

unsafe extern "C-unwind" fn writer_int16(l: L) -> c_int {
    let b = int16((api().checknumber)(l, 2));
    userdata::check::<Writer>(l, 1).data.extend(b);
    0
}

unsafe extern "C-unwind" fn writer_int32(l: L) -> c_int {
    let b = int32((api().checknumber)(l, 2));
    userdata::check::<Writer>(l, 1).data.extend(b);
    0
}

unsafe extern "C-unwind" fn writer_float32(l: L) -> c_int {
    let b = float32((api().checknumber)(l, 2));
    userdata::check::<Writer>(l, 1).data.extend(b);
    0
}

unsafe extern "C-unwind" fn writer_varint(l: L) -> c_int {
    let w = userdata::check::<Writer>(l, 1);
    varint(l, 2, &mut w.data);
    0
}

unsafe extern "C-unwind" fn writer_string(l: L) -> c_int {
    let s = text_at(l, 2, "a buffer's string");
    let w = userdata::check::<Writer>(l, 1);
    (api().pushnumber)(l, s.len() as f64);
    varint(l, -1, &mut w.data);
    w.data.extend_from_slice(s);
    0
}

unsafe extern "C-unwind" fn writer_bytes(l: L) -> c_int {
    let w = userdata::check::<Writer>(l, 1);
    bytes(l, &w.data)
}

unsafe extern "C-unwind" fn writer_size(l: L) -> c_int {
    number(l, userdata::check::<Writer>(l, 1).data.len() as f64)
}

// file.buffer: the reader ---------------------------------------------------

pub struct Reader {
    data: Vec<u8>,
    at: usize,
}

impl Native for Reader {
    const NAME: &'static CStr = c"foundation.file.buffer.reader";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Byte", reader_byte),
        (c"UInt16", reader_uint16),
        (c"Int16", reader_int16),
        (c"Int32", reader_int32),
        (c"Float32", reader_float32),
        (c"Varint", reader_varint),
        (c"String", reader_string),
        (c"Consumed", reader_consumed),
    ];
}

impl Reader {
    /// The next n bytes, or None past the end (the reader moves on anyway).
    fn take(&mut self, n: usize) -> Option<&[u8]> {
        let start = self.at;
        self.at += n;
        self.data.get(start..start + n)
    }
}

unsafe extern "C-unwind" fn buffer_reader(l: L) -> c_int {
    let data = text_at(l, 1, "a reader's data").to_vec();
    userdata::push(l, Reader { data, at: 0 });
    1
}

unsafe fn short(l: L) -> ! {
    raise_where(l, "the reader ran past the end of its data".into())
}

unsafe extern "C-unwind" fn reader_byte(l: L) -> c_int {
    match userdata::check::<Reader>(l, 1).take(1) {
        Some(b) => number(l, b[0] as f64),
        None => nothing(l),
    }
}

unsafe fn uint16(l: L) -> f64 {
    match userdata::check::<Reader>(l, 1).take(2) {
        Some(b) => b[0] as f64 + b[1] as f64 * 256.0,
        None => short(l),
    }
}

unsafe extern "C-unwind" fn reader_uint16(l: L) -> c_int {
    number(l, uint16(l))
}

unsafe extern "C-unwind" fn reader_int16(l: L) -> c_int {
    let n = uint16(l);
    number(l, if n >= 32768.0 { n - 65536.0 } else { n })
}

unsafe extern "C-unwind" fn reader_int32(l: L) -> c_int {
    let Some(b) = userdata::check::<Reader>(l, 1).take(4).map(|b| [b[0], b[1], b[2], b[3]]) else { short(l) };
    let n = b[0] as f64 + b[1] as f64 * 256.0 + b[2] as f64 * 65536.0 + b[3] as f64 * 16_777_216.0;
    number(l, if n >= 2_147_483_648.0 { n - 4_294_967_296.0 } else { n })
}

unsafe extern "C-unwind" fn reader_float32(l: L) -> c_int {
    let Some([a, b, c, d]) = userdata::check::<Reader>(l, 1).take(4).map(|b| [b[0], b[1], b[2], b[3]]) else { short(l) };
    let sign = if d >= 128 { -1.0 } else { 1.0 };
    let exponent = (d % 128) as c_int * 2 + (c / 128) as c_int;
    let mantissa = (c % 128) as f64 * 65536.0 + b as f64 * 256.0 + a as f64;
    let value = if exponent == 0 {
        if mantissa == 0.0 {
            0.0
        } else {
            sign * ldexp(mantissa, -149)
        }
    } else if exponent == 255 {
        sign * f64::INFINITY
    } else {
        sign * ldexp(mantissa + MANTISSA, exponent - 150)
    };
    number(l, value)
}

unsafe fn read_varint(l: L) -> f64 {
    let r = userdata::check::<Reader>(l, 1);
    let (mut n, mut scale) = (0.0, 1.0);
    loop {
        let Some(&b) = r.take(1).and_then(|b| b.first()) else { short(l) };
        n += (b % 128) as f64 * scale;
        scale *= 128.0;
        if b < 128 {
            return n;
        }
    }
}

unsafe extern "C-unwind" fn reader_varint(l: L) -> c_int {
    number(l, read_varint(l))
}

unsafe extern "C-unwind" fn reader_string(l: L) -> c_int {
    let length = read_varint(l) as usize;
    let r = userdata::check::<Reader>(l, 1);
    let start = r.at.min(r.data.len());
    let end = (r.at + length).min(r.data.len());
    r.at += length;
    bytes(l, &r.data[start..end])
}

unsafe extern "C-unwind" fn reader_consumed(l: L) -> c_int {
    number(l, userdata::check::<Reader>(l, 1).at as f64)
}

// encoding.utf16 -------------------------------------------------------------

unsafe extern "C-unwind" fn utf16_decode(l: L) -> c_int {
    let raw = text_at(l, 1, "UTF-16 text");
    let mut out = Vec::with_capacity(raw.len() / 2);
    let mut i = 0;
    while i + 1 < raw.len() {
        let mut unit = raw[i] as u32 + raw[i + 1] as u32 * 0x100;
        i += 2;
        if (0xD800..0xDC00).contains(&unit) && i + 1 < raw.len() {
            let low = raw[i] as u32 + raw[i + 1] as u32 * 0x100;
            unit = (0x10000 + (unit - 0xD800) * 0x400).wrapping_add(low).wrapping_sub(0xDC00);
            i += 2;
        }
        if unit != 0xFEFF {
            utf8(unit as f64, &mut out);
        }
    }
    let pushed = bytes(l, &out);
    drop(out);
    pushed
}

// encoding.cursor -------------------------------------------------------------

/// A cursor: env.text, the position (0-based) and the saved ones.
pub struct Cursor {
    at: usize,
    saved: Vec<usize>,
    length: usize,
}

impl Native for Cursor {
    const NAME: &'static CStr = c"foundation.encoding.cursor";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Literal", cursor_literal),
        (c"Pattern", cursor_pattern),
        (c"Peek", cursor_peek),
        (c"Whitespace", cursor_whitespace),
        (c"Save", cursor_save),
        (c"Restore", cursor_restore),
        (c"Commit", cursor_commit),
        (c"Position", cursor_position),
        (c"AtEnd", cursor_at_end),
        (c"Rest", cursor_rest),
    ];
}

unsafe extern "C-unwind" fn cursor_new(l: L) -> c_int {
    let length = text_at(l, 1, "a cursor's text").len();
    userdata::push(l, Cursor { at: 0, saved: Vec::new(), length });
    fresh_environment(l, -1);
    let api = api();
    (api.getfenv)(l, -1);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"text".as_ptr());
    (api.settop)(l, -2);
    1
}

/// The cursor's text (pushed: it stays on the stack while borrowed).
unsafe fn cursor_text<'a>(l: L) -> &'a [u8] {
    env_field(l, 1, c"text");
    string_at(l, -1).unwrap_or_default()
}

unsafe extern "C-unwind" fn cursor_literal(l: L) -> c_int {
    let s = text_at(l, 2, "a literal").to_vec();
    let ignore_case = (api().toboolean)(l, 3) != 0;
    let text = cursor_text(l);
    let c = userdata::check::<Cursor>(l, 1);
    let end = (c.at + s.len()).min(text.len());
    let here = &text[c.at.min(text.len())..end];
    if here == s.as_slice() || (ignore_case && here.eq_ignore_ascii_case(&s)) {
        let start = c.at;
        c.at += s.len();
        drop(s);
        return bytes(l, &text[start..end]);
    }
    drop(s);
    nothing(l)
}

/// Runs string.find(text, "^" .. p, at): the number of results it left.
unsafe fn find_here(l: L, pattern: c_int, at: usize, base: c_int) -> c_int {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"string".as_ptr());
    (api.getfield)(l, -1, c"find".as_ptr());
    (api.remove)(l, -2);
    env_field(l, 1, c"text");
    crate::lua::push_str(l, "^");
    (api.pushvalue)(l, pattern);
    (api.concat)(l, 2);
    (api.pushnumber)(l, (at + 1) as f64);
    (api.call)(l, 3, -1);
    (api.gettop)(l) - base
}

/// Pattern and Peek: the captures, or the whole match, or nil.
unsafe fn matched(l: L, moves: bool) -> c_int {
    let api = api();
    (api.checktype)(l, 2, TSTRING);
    (api.settop)(l, 2);
    let at = userdata::check::<Cursor>(l, 1).at;
    let n = find_here(l, 2, at, 2);
    if n == 0 || (api.type_of)(l, 3) == TNIL {
        return nothing(l);
    }
    let last = (api.tonumber)(l, 4) as usize;
    if moves {
        userdata::check::<Cursor>(l, 1).at = last;
    }
    if n == 2 {
        let first = (api.tonumber)(l, 3) as usize;
        env_field(l, 1, c"text");
        let text = string_at(l, -1).unwrap_or_default();
        return bytes(l, &text[first - 1..last]);
    }
    n - 2
}

unsafe extern "C-unwind" fn cursor_pattern(l: L) -> c_int {
    matched(l, true)
}

unsafe extern "C-unwind" fn cursor_peek(l: L) -> c_int {
    matched(l, false)
}

unsafe extern "C-unwind" fn cursor_whitespace(l: L) -> c_int {
    let text = cursor_text(l);
    let c = userdata::check::<Cursor>(l, 1);
    let start = c.at;
    let mut end = start;
    while end < text.len() && matches!(text[end], b' ' | b'\t' | b'\r' | b'\n') {
        end += 1;
    }
    if end == start {
        return nothing(l);
    }
    c.at = end;
    bytes(l, &text[start..end])
}

unsafe extern "C-unwind" fn cursor_save(l: L) -> c_int {
    let c = userdata::check::<Cursor>(l, 1);
    c.saved.push(c.at);
    0
}

unsafe extern "C-unwind" fn cursor_restore(l: L) -> c_int {
    let c = userdata::check::<Cursor>(l, 1);
    if let Some(at) = c.saved.pop() {
        c.at = at;
    }
    0
}

unsafe extern "C-unwind" fn cursor_commit(l: L) -> c_int {
    userdata::check::<Cursor>(l, 1).saved.pop();
    0
}

unsafe extern "C-unwind" fn cursor_position(l: L) -> c_int {
    number(l, (userdata::check::<Cursor>(l, 1).at + 1) as f64)
}

unsafe extern "C-unwind" fn cursor_at_end(l: L) -> c_int {
    let c = userdata::check::<Cursor>(l, 1);
    boolean(l, c.at >= c.length)
}

unsafe extern "C-unwind" fn cursor_rest(l: L) -> c_int {
    let text = cursor_text(l);
    let at = userdata::check::<Cursor>(l, 1).at.min(text.len());
    bytes(l, &text[at..])
}

// encoding.keyvalues ----------------------------------------------------------

enum Item {
    Open,
    Close,
    Text(Vec<u8>),
}

/// The next item from position i, and the position after; None at the end.
fn next_item(text: &[u8], mut i: usize) -> (Option<Item>, usize) {
    let length = text.len();
    while i < length {
        let c = text[i];
        if c == b'/' && text.get(i + 1) == Some(&b'/') {
            while i < length && text[i] != b'\n' {
                i += 1;
            }
        } else if c <= 32 {
            i += 1;
        } else {
            break;
        }
    }
    if i >= length {
        return (None, i);
    }
    match text[i] {
        b'{' => (Some(Item::Open), i + 1),
        b'}' => (Some(Item::Close), i + 1),
        b'"' => {
            let mut out = Vec::new();
            i += 1;
            while i < length {
                match text[i] {
                    b'"' => return (Some(Item::Text(out)), i + 1),
                    b'\\' => {
                        match text.get(i + 1) {
                            Some(b'n') => out.push(b'\n'),
                            Some(b't') => out.push(b'\t'),
                            Some(&e) => out.push(e),
                            None => {}
                        }
                        i += 2;
                    }
                    c => {
                        out.push(c);
                        i += 1;
                    }
                }
            }
            (Some(Item::Text(out)), i)
        }
        _ => {
            let start = i;
            while i < length && !matches!(text[i], 0..=32 | b'"' | b'{' | b'}') {
                i += 1;
            }
            (Some(Item::Text(text[start..i].to_vec())), i)
        }
    }
}

unsafe extern "C-unwind" fn keyvalues_read(l: L) -> c_int {
    let api = api();
    let text = text_at(l, 1, "KeyValues text");
    (api.settop)(l, 2);
    (api.createtable)(l, 0, 0);
    let path = (api.gettop)(l);
    let mut depth: c_int = 0;
    let mut key: Option<Vec<u8>> = None;
    let mut i = 0;
    loop {
        let (item, next) = next_item(text, i);
        i = next;
        let Some(item) = item else { break };
        match item {
            Item::Open => {
                depth += 1;
                bytes(l, key.take().as_deref().unwrap_or_default());
                (api.rawseti)(l, path, depth);
            }
            Item::Close => {
                if depth > 0 {
                    (api.pushnil)(l);
                    (api.rawseti)(l, path, depth);
                    depth -= 1;
                }
                key = None;
            }
            Item::Text(value) => match key.take() {
                None => key = Some(value),
                Some(k) => {
                    (api.pushvalue)(l, 2);
                    (api.pushvalue)(l, path);
                    bytes(l, &k);
                    bytes(l, &value);
                    drop(k);
                    drop(value);
                    (api.call)(l, 3, 0);
                }
            },
        }
    }
    0
}

// encoding.consolecfg ---------------------------------------------------------

/// The line with its comment removed, and whether it chains commands.
fn strip(line: &[u8]) -> (&[u8], bool) {
    let mut quoted = false;
    for i in 0..line.len() {
        match line[i] {
            b'"' => quoted = !quoted,
            b'/' if !quoted && line.get(i + 1) == Some(&b'/') => return (&line[..i], false),
            b';' if !quoted => return (line, true),
            _ => {}
        }
    }
    (line, false)
}

fn is_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\n' | b'\r' | 0x0B | 0x0C)
}

fn trim(s: &[u8]) -> &[u8] {
    let start = s.iter().position(|&c| !is_space(c)).unwrap_or(s.len());
    let end = s.iter().rposition(|&c| !is_space(c)).map_or(start, |e| e + 1);
    &s[start..end.max(start)]
}

/// The commands of cfg text, and the lines refused for chaining.
fn commands(text: &[u8]) -> (Vec<&[u8]>, Vec<&[u8]>) {
    let (mut commands, mut refused) = (Vec::new(), Vec::new());
    let mut lines: Vec<&[u8]> = text.split(|&c| c == b'\n').collect();
    if text.last() == Some(&b'\n') {
        lines.pop();
    }
    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        let (stripped, chained) = strip(line);
        let command = trim(stripped);
        if chained {
            refused.push(command);
        } else if !command.is_empty() {
            commands.push(command);
        }
    }
    (commands, refused)
}

unsafe fn push_strings(l: L, list: &[&[u8]]) {
    let api = api();
    (api.createtable)(l, list.len() as c_int, 0);
    for (i, s) in list.iter().enumerate() {
        bytes(l, s);
        (api.rawseti)(l, -2, i as c_int + 1);
    }
}

unsafe extern "C-unwind" fn consolecfg_commands(l: L) -> c_int {
    let text = text_at(l, 1, "cfg text");
    let (found, refused) = commands(text);
    push_strings(l, &found);
    push_strings(l, &refused);
    drop(found);
    drop(refused);
    2
}

// encoding.cvarfile -----------------------------------------------------------

unsafe extern "C-unwind" fn cvarfile_write(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TTABLE);
    let mut out = Vec::new();
    let mut missing = None;
    each_item(l, 1, |l, name| {
        if missing.is_some() {
            return;
        }
        (api.pushvalue)(l, name);
        (api.gettable)(l, 2);
        let value = (api.gettop)(l);
        if (api.type_of)(l, value) != TSTRING && (api.type_of)(l, value) != crate::lua::TNUMBER {
            missing = Some(tostring(l, name));
            return;
        }
        out.extend_from_slice(text_at(l, name, "a convar's name"));
        out.extend_from_slice(b" \"");
        out.extend_from_slice(text_at(l, value, "a convar's value"));
        out.extend_from_slice(b"\"\n");
    });
    if let Some(name) = missing {
        drop(out);
        raise_where(l, format!("bad argument #3 to 'format' (string expected for {name})"));
    }
    let pushed = bytes(l, &out);
    drop(out);
    pushed
}

/// A command's name and its value, quoted or not.
fn split(command: &[u8]) -> (&[u8], &[u8]) {
    let end = command.iter().position(|&c| is_space(c)).unwrap_or(command.len());
    let name = &command[..end];
    let rest = &command[end..];
    let start = rest.iter().position(|&c| !is_space(c)).unwrap_or(rest.len());
    let rest = &rest[start..];
    let value = if rest.len() >= 2 && rest[0] == b'"' && rest[rest.len() - 1] == b'"' { &rest[1..rest.len() - 1] } else { rest };
    (name, value)
}

unsafe extern "C-unwind" fn cvarfile_read(l: L) -> c_int {
    let api = api();
    let text = text_at(l, 1, "cfg text");
    (api.checktype)(l, 2, TTABLE);
    (api.settop)(l, 2);
    (api.createtable)(l, 0, 0);
    let wanted = (api.gettop)(l);
    each_item(l, 2, |l, name| {
        (api.pushvalue)(l, name);
        (api.pushboolean)(l, 1);
        (api.rawset)(l, wanted);
    });
    (api.createtable)(l, 0, 0);
    let values = (api.gettop)(l);
    let (found, _) = commands(text);
    for command in &found {
        let (name, value) = split(command);
        bytes(l, name);
        (api.pushvalue)(l, -1);
        (api.rawget)(l, wanted);
        let is_wanted = (api.type_of)(l, -1) != TNIL;
        (api.settop)(l, -2);
        if is_wanted {
            bytes(l, value);
            (api.rawset)(l, values);
        } else {
            (api.settop)(l, -2);
        }
    }
    drop(found);
    (api.settop)(l, values);
    1
}

// encoding.gma ------------------------------------------------------------------

fn uint64(n: f64) -> [u8; 8] {
    let low = int32(n);
    [low[0], low[1], low[2], low[3], 0, 0, 0, 0]
}

unsafe extern "C-unwind" fn gma_write(l: L) -> c_int {
    let api = api();
    let name = text_at(l, 1, "an archive's name").to_vec();
    (api.checktype)(l, 2, TTABLE);
    let mut body = b"GMAD".to_vec();
    body.push(3);
    body.extend(uint64(0.0));
    body.extend(uint64(0.0));
    body.push(0);
    body.extend_from_slice(&name);
    body.extend([0, 0, 0]);
    body.extend(int32(1.0));
    drop(name);
    let mut datas: Vec<Vec<u8>> = Vec::new();
    let mut i = 0.0;
    each_item(l, 2, |l, f| {
        i += 1.0;
        (api.getfield)(l, f, c"path".as_ptr());
        let path = text_at(l, -1, "a file's path").to_vec();
        (api.getfield)(l, f, c"data".as_ptr());
        let data = text_at(l, -1, "a file's data").to_vec();
        body.extend(int32(i));
        body.extend_from_slice(&path);
        body.push(0);
        body.extend(uint64(data.len() as f64));
        body.extend(int32(crc32(&data) as f64));
        datas.push(data);
    });
    body.extend(int32(0.0));
    for data in &datas {
        body.extend_from_slice(data);
    }
    drop(datas);
    let crc = crc32(&body);
    body.extend(int32(crc as f64));
    let pushed = bytes(l, &body);
    drop(body);
    pushed
}

unsafe extern "C-unwind" fn gma_read(l: L) -> c_int {
    let api = api();
    let data = text_at(l, 1, "an archive");
    if !data.starts_with(b"GMAD") {
        raise_where(l, "not a GMA archive".into());
    }
    let mut at = 4 + 1 + 16;
    let cstr = |at: &mut usize| -> Option<&[u8]> {
        let stop = data[*at..].iter().position(|&c| c == 0)? + *at;
        let s = &data[*at..stop];
        *at = stop + 1;
        Some(s)
    };
    let int32_at = |at: &mut usize| -> Option<f64> {
        let b = data.get(*at..*at + 4)?;
        *at += 4;
        Some(b[0] as f64 + b[1] as f64 * 256.0 + b[2] as f64 * 65536.0 + b[3] as f64 * 16_777_216.0)
    };
    let parsed = (|| {
        while !cstr(&mut at)?.is_empty() {}
        let name = cstr(&mut at)?;
        cstr(&mut at)?;
        cstr(&mut at)?;
        int32_at(&mut at)?;
        let mut entries = Vec::new();
        while int32_at(&mut at)? != 0.0 {
            let path = cstr(&mut at)?;
            let size = int32_at(&mut at)? as usize;
            int32_at(&mut at)?;
            int32_at(&mut at)?;
            entries.push((path, size));
        }
        let mut files = Vec::new();
        for (path, size) in entries {
            let end = (at + size).min(data.len());
            files.push((path, &data[at.min(end)..end]));
            at += size;
        }
        Some((name, files))
    })();
    let Some((name, files)) = parsed else { raise_where(l, "a GMA archive cut short".into()) };
    (api.createtable)(l, 0, 2);
    bytes(l, name);
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.createtable)(l, files.len() as c_int, 0);
    for (i, (path, file)) in files.iter().enumerate() {
        (api.createtable)(l, 0, 2);
        bytes(l, path);
        (api.setfield)(l, -2, c"path".as_ptr());
        bytes(l, file);
        (api.setfield)(l, -2, c"data".as_ptr());
        (api.rawseti)(l, -2, i as c_int + 1);
    }
    drop(files);
    (api.setfield)(l, -2, c"files".as_ptr());
    1
}

/// Pushes file.buffer into the table at the top, as `buffer`.
pub unsafe fn push_file(l: L) {
    module::push(
        l,
        &[
            (c"Byte", buffer_byte),
            (c"Int16", buffer_int16),
            (c"Int32", buffer_int32),
            (c"Float32", buffer_float32),
            (c"Varint", buffer_varint),
            (c"String", buffer_string),
            (c"Utf8", buffer_utf8),
            (c"Crc32", buffer_crc32),
            (c"Writer", buffer_writer),
            (c"Reader", buffer_reader),
        ],
        None,
    );
    (api().setfield)(l, -2, c"buffer".as_ptr());
}

pub const FILE_NAMES: &[&CStr] = &[c"buffer"];

/// Pushes the encoding namespace's native modules into the table at the top.
pub unsafe fn push_encoding(l: L) {
    let api = api();
    module::push(l, &[(c"Decode", utf16_decode)], None);
    (api.setfield)(l, -2, c"utf16".as_ptr());
    module::push(l, &[(c"New", cursor_new)], None);
    (api.setfield)(l, -2, c"cursor".as_ptr());
    module::push(l, &[(c"Read", keyvalues_read)], None);
    (api.setfield)(l, -2, c"keyvalues".as_ptr());
    module::push(l, &[(c"Commands", consolecfg_commands)], None);
    (api.setfield)(l, -2, c"consolecfg".as_ptr());
    module::push(l, &[(c"Write", cvarfile_write), (c"Read", cvarfile_read)], None);
    (api.setfield)(l, -2, c"cvarfile".as_ptr());
    module::push(l, &[(c"Write", gma_write), (c"Read", gma_read)], None);
    crate::lua::push_str(l, "GMAD");
    (api.setfield)(l, -2, c"MAGIC".as_ptr());
    (api.pushnumber)(l, 3.0);
    (api.setfield)(l, -2, c"VERSION".as_ptr());
    (api.setfield)(l, -2, c"gma".as_ptr());
}

pub const ENCODING_NAMES: &[&CStr] = &[c"utf16", c"cursor", c"keyvalues", c"consolecfg", c"cvarfile", c"gma"];
