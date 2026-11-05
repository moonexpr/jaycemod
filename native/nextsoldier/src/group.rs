//! The root of the tree a soldier runs beside its main one, as L4D2's survivors run their
//! legs: GroupIdentityBehavior. It runs what its config starts it on; what it holds of a
//! soldier's group grows here, in Rust, since it runs every update.

#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) use hooks::KIND;

#[cfg(all(windows, target_arch = "x86_64"))]
mod hooks {
    use crate::engine::{self, Kind};
    use crate::layout::*;
    use foundation::lua::{api, raise_where, L, TTABLE};
    use std::ffi::{c_int, c_void, CStr};

    const NAME: &CStr = c"GroupIdentityBehavior";

    pub(crate) const KIND: Kind = Kind {
        name: NAME,
        slots,
        init,
        constructor,
    };

    fn slots() -> Vec<(usize, usize)> {
        vec![(INITIAL_CONTAINED, initial_contained as *const () as usize)]
    }

    unsafe fn init(_l: L, _config: c_int) -> u64 {
        0
    }

    /// engine.GroupIdentityBehavior{ initial } -> the root, for engine.InsertGroup: `initial`
    /// the action it runs first.
    unsafe extern "C-unwind" fn constructor(l: L) -> c_int {
        let api = api();
        (api.settop)(l, 1);
        (api.checktype)(l, 1, TTABLE);
        (api.getfield)(l, 1, c"initial".as_ptr());
        if (api.type_of)(l, -1) != TTABLE {
            raise_where(
                l,
                "GroupIdentityBehavior needs the action it runs first".into(),
            );
        }
        (api.settop)(l, 1);
        engine::mark_config(l, NAME);
        1
    }

    unsafe extern "win64" fn initial_contained(
        this: *mut LuaAction,
        _me: *mut c_void,
    ) -> *mut Action {
        engine::with_config(this, |l| {
            (api().getfield)(l, -1, c"initial".as_ptr());
            engine::action_from_top(l, this)
        })
    }
}
