//! A binding answers Lua as a web server answers a request: the request is
//! read off the stack into Rust values (a bad argument refused there, as
//! `luaL_check*` refuses it), a handler works on Rust types alone, and its
//! answer is written back as the response. Lua is the wire; the structures
//! stay Rust's.
//!
//! The handler is the one place a Rust panic may start, so it runs inside
//! `catch_unwind`, and only it: a Lua error unwinding into `catch_unwind`
//! aborts the process, as a Rust panic reaching Lua does. A handler is held
//! to touching no Lua by its `Send` bound: `L` is not `Send`, nor is a
//! userdata's guard, so it takes the value through `&mut *guard`.
//!
//! A handler's failure is one of two (`Fault`): the caller's mistake, raised
//! at the caller's line with its message, or ours, a panic, raised as a
//! foundation bug after the panic hook has logged where it happened.

use crate::lua::{push_str, raise_where, L};
use std::any::Any;
use std::ffi::c_int;
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Why a handler would not answer: the caller's mistake, said to it.
#[derive(Debug, PartialEq)]
pub struct Refusal(pub String);

impl Refusal {
    /// A refusal saying what a domain error says.
    pub fn of(error: impl std::fmt::Display) -> Refusal {
        Refusal(error.to_string())
    }
}

/// A response: the values a handler's answer pushes back, and how many.
pub trait Reply {
    /// # Safety
    /// `l` is the running call's state.
    unsafe fn reply(self, l: L) -> c_int;
}

impl Reply for () {
    unsafe fn reply(self, _l: L) -> c_int {
        0
    }
}

impl Reply for f64 {
    unsafe fn reply(self, l: L) -> c_int {
        l.pushnumber(self);
        1
    }
}

impl Reply for usize {
    unsafe fn reply(self, l: L) -> c_int {
        l.pushnumber(self as f64);
        1
    }
}

impl Reply for u32 {
    unsafe fn reply(self, l: L) -> c_int {
        l.pushnumber(f64::from(self));
        1
    }
}

impl Reply for bool {
    unsafe fn reply(self, l: L) -> c_int {
        l.pushboolean(c_int::from(self));
        1
    }
}

impl Reply for String {
    unsafe fn reply(self, l: L) -> c_int {
        push_str(l, &self);
        1
    }
}

/// None answers a single nil, as the Lua twins' `return nil` does.
impl<T: Reply> Reply for Option<T> {
    unsafe fn reply(self, l: L) -> c_int {
        match self {
            Some(value) => value.reply(l),
            None => {
                l.pushnil();
                1
            }
        }
    }
}

impl<A: Reply, B: Reply> Reply for (A, B) {
    unsafe fn reply(self, l: L) -> c_int {
        self.0.reply(l) + self.1.reply(l)
    }
}

/// Runs `handler` and answers Lua with its reply; a refusal is raised at
/// the caller's line, a panic as a foundation bug.
///
/// # Safety
/// `l` is the running call's state.
pub unsafe fn respond<R: Reply>(l: L, handler: impl FnOnce() -> Result<R, Refusal> + Send) -> c_int {
    match pure(l, handler) {
        Ok(answer) => answer.reply(l),
        Err(Refusal(message)) => raise_where(l, message),
    }
}

/// Runs the Rust part of a binding that must also call into Lua between its
/// parts (a job's run, a search's step): `work` touches no Lua, and a panic
/// in it is raised as a foundation bug rather than aborting the server.
///
/// # Safety
/// `l` is the running call's state.
pub unsafe fn pure<R>(l: L, work: impl FnOnce() -> R + Send) -> R {
    match catch_unwind(AssertUnwindSafe(work)) {
        Ok(value) => value,
        Err(payload) => raise_where(l, bug(payload)),
    }
}

/// A panic's message as the Lua error a foundation bug raises.
fn bug(payload: Box<dyn Any + Send>) -> String {
    let message = match payload.downcast::<String>() {
        Ok(text) => *text,
        Err(payload) => payload.downcast::<&str>().map_or_else(|_| "a panic without a message".to_owned(), |text| (*text).to_owned()),
    };
    format!("foundation bug: {message} (the server log has where)")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_panic_with_a_formatted_message_is_named_a_bug() {
        let payload = catch_unwind(|| panic!("slot {} is free", 3)).unwrap_err();
        assert_eq!(bug(payload), "foundation bug: slot 3 is free (the server log has where)");
    }

    #[test]
    fn a_panic_with_a_plain_message_is_named_a_bug() {
        let payload = catch_unwind(|| panic!("a plain one")).unwrap_err();
        assert_eq!(bug(payload), "foundation bug: a plain one (the server log has where)");
    }

    #[test]
    fn a_refusal_says_what_the_domain_error_says() {
        assert_eq!(Refusal::of(crate::graph::GraphError::LinkBeforeNode), Refusal("a link added before any node".into()));
    }
}
