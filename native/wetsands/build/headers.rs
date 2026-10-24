//! Reads the Source SDK's headers (native/vendor/source-sdk-2013) for the
//! values Source names: every enum's members, and each `const float` or
//! `const int` defined outside any `#if` (one inside a branch has another
//! value per game, so which one GMod's build took is not the header's to
//! say). Writes them as Rust constants under their Source names. A value
//! this cannot evaluate exactly is an error, never a guess.

use std::collections::HashMap;

#[derive(Debug, PartialEq)]
pub struct Constant {
    pub name: String,
    pub value: Value,
    /// The enum it belongs to, or None for a plain constant.
    pub group: Option<String>,
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Value {
    Int(i64),
    Float(f64),
}

/// Strips `//` and `/* */` comments.
fn uncommented(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(i) = rest.find('/') {
        out.push_str(&rest[..i]);
        let tail = &rest[i..];
        if tail.starts_with("//") {
            rest = tail.find('\n').map_or("", |n| &tail[n..]);
        } else if tail.starts_with("/*") {
            rest = tail.find("*/").map_or("", |n| &tail[n + 2..]);
        } else {
            out.push('/');
            rest = &tail[1..];
        }
    }
    out.push_str(rest);
    out
}

/// An integer expression of literals, names already known, `|`, `<<`, `+`
/// and parentheses.
fn evaluate(expr: &str, known: &HashMap<String, i64>) -> Result<i64, String> {
    let tokens = tokenize(expr)?;
    let mut parser = Parser { tokens: &tokens, at: 0, known };
    let value = parser.or()?;
    if parser.at != tokens.len() {
        return Err(format!("cannot evaluate `{}`", expr.trim()));
    }
    Ok(value)
}

fn tokenize(expr: &str) -> Result<Vec<String>, String> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = expr.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_whitespace() {
            i += 1;
        } else if c == '<' && chars.get(i + 1) == Some(&'<') {
            tokens.push("<<".into());
            i += 2;
        } else if "|+()".contains(c) {
            tokens.push(c.to_string());
            i += 1;
        } else if c.is_alphanumeric() || c == '_' {
            let start = i;
            while i < chars.len() && (chars[i].is_alphanumeric() || chars[i] == '_') {
                i += 1;
            }
            tokens.push(chars[start..i].iter().collect());
        } else {
            return Err(format!("cannot evaluate `{}`: `{c}`", expr.trim()));
        }
    }
    Ok(tokens)
}

struct Parser<'a> {
    tokens: &'a [String],
    at: usize,
    known: &'a HashMap<String, i64>,
}

impl Parser<'_> {
    fn peek(&self) -> Option<&str> {
        self.tokens.get(self.at).map(String::as_str)
    }

    fn or(&mut self) -> Result<i64, String> {
        let mut value = self.shift()?;
        while self.peek() == Some("|") {
            self.at += 1;
            value |= self.shift()?;
        }
        Ok(value)
    }

    fn shift(&mut self) -> Result<i64, String> {
        let mut value = self.sum()?;
        while self.peek() == Some("<<") {
            self.at += 1;
            value <<= self.sum()?;
        }
        Ok(value)
    }

    fn sum(&mut self) -> Result<i64, String> {
        let mut value = self.atom()?;
        while self.peek() == Some("+") {
            self.at += 1;
            value += self.atom()?;
        }
        Ok(value)
    }

    fn atom(&mut self) -> Result<i64, String> {
        let token = self.peek().ok_or("an expression ends early")?.to_string();
        self.at += 1;
        if token == "(" {
            let value = self.or()?;
            if self.peek() != Some(")") {
                return Err("an unclosed parenthesis".into());
            }
            self.at += 1;
            return Ok(value);
        }
        if let Some(hex) = token.strip_prefix("0x").or_else(|| token.strip_prefix("0X")) {
            return i64::from_str_radix(hex, 16).map_err(|e| format!("`{token}`: {e}"));
        }
        if token.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            return token.parse().map_err(|e| format!("`{token}`: {e}"));
        }
        self.known.get(&token).copied().ok_or_else(|| format!("`{token}` is not a known value"))
    }
}

/// The text between each `enum Name {` and its `}`, by name.
fn enums(text: &str) -> Vec<(String, String)> {
    let mut found = Vec::new();
    let mut rest = text;
    while let Some(i) = rest.find("enum ") {
        let after = &rest[i + 5..];
        let name: String = after.trim_start().chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
        let (Some(open), Some(close)) = (after.find('{'), after.find('}')) else { break };
        let head = &after[..open];
        if !name.is_empty() && open < close && !head.contains(';') && head.trim() == name {
            found.push((name, after[open + 1..close].to_string()));
        }
        rest = &after[close.max(open) + 1..];
    }
    found
}

/// Every enum's members and the plain constants outside `#if`s, in header order.
pub fn constants(header: &str) -> Result<Vec<Constant>, String> {
    let text = uncommented(header);
    let mut out = Vec::new();
    let mut known: HashMap<String, i64> = HashMap::new();
    for (group, body) in enums(&text) {
        let mut next = 0i64;
        for member in body.split(',') {
            let member = member.trim();
            if member.is_empty() {
                continue;
            }
            let (name, value) = match member.split_once('=') {
                Some((name, expr)) => (name.trim().to_string(), evaluate(expr, &known)?),
                None => (member.to_string(), next),
            };
            next = value + 1;
            known.insert(name.clone(), value);
            out.push(Constant { name, value: Value::Int(value), group: Some(group.clone()) });
        }
    }
    let mut depth = 0usize;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with("#if") {
            depth += 1;
        } else if line.starts_with("#endif") {
            depth = depth.saturating_sub(1);
        } else if depth == 0 {
            if let Some(constant) = plain(line, &known)? {
                out.push(constant);
            }
        }
    }
    Ok(out)
}

/// A `const float Name = 1.0f;` or `const int Name = 3;` line.
fn plain(line: &str, known: &HashMap<String, i64>) -> Result<Option<Constant>, String> {
    let float = line.strip_prefix("const float ");
    let Some(rest) = float.or_else(|| line.strip_prefix("const int ")) else { return Ok(None) };
    let Some((name, value)) = rest.trim_end_matches(';').split_once('=') else { return Ok(None) };
    let (name, value) = (name.trim().to_string(), value.trim().trim_end_matches(';').trim());
    let value = if float.is_some() {
        let literal = value.trim_end_matches('f');
        match literal.parse::<f64>() {
            Ok(v) => Value::Float(v),
            Err(_) => return Err(format!("`{name}` = `{value}` is not a float literal")),
        }
    } else {
        Value::Int(evaluate(value, known)?)
    };
    Ok(Some(Constant { name, value, group: None }))
}

/// The constants as a Rust module's items.
pub fn rust(constants: &[Constant]) -> String {
    let mut out = String::new();
    for c in constants {
        let doc = c.group.as_ref().map_or(String::new(), |g| format!("/// {g}\n"));
        let item = match c.value {
            Value::Int(v) if c.group.is_some() => format!("pub const {}: i64 = {v};\n", c.name),
            Value::Int(v) => format!("pub const {}: i64 = {v};\n", c.name),
            Value::Float(v) => format!("pub const {}: f32 = {v:?};\n", c.name),
        };
        out.push_str(&doc);
        out.push_str(&item);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER: &str = "
// a comment with enum Fake { NO = 1 };
const float StepHeight = 18.0f;  // step
#ifdef CSTRIKE_DLL
const float DeathDrop = 200.0f;
#else
const float DeathDrop = 400.0f;
#endif
/* enum Hidden { X } */
enum NavDirType
{
	NORTH = 0,
	EAST,
	SOUTH = 2,	// trailing
	WEST,

	NUM_DIRECTIONS
};
enum Flags
{
	A = 0x01,
	B = 1 << 1,
	BOTH = ( A | B ),
};
";

    fn named(constants: &[Constant], name: &str) -> Option<Value> {
        constants.iter().find(|c| c.name == name).map(|c| c.value)
    }

    #[test]
    fn reads_enum_members_counting_on_from_the_last_value() {
        let c = constants(HEADER).unwrap();
        assert_eq!(named(&c, "EAST"), Some(Value::Int(1)));
        assert_eq!(named(&c, "WEST"), Some(Value::Int(3)));
        assert_eq!(named(&c, "NUM_DIRECTIONS"), Some(Value::Int(4)));
        assert_eq!(c.iter().find(|c| c.name == "NORTH").unwrap().group.as_deref(), Some("NavDirType"));
    }

    #[test]
    fn evaluates_hex_shifts_and_ors_of_earlier_members() {
        let c = constants(HEADER).unwrap();
        assert_eq!(named(&c, "B"), Some(Value::Int(2)));
        assert_eq!(named(&c, "BOTH"), Some(Value::Int(3)));
    }

    #[test]
    fn takes_plain_constants_only_outside_conditional_branches() {
        let c = constants(HEADER).unwrap();
        assert_eq!(named(&c, "StepHeight"), Some(Value::Float(18.0)));
        assert_eq!(named(&c, "DeathDrop"), None);
    }

    #[test]
    fn ignores_what_comments_hide() {
        let c = constants(HEADER).unwrap();
        assert_eq!(named(&c, "NO"), None);
        assert_eq!(named(&c, "X"), None);
    }

    #[test]
    fn refuses_a_value_it_cannot_evaluate() {
        let err = constants("enum E { A = sizeof(int) };").unwrap_err();
        assert!(err.contains("sizeof"), "{err}");
        assert!(constants("enum E { A = UNKNOWN };").unwrap_err().contains("UNKNOWN"));
    }

    #[test]
    fn writes_rust_constants_under_source_names() {
        let c = constants("const float StepHeight = 18.0f;\nenum D { NORTH = 0 };").unwrap();
        assert_eq!(rust(&c), "/// D\npub const NORTH: i64 = 0;\npub const StepHeight: f32 = 18.0;\n");
    }
}
