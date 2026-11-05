// This file contains the unconstrained helpers that are mostly used by unconstrained ops

use crate::constants::TWO_POW_120;

use crate::fns::unconstrained_ops::__gte;

use crate::utils::msb::get_msb;
use crate::utils::split_bits::{__normalize_limbs, __split_120_bits};

// ------------------------------ DERIVATION HELPER FUNCTIONS ------------------------------

///  Construct a `1` BigInt value (unconstrained)
pub(crate) unconstrained fn __one<let N: u32>() -> [u128; N] {
    let mut limbs: [u128; N] = [0; N];
    limbs[0] = 1;
    limbs
}

/// Construct a BigInt value from Field (unconstrained)
///
/// Split the native `Field` value into `N` 120-bit limbs
pub(crate) unconstrained fn __from_field<let N: u32>(val: Field) -> [u128; N] {
    let x: Field = val;
    let mut result: [u128; N] = [0; N];

    if (N == 1) {
        let (first_limb, _): (u128, Field) = __split_120_bits(x);
        result[0] = first_limb;
    }

    if (N == 2) {
        let (first_limb, x): (u128, Field) = __split_120_bits(x);
        let (second_limb, _): (u128, Field) = __split_120_bits(x);
        result[0] = first_limb;
        result[1] = second_limb;
    }

    if (N > 2) {
        let (first_limb, x): (u128, Field) = __split_120_bits(x);
        let (second_limb, x): (u128, Field) = __split_120_bits(x);
        let (third_limb, _): (u128, Field) = __split_120_bits(x);
        result[0] = first_limb;
        result[1] = second_limb;
        result[2] = third_limb;
    }
    result
}

// ------------------------------ ARITHMETIC WITH FLAGS HELPER FUNCTIONS ------------------------------
// These are the functions that compute modular operations results as well as borrow and carry flags for constraints

/// Compute flags for modular addition (unconstrained)
///
/// Given `lhs, rhs, modulus`, computes the carry and borrow flags needed
/// for `lhs + rhs - (overflow ? modulus : 0)`.
/// The result is computed in constrained code using `compute_add_result`.
///
/// Returns (carry_flags, borrow_flags, overflow) where:
/// - carry_flags: carries from adding lhs + rhs
/// - borrow_flags: borrows from subtracting modulus when overflow occurs
/// - overflow: true if lhs + rhs >= modulus (so we need to subtract modulus)
pub(crate) unconstrained fn compute_add_flags<let N: u32>(
    modulus: &[u128; N],
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> ([bool; N - 1], [bool; N - 1], bool) {
    let mask: u128 = TWO_POW_120 - 1;

    let add_res: [u128; N] = __helper_add(lhs, rhs);
    let overflow: bool = __gte(&add_res, modulus);

    let subtrahend: [u128; N] = if overflow { *modulus } else { [0; N] };

    let mut borrow_flags: [bool; N - 1] = [false; N - 1];
    let mut carry_flags: [bool; N - 1] = [false; N - 1];

    let mut carry: u128 = 0;
    let mut borrow: u128 = 0;
    for i in 0..N {
        let mut add_term: u128 = lhs[i] + rhs[i] + carry;
        carry = add_term >> 120;
        add_term &= mask;

        let sub_term: u128 = subtrahend[i] + borrow;
        borrow = (sub_term > add_term) as u128;

        // Only set `borrow` and `carry` if they differ
        // And if it's not the last limb
        if (carry != borrow) & (i < N - 1) {
            carry_flags[i] = carry != 0;
            borrow_flags[i] = borrow != 0;
        }
    }
    (carry_flags, borrow_flags, overflow)
}

/// Compute flags for modular subtraction (unconstrained)
///
/// Given `lhs, rhs, modulus`, computes the carry and borrow flags needed
/// for `lhs - rhs + (underflow ? modulus : 0)`.
/// The result is computed in constrained code using `compute_sub_result`.
///
/// Returns (carry_flags, borrow_flags, underflow) where:
/// - carry_flags: carries from adding (lhs + modulus) when underflow occurs
/// - borrow_flags: borrows from subtracting rhs
/// - underflow: true if lhs < rhs (so we need to add modulus)
pub(crate) unconstrained fn compute_sub_flags<let N: u32>(
    modulus: &[u128; N],
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> ([bool; N - 1], [bool; N - 1], bool) {
    let mask: u128 = TWO_POW_120 - 1;

    let underflow: bool = !__gte(lhs, rhs);

    let addend: [u128; N] = if underflow { *modulus } else { [0; N] };

    let mut borrow_flags: [bool; N - 1] = [false; N - 1];
    let mut carry_flags: [bool; N - 1] = [false; N - 1];

    let mut carry: u128 = 0;
    let mut borrow: u128 = 0;
    for i in 0..N {
        let mut add_term: u128 = lhs[i] + addend[i] + carry;
        carry = add_term >> 120;
        add_term &= mask;

        let sub_term: u128 = rhs[i] + borrow;
        borrow = (sub_term > add_term) as u128;

        // Only set `borrow` and `carry` if they differ
        // And if it's not the last limb
        if (carry != borrow) & (i < N - 1) {
            carry_flags[i] = carry != 0;
            borrow_flags[i] = borrow != 0;
        }
    }
    (carry_flags, borrow_flags, underflow)
}

/// Compute borrow flags for lhs - rhs (unconstrained)
///
/// The result is computed in constrained code using `compute_gte_result`
pub(crate) unconstrained fn compute_borrow_flags<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [bool; N - 1] {
    let mut borrow_flags: [bool; N - 1] = [false; N - 1];
    borrow_flags[0] = lhs[0] < rhs[0];
    for i in 1..N - 1 {
        borrow_flags[i] = lhs[i] < rhs[i] + (borrow_flags[i - 1] as u128);
    }
    borrow_flags
}

/// Compute underflow and borrow flags for gte comparison (unconstrained)
///
/// Returns (underflow, borrow_flags) where:
/// - underflow is true if lhs < rhs
/// - borrow_flags correspond to max(lhs, rhs) - min(lhs, rhs)
pub(crate) unconstrained fn compute_gte_flags<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> (bool, [bool; N - 1]) {
    let underflow: bool = !__gte(lhs, rhs);
    // swap if underflow so we're computing borrow flags for larger - smaller
    let (a, b): ([u128; N], [u128; N]) = if underflow {
        (*rhs, *lhs)
    } else {
        (*lhs, *rhs)
    };

    let borrow_flags = compute_borrow_flags(&a, &b);
    (underflow, borrow_flags)
}

// ------------------------------ MODULAR REDUCTION ------------------------------

/// Reduce a double-width value modulo `2^BITS`, returning (Q, R) (unconstrained)
///
/// For the `2N`-limb value `x` compute (`Q`, `R`) such that:
///      x = R + Q * 2^BITS, 0 <= R < 2^BITS
///
/// As the modulus is a power of two, `R` is the low `BITS` bits of `x` and `Q` is the
/// remaining high bits.
///
/// ## Note
/// `Q` is truncated to `N` limbs. Callers must ensure that `x < 2^(120 * N + BITS)`,
/// which holds for the product of any two `N`-limb values whose limbs are at most 120 bits.
pub(crate) unconstrained fn __reduce<let N: u32, let BITS: u32>(
    x: &[u128; 2 * N],
) -> ([u128; N], [u128; N]) {
    let bits: u32 = BITS;
    let top_limb: u32 = bits / 120;
    let top_limb_mask: u128 = (1 << ((bits % 120) as u128)) - 1;

    let mut remainder: [u128; N] = [0; N];
    for i in 0..top_limb {
        remainder[i] = x[i];
    }
    remainder[top_limb] = x[top_limb] & top_limb_mask;

    let long_quotient: [u128; 2 * N] = __shr(x, bits);
    let mut quotient: [u128; N] = [0; N];
    for i in 0..N {
        quotient[i] = long_quotient[i];
    }

    (quotient, remainder)
}

// ------------------------------ ARITHMETIC HELPER FUNCTIONS ------------------------------
// These are the functions that operate on limbs as if they were just big integers

/// Adds `1` to the BigInt value, without checking for overflow (unconstrained)
///
/// ## Note
/// The `carry` must be `0` at the end of the loop.
/// No explicit assertion is made, as this condition is validated during evaluation.
pub(crate) unconstrained fn __increment<let N: u32>(val: &[u128; N]) -> [u128; N] {
    let mask: u128 = TWO_POW_120 - 1;

    let mut result: [u128; N] = [0; N];
    let mut carry: u128 = 1;
    for i in 0..N {
        let add_term: u128 = val[i] + carry;
        carry = add_term >> 120;
        result[i] = add_term & mask;
    }
    result
}

/// Adds two `BigInt` values limb-wise, without checking for overflow (unconstrained).
///
/// ## Note
/// The `carry` must be `0` at the end of the loop.
/// No explicit assertion is made, as this condition is validated during evaluation.
pub(crate) unconstrained fn __helper_add<let N: u32>(
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
    result
}

/// Subtracts two `BigInt` values limb-wise, without checking for underflow (unconstrained).
///
/// ## Note
/// The `borrow` must be `0` at the end of the loop.
/// No explicit assertion is made, as this condition is validated during evaluation.
pub(crate) unconstrained fn __helper_sub<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; N] {
    let mut result: [u128; N] = [0; N];

    let mut borrow: u128 = 0;
    for i in 0..N {
        let subtrahend: u128 = rhs[i] + borrow;
        borrow = (subtrahend > lhs[i]) as u128;
        result[i] = (borrow << 120) + lhs[i] - subtrahend;
    }
    result
}

/// Multiplies two `BigInt` values into a double-width result (unconstrained).
///
/// Computes the full schoolbook product of two N-limb little-endian arrays
///
/// ## Note
/// The mathematical product fits in `2 * N - 1` limbs, but we keep `2 * N`
/// limbs intentionally as the extra high limb safely absorbs a possible single limb overflow
/// for values close to `2^{120 * N}`.
pub(crate) unconstrained fn __helper_mul<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
) -> [u128; 2 * N] {
    let mut result: [Field; 2 * N] = [0; 2 * N];
    for i in 0..N {
        for j in 0..N {
            result[i + j] += (lhs[i] as Field) * (rhs[j] as Field);
        }
    }
    __normalize_limbs(result)
}

// ------------------------------ LOGIC HELPER FUNCTIONS ------------------------------
// These are the functions that operate on limbs as if they were just big integers

/// Left-shifts a `BigInt` value by `shift` bits (unconstrained).
///
/// Performs a bitwise left shift across limbs.
///
/// ## Note
/// The most significant limb is truncated to 120 bits after the shift.
///
/// No bounds check is performed on `num_shifted_limbs`.
/// However, we use it only in `__div_rem`, where it is not possible to reach
/// `num_shifted_limbs` > `N`
pub(crate) unconstrained fn __shl<let N: u32>(input: &[u128; N], shift: u32) -> [u128; N] {
    let mut result: [u128; N] = [0; N];

    let num_shifted_limbs: u32 = shift / 120;
    let limb_shift: u128 = (shift % 120) as u128;
    let remainder_shift: u128 = 120 - limb_shift;

    let mask: u128 = TWO_POW_120 - 1;
    let mut remainder: u128 = input[0] >> remainder_shift;

    result[num_shifted_limbs] = (input[0] << limb_shift) & mask;

    for i in 1..(N - num_shifted_limbs) {
        let value: u128 = input[i];
        let upshift: u128 = ((value << limb_shift) | remainder) & mask;
        result[i + num_shifted_limbs] = upshift;
        remainder = value >> remainder_shift;
    }
    result
}

/// Right-shifts a `BigInt` value by `shift` bits (unconstrained).
///
/// Performs a bitwise right shift across limbs.
///
/// # Note
/// No bounds check is performed on `num_shifted_limbs`.
/// Callers must ensure that `shift / 120 < N`
pub(crate) unconstrained fn __shr<let N: u32>(input: &[u128; N], shift: u32) -> [u128; N] {
    let mut result: [u128; N] = [0; N];

    let num_shifted_limbs: u32 = shift / 120;
    let limb_shift: u128 = (shift % 120) as u128;

    let remainder_shift: u128 = 120 - limb_shift;
    let low_mask: u128 = (1 as u128 << limb_shift) - 1;

    result[0] = input[num_shifted_limbs] >> limb_shift;
    for i in 1..(N - num_shifted_limbs) {
        let value: u128 = input[i + num_shifted_limbs];

        let carry: u128 = (value & low_mask) << remainder_shift;
        result[i - 1] |= carry;

        result[i] = value >> limb_shift;
    }
    result
}

/// Right-shifts a `BigInt` value by `1` bit  (unconstrained)
///
/// # Note
/// All the operations on limbs are executed in place
/// to save opcodes
pub(crate) unconstrained fn __shr1<let N: u32>(mut input: [u128; N]) -> [u128; N] {
    let value: u128 = input[N - 1];
    let mut remainder: u128 = (value & 1) << 119;
    input[N - 1] >>= 1;

    for i in 1..N {
        let value: u128 = input[N - 1 - i];
        input[N - 1 - i] = (value >> 1) | remainder;
        remainder = (value & 1) << 119;
    }
    input
}

/// Returns the index of the most significant set bit in a `BigInt` value (unconstrained).
pub(crate) unconstrained fn __get_msb<let N: u32>(val: &[u128; N]) -> u32 {
    let mut count: u32 = 0;
    for i in 0..N {
        let idx: u32 = N - 1 - i;
        let v: u128 = val[idx];
        if (v > 0) {
            count = 120 * idx + get_msb(v);
            break;
        }
    }
    count
}

/// Returns `true` if the bit at position `bit` is set in the `BigInt` (unconstrained).
///
/// ## Note
/// No bounds check is performed on `bit`
pub(crate) fn __get_bit<let N: u32>(input: &[u128; N], bit: u32) -> bool {
    let segment_index: u32 = bit / 120;
    let uint_index: u128 = (bit % 120) as u128;

    let limb: u128 = input[segment_index];
    let value: u128 = (limb >> uint_index) & 1;
    value == 1
}
