// This file contains the unconstrained operations that are used directly by BigInt class

use crate::fns::unconstrained_helpers::{
    __get_bit, __get_msb, __helper_add, __helper_mul, __helper_sub, __increment, __one, __reduce,
    __shl, __shr1,
};

use crate::constants::TWO_POW_120;

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

/// Adds two `BigInt` values with modular reduction (unconstrained)
///
/// Sums the limbs one by one, keeping the carry.
/// In case the result overflows the modulus, the modulus is subtracted once
///
/// ## Note
/// The `carry` must be `0` at the end of the loop.
/// No explicit assertion is made, as this condition is validated during evaluation.
pub unconstrained fn __add<let N: u32>(
    modulus: &[u128; N],
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    let mut result: [u128; N] = [0; N];
    let mut carry: u128 = 0;
    let mask: u128 = TWO_POW_120 - 1;

    for i in 0..N {
        let add_term: u128 = (lhs[i] + rhs[i] + carry);
        carry = add_term >> 120;
        result[i] = add_term & mask;
    }

    // check if the result is greater than the modulus
    if __gte(&result, modulus) {
        __helper_sub(&result, modulus)
    } else {
        result
    }
}

/// Subtracts two `BigInt` values with modular reduction (unconstrained).
///
/// Computes `x + (m - y)` (mod m)
pub unconstrained fn __sub<let N: u32>(
    modulus: &[u128; N],
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    if __is_zero(rhs) {
        *lhs
    } else {
        __add(modulus, lhs, &__helper_sub(modulus, rhs))
    }
}

/// Multiply `x` and `y` and reduce, returning (Q, R) (unconstrained).
///
/// For `BigInt` values `x` and `y` compute (`Q`, `R`) such that:
///      x * y = R + Q * m, 0 <= R < m
/// See `__reduce` for details.
pub(crate) unconstrained fn __mul_with_quotient<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> ([u128; N], [u128; N]) {
    let to_reduce: [u128; N * 2] = __helper_mul(lhs, rhs);
    __reduce::<N, BITS>(&to_reduce)
}

/// Multiplies two `BigInt` values with modular reduction (unconstrained).
pub unconstrained fn __mul<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    __mul_with_quotient::<N, BITS>(lhs, rhs).1
}

/// Modular exponentiation via square-and-multiply. LSB-first (unconstrained).
///
/// Computes `x^e mod m`
///
/// ## Note
/// For the loop, we are using `BITS` instead of `__get_msb`
/// because it is much much cheaper
pub unconstrained fn __pow<let N: u32, let BITS: u32>(
    val: &[u128; N],
    exponent: &[u128; N],
) -> [u128; N] {
    let mut accumulator: [u128; N] = __one();
    let mut x: [u128; N] = *val;
    let num_bits: u32 = BITS;

    for i in 0..num_bits {
        if __get_bit(exponent, i) {
            accumulator = __mul::<N, BITS>(&accumulator, &x);
        }
        x = __mul::<N, BITS>(&x, &x);
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
