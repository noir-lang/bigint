// This file contains the unconstrained operations that are used directly by BigInt class

use crate::fns::constrained_ops::derive_from_seed;

use crate::fns::unconstrained_helpers::{
    __get_bit, __get_msb, __helper_add, __helper_mul, __helper_sub, __increment, __one, __shl,
    __shr1,
};

use crate::constants::TWO_POW_120;

// ------------------------------ DERIVATION FUNCTIONS ------------------------------

/// Deterministically derives a `BigInt` from a seed value (unconstrained)
///
/// Takes a seed byte array and generates a `BigInt` in the range [0, 2^BITS).
///
/// See more information in `constrained_ops.nr`: `derive_from_seed`
pub unconstrained fn __derive_from_seed<let N: u32, let BITS: u32, let SeedBytes: u32>(
    seed: [u8; SeedBytes],
) -> [u128; N] {
    derive_from_seed::<N, BITS, SeedBytes>(seed)
}

// ------------------------------ COMPARISON FUNCTIONS ------------------------------

/// Compare two limb arrays for equality (unconstrained)
pub unconstrained fn __eq<let N: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> bool {
    *lhs == *rhs
}

/// Compare a limb array to a zero array (unconstrained)
pub unconstrained fn __is_zero<let N: u32>(limbs: &[u128; N]) -> bool {
    *limbs == [0; N]
}

/// Compare two little-endian limb arrays for `lhs >= rhs` over integers (unconstrained)
///
/// Starts from the most significant limb (`N - 1`) and returns true
/// if `lhs` is greater or equal to `rhs`
pub(crate) unconstrained fn __gte<let N: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> bool {
    let mut result: bool = true;
    for i in 0..N {
        let idx: u32 = N - 1 - i;
        if (lhs[idx] != rhs[idx]) {
            result = lhs[idx] > rhs[idx];
            break;
        }
    }
    result
}

// ------------------------------ ARITHMETIC FUNCTIONS ------------------------------

/// Adds two `BigInt` values (unconstrained).
///
/// Fails if the sum overflows `2^BITS`.
pub unconstrained fn __add<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    let mut result: [u128; N] = [0; N];
    let mut carry: u128 = 0;
    let mask: u128 = TWO_POW_120 - 1;

    for i in 0..N {
        let add_term: u128 = lhs[i] + rhs[i] + carry;
        carry = add_term >> 120;
        result[i] = add_term & mask;
    }

    let top_limb_bits: u128 = (BITS - (N - 1) * 120) as u128;
    assert((carry == 0) & ((result[N - 1] >> top_limb_bits) == 0), "attempt to add with overflow");
    result
}

/// Subtracts two `BigInt` values (unconstrained).
///
/// Fails if `rhs > lhs`.
pub unconstrained fn __sub<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    assert(__gte(lhs, rhs), "attempt to subtract with overflow");
    __helper_sub(lhs, rhs)
}

/// Multiplies two `BigInt` values (unconstrained).
///
/// Fails if the product overflows `2^BITS`.
pub unconstrained fn __mul<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    let product: [u128; 2 * N] = __helper_mul(lhs, rhs);

    let mut result: [u128; N] = [0; N];
    for i in 0..N {
        result[i] = product[i];
    }
    let top_limb_bits: u128 = (BITS - (N - 1) * 120) as u128;
    let mut overflow: bool = (result[N - 1] >> top_limb_bits) != 0;
    for i in N..2 * N {
        overflow |= product[i] != 0;
    }
    assert(!overflow, "attempt to multiply with overflow");

    result
}

/// Exponentiation via square-and-multiply, MSB-first (unconstrained).
///
/// Computes `x^e`, failing if the result overflows `2^BITS`.
///
/// ## Note
/// Processing the exponent from its most significant bit means each intermediate value is
/// `x^p` for a prefix `p` of the exponent's bits, with `p <= e`. Hence no intermediate step
/// overflows unless the result does (for `x >= 1`; for `x = 0` every intermediate value is `0` or
/// `1`).
pub unconstrained fn __pow<let N: u32, let BITS: u32>(
    val: &[u128; N],
    exponent: &[u128; N],
) -> [u128; N] {
    let mut accumulator: [u128; N] = __one();
    if !__is_zero(exponent) {
        let msb: u32 = __get_msb(exponent);
        for i in 0..msb + 1 {
            accumulator = __mul::<N, BITS>(&accumulator, &accumulator);
            if __get_bit(exponent, msb - i) {
                accumulator = __mul::<N, BITS>(&accumulator, val);
            }
        }
    }
    accumulator
}

/// Given the `BigInt` inputs `x, y`, compute integer division x / y (unconstrained)
///
/// This function implements binary long division and outputs (`quotient`, `remainder`) such that:
///   1. floor(numerator / divisor) = quotient
///   2. numerator % divisor = remainder
///   3. divisor * quotient + remainder = numerator
///
/// Fails if the divisor is zero.
pub unconstrained fn __div_rem<let N: u32>(
    numerator: &[u128; N],
    divisor: &[u128; N],
) -> ([u128; N], [u128; N]) {
    assert(!__is_zero(divisor), "attempt to divide by zero");
    let mut quotient: [u128; N] = [0; N];
    let mut remainder: [u128; N] = *numerator;
    let b: [u128; N] = *divisor;

    let numerator_msb: u32 = __get_msb(numerator);
    let divisor_msb: u32 = __get_msb(divisor);
    if divisor_msb > numerator_msb {
        ([0; N], *numerator)
    } else {
        let bit_difference: u32 = __get_msb(&remainder) - __get_msb(divisor);
        let mut divisor: [u128; N] = __shl(divisor, bit_difference);
        let mut accumulator: [u128; N] = __shl(&__one(), bit_difference);

        // The same as divisor > remainder
        if (__gte(&divisor, &__increment(&remainder))) {
            divisor = __shr1(divisor);
            accumulator = __shr1(accumulator);
        }

        for _ in 0..(N * 120) {
            if (__gte(&remainder, &b) == false) {
                break;
            }
            // we've shunted 'divisor' up to have the same bit length as our remainder.
            // If remainder >= divisor, then a is at least '1 << bit_difference' multiples of b
            if (__gte(&remainder, &divisor)) {
                remainder = __helper_sub(&remainder, &divisor);
                // we can use OR here instead of +, as
                // accumulator is always a nice power of two
                quotient = __helper_add(&quotient, &accumulator);
            }
            divisor = __shr1(divisor);
            accumulator = __shr1(accumulator);
        }

        (quotient, remainder)
    }
}
