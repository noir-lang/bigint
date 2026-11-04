pub mod bigint;

mod constants;

// Pre-defined `BigInt`s for people to use:
pub mod types;

// Free functions and other utils, called by the BigInt structs
pub(crate) mod fns;
pub(crate) mod utils;

mod benchmarks;
mod tests;

// Internal functions required by derive macros for external crates
// Exported through the `internal` submodule to make it clear they are not
// intended for direct use by end users
pub mod internal {
    pub use crate::fns::modulus::get_modulus;

    // Constrained operations
    pub use crate::fns::constrained_ops::add;
    pub use crate::fns::constrained_ops::assert_is_not_equal;
    pub use crate::fns::constrained_ops::assert_is_not_zero;
    pub use crate::fns::constrained_ops::assert_is_not_zero_integer;
    pub use crate::fns::constrained_ops::cmp;
    pub use crate::fns::constrained_ops::derive_from_seed;
    pub use crate::fns::constrained_ops::div;
    pub use crate::fns::constrained_ops::div_rem;
    pub use crate::fns::constrained_ops::eq;
    pub use crate::fns::constrained_ops::from_field;
    pub use crate::fns::constrained_ops::is_zero;
    pub use crate::fns::constrained_ops::is_zero_integer;
    pub use crate::fns::constrained_ops::mul;
    pub use crate::fns::constrained_ops::rem;
    pub use crate::fns::constrained_ops::sqr;
    pub use crate::fns::constrained_ops::sub;
    pub use crate::fns::constrained_ops::validate_in_range;

    // Unconstrained operations
    pub use crate::fns::unconstrained_ops::__add;
    pub use crate::fns::unconstrained_ops::__derive_from_seed;
    pub use crate::fns::unconstrained_ops::__div_rem;
    pub use crate::fns::unconstrained_ops::__eq;
    pub use crate::fns::unconstrained_ops::__is_zero;
    pub use crate::fns::unconstrained_ops::__mul;
    pub use crate::fns::unconstrained_ops::__pow;
    pub use crate::fns::unconstrained_ops::__sqr;
    pub use crate::fns::unconstrained_ops::__sub;

    // Serialization functions
    pub use crate::fns::serialization::from_be_bytes;
    pub use crate::fns::serialization::from_le_bytes;
    pub use crate::fns::serialization::to_be_bytes;
    pub use crate::fns::serialization::to_le_bytes;
}

// Re-export the main structs so that users don't have to specify the paths
pub use bigint::BigInt;
pub use bigint::{compute_quadratic_expression, evaluate_quadratic_expression, to_field};
pub use bigint::derive_bigint;

// Re-export the pre-defined bigint types, for easier access:
pub use types::U1024::U1024;
pub use types::U2048::U2048;
pub use types::U256::U256;
pub use types::U4096::U4096;
pub use types::U512::U512;
pub use types::U8192::U8192;
