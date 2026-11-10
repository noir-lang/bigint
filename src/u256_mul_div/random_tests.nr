//! Differential tests against a reference computed with `U512`, which holds the
//! full product `a * b` and divides it with bigint's general `U512` division, a code
//! path independent of the 64-bit-digit helper under test.
//!
//! The parametric tests take random inputs from the `nargo test` fuzzer. A random
//! input may be one the library rejects; the reference reports that through the
//! `*_ok` flags and the test then checks nothing for that operation. The rejection
//! paths are covered by the fixed `should_fail_with` tests in `tests.nr`.

use crate::{BigInt, U256, U512};
use mul_div::MulDiv;

/// Exact results of `a * b / d`.
/// `rem_ok` is false when `d` is zero or the floor quotient does not fit in U256;
/// `ceil_ok` is false when `d` is zero or the ceiling quotient does not fit.
struct Reference {
    rem_ok: bool,
    q: U256,
    r: U256,
    ceil_ok: bool,
    ceil: U256,
}

/// Narrows a U512 below 2^256 to U256. U256 uses the first three 120-bit limbs.
unconstrained fn narrow(x: U512) -> U256 {
    let limbs = x.get_limbs();
    U256::from_limbs([limbs[0], limbs[1], limbs[2]])
}

unconstrained fn reference(a: U256, b: U256, d: U256) -> Reference {
    let zero = U256::zero();
    if d == zero {
        Reference { rem_ok: false, q: zero, r: zero, ceil_ok: false, ceil: zero }
    } else {
        let max = U512::from(U256::from_le_bytes([255; 32]));
        let product = U512::from(a) * U512::from(b);
        let (q, r) = product.div_rem(&U512::from(d));
        let ceil = if r == U512::zero() {
            q
        } else {
            q + U512::one()
        };
        let rem_ok = q <= max;
        let ceil_ok = ceil <= max;
        Reference {
            rem_ok,
            q: if rem_ok { narrow(q) } else { zero },
            r: if rem_ok { narrow(r) } else { zero },
            ceil_ok,
            ceil: if ceil_ok { narrow(ceil) } else { zero },
        }
    }
}

fn check_u256(a: U256, b: U256, d: U256) -> Reference {
    // Safety: the reference is only compared against, never used as a result.
    let expected = unsafe { reference(a, b, d) };
    if expected.rem_ok {
        assert_eq(a.mul_div_rem(b, d), (expected.q, expected.r));
        assert_eq(a.mul_div_floor(b, d), expected.q);
    }
    if expected.ceil_ok {
        assert_eq(a.mul_div_ceil(b, d), expected.ceil);
    }
    expected
}

fn u256_max3(a: U256, b: U256, c: U256) -> U256 {
    let ab = if a > b { a } else { b };
    if ab > c {
        ab
    } else {
        c
    }
}

#[test]
fn u256_random(a: [u8; 32], b: [u8; 32], d: [u8; 32]) {
    let _ = check_u256(
        U256::from_le_bytes(a),
        U256::from_le_bytes(b),
        U256::from_le_bytes(d),
    );
}

#[test]
fn u256_fitting_quotient(a: [u8; 32], b: [u8; 32]) {
    let a = U256::from_le_bytes(a);
    let b = U256::from_le_bytes(b);
    let expected = check_u256(a, b, u256_max3(a, b, U256::one()));
    assert(expected.rem_ok);
}

#[test]
fn u256_exact_division(a: [u8; 32], b: [u8; 32]) {
    let a = U256::from_le_bytes(a);
    let b = u256_max3(U256::from_le_bytes(b), U256::one(), U256::one());
    let expected = check_u256(a, b, b);
    assert(expected.rem_ok & (expected.r == U256::zero()));
}

#[test]
fn u256_small_divisor(a: [u8; 32], s: u64) {
    let s = U256::from(s as u128);
    let expected = check_u256(U256::from_le_bytes(a), s, s + U256::one());
    assert(expected.rem_ok);
}

#[test]
fn u256_half_width_divisor(a: [u8; 32], s: u128) {
    // A 128-bit divisor next to the 120-bit limb boundary of U256.
    let s = U256::from(s);
    let expected = check_u256(U256::from_le_bytes(a), s, s + U256::one());
    assert(expected.rem_ok);
}

#[test]
fn u256_ceiling_overflow(k: u64) {
    let max = U256::from_le_bytes([255; 32]);
    let k = U256::from(k as u128) + U256::one();
    let expected = check_u256(max - k, max - k, max - k - k);
    assert(expected.rem_ok & !expected.ceil_ok);
}

#[test]
fn reference_matches_known_case() {
    // (2^256 - 1)^2 / (2^256 - 1) = 2^256 - 1 exactly; 7 * 9 / 4 = 15 rem 3, ceil 16.
    let max = U256::from_le_bytes([255; 32]);
    // Safety: test-only use of the unconstrained reference.
    let full = unsafe { reference(max, max, max) };
    assert(full.rem_ok & full.ceil_ok & (full.q == max) & (full.r == U256::zero()));
    // Safety: test-only use of the unconstrained reference.
    let small = unsafe { reference(U256::from(7), U256::from(9), U256::from(4)) };
    assert(
        (small.q == U256::from(15)) & (small.r == U256::from(3)) & (small.ceil == U256::from(16)),
    );
}
