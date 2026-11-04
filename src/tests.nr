use crate::bigint::BigInt;
use crate::bigint::derive_bigint;
use crate::bigint::{evaluate_quadratic_expression, to_field};
use crate::constants::{GRUMPKIN_MODULUS, TWO_POW_120, TWO_POW_240};
use crate::fns::constrained_ops::{from_field, validate_gt};
use crate::fns::expressions::{assert_product_limbs_fit_in_246_bits, validate_udiv_mod_expression};
use crate::fns::modulus::get_modulus;
use crate::fns::unconstrained_helpers::__helper_add;

use crate::types::U2048::U2048;
use crate::types::U256::U256;
use crate::types::U512::U512;

// Test-only unsigned integer types. Every shipped type is at least 256 bits wide, but some code
// paths only apply to narrower widths:
//
// - `U252`: a width below the native field, and not a multiple of 8. It covers `to_field` and
//   `from_field` skipping the comparison against the Grumpkin modulus, byte conversions
//   range-checking the bits of the most significant byte, and `derive_from_seed` masking the
//   bits of the top limb (which holds 12 bits).
// - `U253`: the widest type whose values always fit within the native field, as `2^253` is the
//   largest power of two below the Grumpkin modulus. It covers `from_field` relying on the range
//   check alone at that boundary.

// A 252-bit unsigned integer
#[derive_bigint(252)]
pub struct U252 {
    limbs: [u128; 3],
}

// A 253-bit unsigned integer
#[derive_bigint(253)]
pub struct U253 {
    limbs: [u128; 3],
}

// 2^256 - 1
global U256_MAX: [u128; 3] = [TWO_POW_120 - 1, TWO_POW_120 - 1, 0xffff];

// ------------------------------ REGRESSION TESTS ------------------------------

#[test]
fn test_sub_underflow_regression() {
    let limbs: [u128; 3] =
        [605231426910671071918217543292637230, 925169190305713195541137574269511054, 4915];
    let a: U256 = U256::from_limbs(limbs);
    let b: U256 = U256::from_limbs(limbs);
    let c: U256 = b - a;
    assert(c.get_limbs() == [0, 0, 0]);
}

// Tests to confirm that we can no longer pass more than 1 extra `MOD` as a part of the witness

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_evaluate_quadratic_expression_add_extra_mod_fuzz(xseed: [u8; 4], yseed: [u8; 3]) {
    let x: U256 = U256::derive_from_seed(xseed);
    let y: U256 = U256::derive_from_seed(yseed);

    let modulus: [u128; 3] = get_modulus::<3, 256>();

    // compute honest z = x + y (mod MOD)
    // Safety: test code
    let mut z_: [u128; 3] = unsafe { x.__add(&y).get_limbs() };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };

    let z: U256 = U256::from_limbs_unsafe(z_);

    evaluate_quadratic_expression([[]], [[]], [[]], [[]], [x, y, z], [false, false, true]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_evaluate_quadratic_expression_mul_extra_mod_fuzz(xseed: [u8; 1], yseed: [u8; 2]) {
    let x: U256 = U256::derive_from_seed(xseed);
    let y: U256 = U256::derive_from_seed(yseed);

    let modulus: [u128; 3] = get_modulus::<3, 256>();

    // compute honest z = x * y (mod MOD)
    // Safety: test code
    let mut z_: [u128; 3] = unsafe { x.__mul(&y).get_limbs() };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };

    let z: U256 = U256::from_limbs_unsafe(z_);

    evaluate_quadratic_expression([[x]], [[false]], [[y]], [[false]], [z], [true]);
}

// This tests that we no longer validate udiv_mod expression `(mod MOD)`
// This would have passed previously with `evaluate_quadratic_expression` call
#[test(should_fail)]
fn test_udiv_mod_extra_modulus_regression(xseed: [u8; 1], yseed: [u8; 2]) {
    let x: U256 = U256::derive_from_seed(xseed);
    let y: U256 = U256::derive_from_seed(yseed);

    let modulus: [u128; 3] = get_modulus::<3, 256>();

    // compute honest z = x * y (mod MOD)
    // Safety: test code
    let (q, r): (U256, U256) = unsafe { x.__udiv_mod(&y) };

    let mut q_: [u128; 3] = q.get_limbs();
    // Safety: test code
    q_ = unsafe { __helper_add(&q_, &modulus) };

    validate_udiv_mod_expression::<3, 256>(&x.get_limbs(), &y.get_limbs(), &q_, &r.get_limbs());
}

// This tests that `validate_gt` no longer accepts identical inputs
#[test(should_fail)]
fn test_validate_gt_regression_U256() {
    let x: U256 = U256::derive_from_seed([1, 2, 3, 4]);
    let y: U256 = U256::derive_from_seed([1, 2, 3, 4]);
    let x_limbs = x.get_limbs();
    let y_limbs = y.get_limbs();
    validate_gt::<3, 256>(&x_limbs, &y_limbs);
}

// Regression tests for evaluate_quadratic_expression overflow detection.
// When LHS_N, RHS_N, or NUM_PRODUCTS are too large, `assert_product_limbs_fit_in_246_bits`
// rejects the expression before any witness values are inspected. Zero inputs are
// therefore sufficient to exercise the check.
#[test(should_fail_with = "product limbs may exceed 2^246")]
fn test_evaluate_quadratic_expression_overflow_num_products_U256() {
    let zero: U256 = BigInt::new();
    // NUM_PRODUCTS=33, LHS_N=1, RHS_N=1
    // Fails the (N-2)th limb check: 33 * 2 * (2^120-1)^2 > 2^246
    evaluate_quadratic_expression(
        [[zero]; 33],
        [[false]; 33],
        [[zero]; 33],
        [[false]; 33],
        [],
        [],
    );
}

#[test(should_fail_with = "product limbs may exceed 2^246")]
fn test_evaluate_quadratic_expression_overflow_num_products_U256_2() {
    let zero: U256 = BigInt::new();
    // NUM_PRODUCTS=1, LHS_N=6, RHS_N=6
    // Fails the (N-2)th limb check: 1 * 6 * 6 * 2 * (2^120-1)^2 > 2^246
    evaluate_quadratic_expression([[zero; 6]], [[false; 6]], [[zero; 6]], [[false; 6]], [], []);
}

// The (N-1)th limb bound only dominates when `TOP_LIMB_BITS + 1 == 120`, i.e. when
// `BITS = N * 120 - 1`. None of the shipped `BigInt` types hit that case, so we
// exercise the check directly via `assert_product_limbs_fit_in_246_bits` with a
// synthetic `<N, BITS>` pair.
//
// With N=3, BITS=359, LHS_N=RHS_N=1, NUM_PRODUCTS=22:
//   - (N-2)th bound: 22 * 2 * (2^120-1)^2 ~ 44 * 2^240 < 2^246  (passes)
//   - (N-1)th bound: 22 * 3 * (2^120-1)^2 ~ 66 * 2^240 > 2^246  (fails first)
#[test(should_fail_with = "product limbs may exceed 2^246 at limb 2")]
fn test_assert_product_limbs_fit_in_246_bits_n_minus_1() {
    assert_product_limbs_fit_in_246_bits::<3, 359, 1, 1, 22>();
}

// from_field must reject values >= 2^BITS, even when they are smaller than the Grumpkin modulus.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_field_regression() {
    // 2^253 + 5
    let value: Field = 0x2000 * TWO_POW_240 + 5;
    let _: [u128; 3] = from_field::<3, 253>(value);
}

// ------------------------------ COMPLETENESS TESTS ------------------------------

// (-1 * -1) + (-1 * -1) + ... - 20 = 0
// Many negated terms must not overflow the limb borrow/carry bounds for a valid expression.
#[test]
fn test_evaluate_quadratic_expression_many_negated_terms() {
    let one: U256 = U256::one();
    let v: U256 = BigInt::from_limbs([20 as u128, 0, 0]);

    let lhs_terms: [[U256; 1]; 20] = [[one; 1]; 20];
    let lhs_flags: [[bool; 1]; 20] = [[true; 1]; 20];
    let rhs_terms: [[U256; 1]; 20] = [[one; 1]; 20];
    let rhs_flags: [[bool; 1]; 20] = [[true; 1]; 20];
    let linear_terms: [U256; 1] = [v];
    let linear_flags: [bool; 1] = [true];
    evaluate_quadratic_expression(
        lhs_terms,
        lhs_flags,
        rhs_terms,
        rhs_flags,
        linear_terms,
        linear_flags,
    );
}

// ------------------------------ BASIC TESTS ------------------------------

#[test]
fn test_bits_U256() {
    assert_eq(<U256 as BigInt>::BITS, 256)
}

#[test]
fn test_num_limbs_U256() {
    assert_eq(U256::zero().num_limbs(), 3)
}

#[test]
fn test_get_limbs_U256() {
    let test_value: U256 = U256::from_limbs([0, 1, 2]);
    assert_eq(test_value.get_limbs(), [0, 1, 2]);
    assert_eq(test_value.get_limb(0), 0);
    assert_eq(test_value.get_limb(1), 1);
    assert_eq(test_value.get_limb(2), 2);
}

#[test]
fn test_set_limb_U256() {
    let mut test_value: U256 = U256::from_limbs([0, 1, 2]);
    test_value.set_limb(0, 3);
    assert_eq(test_value.get_limb(0), 3);
}

// ------------------------------ DERIVATION TESTS ------------------------------

#[test]
fn test_derive_from_seed() {
    let seed: [u8; 4] = [1, 2, 3, 4];
    let result_bn: U256 = BigInt::derive_from_seed(seed);
    result_bn.validate_in_range();
}

#[test]
fn test_validate_derive_from_seed() {
    let seed: [u8; 4] = [1, 2, 3, 4];
    let result_bn: U256 = U256::derive_from_seed(seed);
    assert(result_bn.get_limb(0) == 0xfd2a2cad9bdafe1cf39def3d71793a);
    assert(result_bn.get_limb(1) == 0xb2b0e456e76ec08043511c2c398ef6);
    assert(result_bn.get_limb(2) == 0x000000000000000000000000009093);
}

// `derive_from_seed` must mask the bits of the most significant byte of the top limb when its
// width is not a multiple of 8: the top limb of a `U252` holds 12 bits. The constrained and
// unconstrained implementations must also agree.
#[test]
fn test_derive_from_seed_masks_top_limb() {
    let mut max_top_limb: u128 = 0;
    for i in 0..32 {
        let seed: [u8; 2] = [i as u8, 7];
        let a: U252 = U252::derive_from_seed(seed);
        // Safety: test code
        let b: U252 = unsafe { U252::__derive_from_seed(seed) };
        assert(a == b);
        if a.get_limb(2) > max_top_limb {
            max_top_limb = a.get_limb(2);
        }
    }
    assert(max_top_limb < 0x1000);
    // With 32 samples, the top limb uses its high bits as well (otherwise the mask is too narrow)
    assert(max_top_limb >= 0x800);
}

// ------------------------------ LIMB ACCESS TESTS ------------------------------

// from_limbs must reject limbs that exceed the valid range.
#[test(should_fail)]
fn test_from_limbs_rejects_oversized_top_limb() {
    // U256 top limb is 16 bits, 0x10000 = 2^16 exceeds that
    let _: U256 = U256::from_limbs([0, 0, 0x10000]);
}

// from_limbs_unsafe accepts limbs that exceed the valid range.
#[test]
fn test_from_limbs_unsafe_accepts_oversized_top_limb() {
    let _: U256 = U256::from_limbs_unsafe([0, 0, 0x10000]);
}

// set_limb must reject a value that exceeds the valid range for the top limb.
#[test(should_fail)]
fn test_set_limb_rejects_oversized_top_limb() {
    let mut a: U256 = U256::zero();
    a.set_limb(2, 0x10000);
}

// set_limb must reject a value that exceeds 120 bits for a non-top limb.
#[test(should_fail)]
fn test_set_limb_rejects_oversized_non_top_limb() {
    let mut a: U256 = U256::zero();
    a.set_limb(0, TWO_POW_120);
}

// set_limb_unsafe accepts values that exceed the valid range.
#[test]
fn test_set_limb_unsafe_accepts_oversized() {
    let mut a: U256 = U256::zero();
    a.set_limb_unsafe(2, 0x10000);
    assert(a.get_limb(2) == 0x10000);
}

// ------------------------------ CONVERSION TESTS ------------------------------

#[test]
fn test_from_field_1_digit() {
    let field: Field = 1;
    let result: U256 = U256::from(field);
    assert(result == U256::one());
}

#[test]
fn test_from_field_2_digits() {
    let field: Field = 762576765071760201410184025311678064293966151975347778787092903729041075;
    let result: U256 = U256::from(field);
    let expected: U256 = U256::from_limbs([
        0xe88ed97f8f707abd3fa65763c80eb3,
        0x6e7d8b5586595aa1fb2ee04d5cb4f5,
        0x0,
    ]);
    assert(result == expected);
}

#[test]
fn test_from_field_3_digits() {
    let field: Field = -1;
    let result: U256 = U256::from(field);
    let expected: U256 = U256::from_limbs([
        0x33e84879b9709143e1f593f0000000,
        0x4e72e131a029b85045b68181585d28,
        0x3064,
    ]);
    assert(result == expected);
}

#[test]
fn test_from_field_5_digits() {
    let field: Field = -1;
    let result: U512 = U512::from(field);
    let expected: U512 = U512::from_limbs([
        0x33e84879b9709143e1f593f0000000,
        0x4e72e131a029b85045b68181585d28,
        0x3064,
        0x0,
        0x0,
    ]);
    assert(result == expected);
}

// BITS < 253: validated by the range check alone.
#[test]
fn test_from_field_bits_lt_253() {
    // 2^252 - 1
    let max: Field = 0x1000 * TWO_POW_240 - 1;
    let result: [u128; 3] = from_field::<3, 252>(max);
    assert(result == [TWO_POW_120 - 1, TWO_POW_120 - 1, 0xfff]);
}

// BITS > 253: validates via validate_gt(GRUMPKIN, result).
#[test]
fn test_from_field_bits_gt_253() {
    let result: [u128; 5] = from_field::<5, 512>(-1 as Field);
    assert(result[0] == GRUMPKIN_MODULUS[0] - 1);
    assert(result[1] == GRUMPKIN_MODULUS[1]);
    assert(result[2] == GRUMPKIN_MODULUS[2]);
    assert(result[3] == 0);
    assert(result[4] == 0);
}

// BITS == 253: 2^253 is smaller than the Grumpkin modulus, so the range check alone suffices.
#[test]
fn test_from_field_bits_eq_253() {
    // 2^253 - 1
    let max: Field = 0x2000 * TWO_POW_240 - 1;
    let result: [u128; 3] = from_field::<3, 253>(max);
    assert(result == [TWO_POW_120 - 1, TWO_POW_120 - 1, 0x1fff]);

    let result: U253 = U253::from(max);
    assert_eq(to_field(result), max);
}

// BITS == 253: values in [2^253, GRUMPKIN_MODULUS) are rejected.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_field_bits_eq_253_rejects_neg_one() {
    let _: U253 = U253::from(-1);
}

#[test]
fn test_to_field_one() {
    let field: Field = 1;
    let bn: U256 = U256::one();
    let result: Field = to_field(bn);
    assert(result == field);
}

#[test]
fn test_to_field_one_digit() {
    let field: Field = 1066513542066841864585910935480267774;
    let bn: U256 = U256::from_limbs([0xcd672d695ef3129e4c40867a7173fe, 0x0, 0x0]);
    let result: Field = to_field(bn);
    assert(result == field);
}

#[test]
fn test_to_field_two_digits() {
    let field: Field = 697955470585821007263499235110798476786097877002667034107578965871052378;
    let bn: U256 = U256::from_limbs([
        0x5a10b956d41840745e0a9f6e34465a,
        0x65209b74583b912262843211905e41,
        0x0,
    ]);
    let result = to_field(bn);
    assert(result == field);
}

#[test]
fn test_to_field_three_digits() {
    let field: Field = 2330301921655783950764183713945533646391233209687308929386184468126823563744;
    let bn: U256 = U256::from_limbs([
        0x862cf8ea69d6c70c9cc8d8871b41e0,
        0xe7763528201566c2fc8d93973cf1b4,
        0x526,
    ]);
    let result = to_field(bn);
    assert(result == field);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_to_field_three_digits_overflow() {
    let bn: U256 = U256::from_limbs([
        0x4e6405505a33bb9b9c0563df2bd59a,
        0x48dbe03a9bb4865ba961e41ef9dded,
        0x3a36,
    ]);
    let _: Field = to_field(bn);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_to_field_too_many_digits() {
    let bn: U512 = U512::from_limbs([
        0xea1742447ee9d92f9f18e1c80a481e,
        0x3d89ad3d3ae85f3f482a08435c93ec,
        0x1e9f,
        0x1,
        0x0,
    ]);
    let _: Field = to_field(bn);
}

#[test]
fn test_from_to_field_1() {
    let a: Field = 20192735083400333763152317277081729935089452774154199134677444560763605803197;
    let b: U256 = U256::from(a);
    let c: Field = to_field(b);
    assert(c == a);
}

#[test]
fn test_from_to_field_fuzz(a: Field) {
    let b: U512 = U512::from(a);
    let c: Field = to_field(b);
    assert(c == a);
}

#[test]
fn test_to_from_field_1() {
    let a: U256 = U256::from_limbs([
        0x3c768db7732ea1b536c06ae66bce70,
        0xb9936c1401d91e7e9e1138375650b4,
        0x8c8,
    ]);
    let b: Field = to_field(a);
    let c: U256 = U256::from(b);
    assert(a == c);
}

#[test]
fn test_to_from_field_2() {
    let a: U512 = U512::from_limbs([
        0xd7562bf2b1fe13d458685c96a46d28,
        0x2079950acd45bb43a9beeba69d5dc9,
        0x18ca,
        0x0,
        0x0,
    ]);
    let b: Field = to_field(a);
    let c: U512 = U512::from(b);
    assert(a == c);
}

/// `U252` has `BITS = 252` and `N = 3`, so every value is below the Grumpkin
/// modulus by construction and `to_field` must not attempt (and fail) to compare against it.
#[test]
fn test_to_field_bits_below_254() {
    let one = U252::one();
    assert_eq(to_field(one), 1);

    // the largest representable value, `2^252 - 1`
    let U252_MODULUS_MINUS_ONE: Field =
        0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    let max = U252::zero() - U252::one();
    assert_eq(to_field(max), U252_MODULUS_MINUS_ONE);
}

#[test]
fn fuzz_to_from_field_bits_below_254(seed: [u8; 5]) {
    let a: U252 = U252::derive_from_seed(seed);
    let b: Field = to_field(a);
    let c: U252 = U252::from(b);
    assert_eq(a, c);
}

#[test]
fn fuzz_from_le_bytes(seed: [u8; 5]) {
    let a: U256 = U256::derive_from_seed(seed);
    let bytes: [u8; 32] = a.to_le_bytes();
    let b: U256 = U256::from_le_bytes(bytes);
    assert(a == b);
}

#[test]
fn fuzz_to_be_bytes(seed: [u8; 5]) {
    let a: U256 = U256::derive_from_seed(seed);
    let bytes: [u8; 32] = a.to_be_bytes();
    let b: U256 = U256::from_be_bytes(bytes);
    assert(a == b);
}

// Byte conversions must reject values >= 2^BITS when BITS is not a multiple of 8.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_be_bytes_rejects_out_of_range() {
    let mut bytes: [u8; 32] = [0; 32];
    // 2^252
    bytes[0] = 0x10;
    let _: U252 = U252::from_be_bytes(bytes);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_le_bytes_rejects_out_of_range() {
    let mut bytes: [u8; 32] = [0; 32];
    // 2^252
    bytes[31] = 0x10;
    let _: U252 = U252::from_le_bytes(bytes);
}

#[test]
fn test_from_be_bytes_max_U252() {
    let mut bytes: [u8; 32] = [0xff; 32];
    bytes[0] = 0x0f;
    let a: U252 = U252::from_be_bytes(bytes);
    assert(a == U252::zero() - U252::one());
    assert(a.to_be_bytes() == bytes);
}

// 2^BITS is not representable.
fn test_from_limbs_rejects_two_pow_bits<let N: u32, BN>()
where
    BN: BigInt,
{
    let _: BN = BN::from_limbs(get_modulus::<<BN as BigInt>::N, <BN as BigInt>::BITS>());
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_limbs_rejects_two_pow_bits_U256() {
    test_from_limbs_rejects_two_pow_bits::<3, U256>();
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_limbs_rejects_two_pow_bits_U2048() {
    test_from_limbs_rejects_two_pow_bits::<18, U2048>();
}

// ------------------------------ COMPARISON TESTS ------------------------------

// `[2^120, 0, 0]` and `[0, 1, 0]` both encode the integer `2^120`. Such unnormalised values can
// reach `eq` and `cmp` via circuit inputs or unconstrained functions, so these must reject them
// rather than report the values as distinct.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_eq_rejects_unnormalised_limbs() {
    let a: U256 = U256::from_limbs_unsafe([TWO_POW_120, 0, 0]);
    let b: U256 = U256::from_limbs_unsafe([0, 1, 0]);
    assert(a != b);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_cmp_rejects_unnormalised_limbs() {
    let a: U256 = U256::from_limbs_unsafe([TWO_POW_120, 0, 0]);
    let b: U256 = U256::from_limbs_unsafe([0, 1, 0]);
    assert(a > b);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_cmp_rejects_unnormalised_limbs_reversed() {
    let a: U256 = U256::from_limbs_unsafe([TWO_POW_120, 0, 0]);
    let b: U256 = U256::from_limbs_unsafe([0, 1, 0]);
    assert(b > a);
}

fn test_eq<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let c: BN = BN::derive_from_seed([2, 2, 3, 4]);

    assert(a.eq(b) == true);
    assert(c.eq(b) == false);
    assert(c.eq(a) == false);
}

fn test_is_zero<let N: u32, BN>()
where
    BN: BigInt,
{
    let zero: BN = BN::zero();
    assert(zero.is_zero() == true);

    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    assert(a.is_zero() == false);
    a.assert_is_not_zero();
}

fn test_assert_is_not_equal<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([4, 5, 6, 7]);

    a.assert_is_not_equal(&b);
}

fn test_assert_is_not_equal_fail<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([1, 2, 3, 4]);

    a.assert_is_not_equal(&b);
}

#[test]
fn test_cmp_lt_U256() {
    let mut a: U256 = U256::from_limbs(U256_MAX);
    let mut b: U256 = U256::from_limbs(U256_MAX);

    a.set_limb(0, a.get_limb(0) - 2);
    b.set_limb(0, b.get_limb(0) - 1);

    assert(a < b);
}

#[test(should_fail_with = "Failed constraint")]
fn test_cmp_lt_U256_fail() {
    let mut a: U256 = U256::from_limbs(U256_MAX);
    let mut b: U256 = U256::from_limbs(U256_MAX);

    a.set_limb(0, a.get_limb(0) - 1);
    b.set_limb(0, b.get_limb(0) - 2);

    assert(a < b);
}

#[test]
fn test_cmp_gt_U256() {
    let mut a: U256 = U256::from_limbs(U256_MAX);
    let mut b: U256 = U256::from_limbs(U256_MAX);

    a.set_limb(0, a.get_limb(0) - 1);
    b.set_limb(0, b.get_limb(0) - 2);

    assert(a > b);
}

#[test(should_fail_with = "Failed constraint")]
fn test_cmp_gt_U256_fail() {
    let mut a: U256 = U256::from_limbs(U256_MAX);
    let mut b: U256 = U256::from_limbs(U256_MAX);

    a.set_limb(0, a.get_limb(0) - 2);
    b.set_limb(0, b.get_limb(0) - 1);

    assert(a > b);
}

#[test]
fn test_cmp_U256_fuzz(seed: [u8; 5]) {
    let mut a: U256 = U256::derive_from_seed(seed);
    let modulus_sub_1_div_2: U256 = U256::from_limbs(U256_MAX) / U256::from(2);

    a = if a > modulus_sub_1_div_2 {
        U256::from_limbs(U256_MAX) - a
    } else {
        a
    };
    assert(a < modulus_sub_1_div_2);
}

#[test]
fn test_cmp_equal() {
    let a: U256 = U256::derive_from_seed([1, 2, 3]);
    let b: U256 = U256::derive_from_seed([1, 2, 3]);
    let c: bool = a < b;
    assert(c == false);
}

#[test]
fn fuzz_cmp_equal(seed: [u8; 5]) {
    let a: U256 = U256::derive_from_seed(seed);
    let b: U256 = U256::derive_from_seed(seed);
    let c: bool = a < b;
    assert(c == false);
}

// ------------------------------ ARITHMETIC TESTS ------------------------------

#[test]
fn test_do_nothing() {
    let a: U256 = U256::from_limbs([1, 2, 0]);
    let b: U256 = U256::from_limbs([1, 2, 0]);
    // Safety: test code
    let c: [u128; 3] = unsafe { __helper_add(&a.get_limbs(), &b.get_limbs()) };
    // Safety: test code
    let d: U256 = unsafe { a.__add(&b) };
    let e: U256 = a + b;
    assert(c == d.get_limbs());
    assert(c == e.get_limbs());
}

fn test_add<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([4, 5, 6, 7]);
    let one: BN = BN::one();
    a.validate_in_range();
    b.validate_in_range();

    let mut c: BN = (a + b);
    c += c;
    let d: BN = (a + b) * (one + one);
    assert(c == d);

    let e: BN = one + one;
    let limbs = e.get_limbs();
    let mut true_limbs = [0; <BN as BigInt>::N];
    true_limbs[0] = 2;
    assert_eq(limbs, true_limbs);
}

#[test]
fn test_add_U256_max() {
    // (2^256 - 1) + (2^256 - 1) = 2^256 - 2 (mod 2^256)
    let a: U256 = U256::from_limbs(U256_MAX);
    let b: U256 = U256::from_limbs(U256_MAX);

    let mut expected: U256 = U256::from_limbs(U256_MAX);
    expected.set_limb(0, expected.get_limb(0) - 1);

    let c: U256 = a + b;
    assert(c == expected);
}

#[test]
fn test_add_U256_wrap_around() {
    // (2^256 - 2) + 3 = 1 (mod 2^256)
    let mut a: U256 = U256::from_limbs(U256_MAX);
    let b: U256 = U256::from_limbs([3, 0, 0]);
    let expected: U256 = U256::one();

    a.set_limb(0, a.get_limb(0) - 1);

    let c: U256 = a + b;

    assert(c == expected);
}

#[test]
fn test_sub_U256() {
    // 0 - 1 should equal 2^256 - 1
    let a: U256 = U256::zero();
    let b: U256 = U256::one();
    let expected: U256 = U256::from_limbs(U256_MAX);
    let result: U256 = a - b;
    assert(result == expected);
}

fn test_mul<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([4, 5, 6, 7]);
    let c: BN = (a + b) * (a + b);
    let d: BN = (a * a) + (b * b) + (a * b) + (b * a);
    assert(c.eq(d));
}

fn test_sqr<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = BN::derive_from_seed([1, 2, 3, 4]);
    let b: BN = BN::derive_from_seed([4, 5, 6, 7]);
    let c: BN = (a + b).sqr();
    let d: BN = a.sqr() + b.sqr() + (a * b) + (b * a);
    assert(c == d);
}

#[test]
fn test_mul_U256_with_one() {
    let a: U256 = U256::zero() - (U256::one() + U256::one());
    let b: U256 = U256::one();
    let c: U256 = a * b;
    assert(c == a);
}

fn test_div_udiv_mod_equality<let N: u32, BN>()
where
    BN: BigInt,
{
    let mut a: BN = BN::zero();
    a.set_limb(0, 0x1000);

    let two: BN = BN::one() + BN::one();

    let c: BN = a / two;
    let (d, _): (BN, BN) = a.udiv_mod(&two);

    assert(c == d);
}

#[test]
fn test_udiv_mod_U256() {
    let a: U256 = U256::from_limbs([
        0xec0ca0c0adce359af6fcea1a7ab2dc,
        0xdd52c4aa3fde93685d3f7cc285de32,
        0x6fea,
    ]);
    let b: U256 = U256::from_limbs([12, 0, 0]);

    let (q, r): (U256, U256) = a.udiv_mod(&b);

    // Safety: test code
    let product: U256 = unsafe { q.__mul(&b).__add(&r) };
    assert(product == a);
}

#[test]
fn test_1_udiv_mod_2() {
    let _0: U256 = U256::zero();
    let _1: U256 = U256::one();
    let _2: U256 = _1 + _1;
    assert(_1.udiv_mod(&_2) == (_0, _1));
}

#[test]
fn test_20_udiv_mod_11() {
    let _1: U256 = U256::one();
    let _2_POW_120: U256 = U256::from_limbs([0, 1, 0]);
    let _2_POW_121: U256 = U256::from_limbs([0, 2, 0]);
    let divisor: U256 = _2_POW_120 + _1;
    assert(_2_POW_121.udiv_mod(&divisor) == (_1, _2_POW_120 - _1));
}

//// Set up parametrized tests

// U256

#[test]
fn test_eq_U256() {
    test_eq::<3, U256>();
}

#[test]
fn test_is_zero_U256() {
    test_is_zero::<3, U256>();
}

#[test]
fn test_assert_is_not_equal_U256() {
    test_assert_is_not_equal::<3, U256>();
}

#[test(should_fail_with = "assert_is_not_equal fail")]
fn test_assert_is_not_equal_fail_U256() {
    test_assert_is_not_equal_fail::<3, U256>();
}

#[test]
fn test_add_U256() {
    test_add::<3, U256>();
}

#[test]
fn test_mul_U256() {
    test_mul::<3, U256>();
}

#[test]
fn test_sqr_U256() {
    test_sqr::<3, U256>();
}

#[test]
fn test_div_udiv_mod_equality_U256() {
    test_div_udiv_mod_equality::<3, U256>();
}

// U2048

#[test]
fn test_eq_U2048() {
    test_eq::<18, U2048>();
}

#[test]
fn test_is_zero_U2048() {
    test_is_zero::<18, U2048>();
}

#[test]
fn test_assert_is_not_equal_U2048() {
    test_assert_is_not_equal::<18, U2048>();
}

#[test(should_fail_with = "assert_is_not_equal fail")]
fn test_assert_is_not_equal_fail_U2048() {
    test_assert_is_not_equal_fail::<18, U2048>();
}

#[test]
fn test_add_U2048() {
    test_add::<18, U2048>();
}

#[test]
fn test_mul_U2048() {
    test_mul::<18, U2048>();
}

#[test]
fn test_sqr_U2048() {
    test_sqr::<18, U2048>();
}

#[test]
fn test_div_udiv_mod_equality_U2048() {
    test_div_udiv_mod_equality::<18, U2048>();
}

// Other

#[test]
fn test_mul_u1024() {
    test_mul::<9, crate::types::U1024::U1024>();
}

#[test]
fn test_mul_u4096() {
    test_mul::<35, crate::types::U4096::U4096>();
}

#[test]
fn test_mul_u512() {
    test_mul::<5, crate::types::U512::U512>();
}

// ------------------------------ EXPRESSIONS TESTS ------------------------------

#[test]
fn test_expressions() {
    let y: U256 = U256::from_limbs([0x1, 0x1, 0x0]);
    let z: U256 = U256::from_limbs([0x2, 0x2, 0x0]);
    // Safety: test code
    let yy: U256 = unsafe { y.__add(&y) };

    assert(yy.get_limbs() == z.get_limbs());

    let uu: U256 = U256::from_limbs([
        0x0000000000000000000000000000000000b4a832748da6ad742a1fd81b787643,
        0x00000000000000000000000000000000009575f594e04080471712c1d7f18e89,
        0x000000000000000000000000000000000000000000000000000000000000063,
    ]);
    let vv: U256 = U256::from_limbs([
        0x0000000000000000000000000000000000b4aec2748da6ad742a1fd81b787643,
        0x00000000000000000000000000000000009575f594e0408047171a01d7f18e89,
        0x0000000000000000000000000000000000000000000000000000000000000062,
    ]);

    let w: U256 = U256::from_limbs([
        0x0000000000000000000000000000000000b4a832748da6ad742a1fd81b787643,
        0x00000000000000000000000000000000009575f594e04080471712c1d7f18e89,
        0x0000000000000000000000000000000000000000000000000000000000001f93,
    ]);
    let x: U256 = U256::from_limbs([
        0x0000000000000000000000000000000000b4aec2748da6ad742a1fd81b787643,
        0x00000000000000000000000000000000009575f594e0408047171a01d7f18e89,
        0x0000000000000000000000000000000000000000000000000000000000000f93,
    ]);
    // Safety: test code
    let wx: U256 = unsafe { w.__mul(&x) };
    // Safety: test code
    let uv: U256 = unsafe { uu.__mul(&vv) };
    // Safety: test code
    let y: U256 = unsafe { U256::zero().__sub(&uv.__add(&wx)) };
    // Safety: test code
    let z: U256 = unsafe { uv.__add(&wx) };

    evaluate_quadratic_expression(
        [[uu], [w]],
        [[false], [false]],
        [[vv], [x]],
        [[false], [false]],
        [z],
        [true],
    );
    evaluate_quadratic_expression(
        [[uu], [w]],
        [[false], [false]],
        [[vv], [x]],
        [[false], [false]],
        [y],
        [false],
    );

    let wx_constrained = w * x;
    assert(wx_constrained.get_limbs() == wx.get_limbs());
}

#[test]
fn test_2048_bit_quadratic_expression() {
    let a: [u128; 18] = [
        0x000000000000000000000000000000000083684820ff40795b8d9f1be2220cba,
        0x0000000000000000000000000000000000d4924fbdc522b07b6cd0ef5508fd66,
        0x0000000000000000000000000000000000d48f6c43c5930f3d70d6db09a48f4a,
        0x0000000000000000000000000000000000e7f72b2c0756704bea85be38352b34,
        0x00000000000000000000000000000000008337197826e2e9ea000ed5b05d5ac5,
        0x000000000000000000000000000000000040680101b43f6d17de8e3507f3d820,
        0x00000000000000000000000000000000000c6ba0cdcf77cff1c10355ea48d387,
        0x0000000000000000000000000000000000e51717a72902214a9dbeb90e4f225f,
        0x0000000000000000000000000000000000c1bd5bec78406b691f71cbcddb4574,
        0x00000000000000000000000000000000001ce5e532cfb306d7b52e7d9f1aa442,
        0x000000000000000000000000000000000019575932f75ddf00595b22782e1ba2,
        0x0000000000000000000000000000000000d630b3fbf0a9e55861e4399900feb9,
        0x0000000000000000000000000000000000d6b37aeb2daa8d2e2f7e29b0f7752a,
        0x0000000000000000000000000000000000e9cacdd93406256b9eb46b73948849,
        0x00000000000000000000000000000000001400e1f0a38695db66993fe042c48b,
        0x0000000000000000000000000000000000e1d829cb4fa8cabb7d0265efbd8527,
        0x000000000000000000000000000000000055f1a92a5dd099ef2bcd89ac175b52,
        0x00000000000000000000000000000000000000000000000000000000000000fc,
    ];
    let b: [u128; 18] = [
        0x0000000000000000000000000000000000c5694493e9bcc76e68dfcf73e0fde1,
        0x0000000000000000000000000000000000ede5e4b8b3e0dec1f4705c35521620,
        0x00000000000000000000000000000000007aa800bab1b33eda0f07695af6c583,
        0x000000000000000000000000000000000045892edea2c02bf0b8b1d2d9a4ebcc,
        0x00000000000000000000000000000000004dffb06bf396f3d0a5b67cff714bdd,
        0x00000000000000000000000000000000004d691db495235e1e032f1ef3e90274,
        0x0000000000000000000000000000000000d92c069d0f2675b2f46cb497aa62d4,
        0x00000000000000000000000000000000003d3f23584f113cef1a4b8b7d183f5c,
        0x0000000000000000000000000000000000289ba11d897837f9cec57dcc430bfc,
        0x0000000000000000000000000000000000765dc64f6ed4a6efd7b26c38f79e59,
        0x00000000000000000000000000000000008edf31fabf5c330ecf7f92fb6487cd,
        0x000000000000000000000000000000000053392f8b14dd78af702b3be2e0d557,
        0x000000000000000000000000000000000034abf357bfd56e9786a7e47ed9a5ae,
        0x0000000000000000000000000000000000a9ebb234064c8ab10d4e7900d4b973,
        0x00000000000000000000000000000000002a6850cce14a20463913002ddc0fa6,
        0x0000000000000000000000000000000000a97e3b06586bfa62325ef7557ab536,
        0x0000000000000000000000000000000000b942b0d26e5be2e08cd425107c59f7,
        0x0000000000000000000000000000000000000000000000000000000000000031,
    ];
    let c_expected: [u128; 18] = [
        0x3f908a621641f3c6e0dfe61741017a,
        0x9c85afca3dfa86c40e1f6be0d5160e,
        0x331821a4d48d37aad83968ddfd0ada,
        0xb9c03895f08767ed50e75126320544,
        0xb902f31d37392d5664dca9f761f67a,
        0x0e988d51c5c3304f356af66fb4c10c,
        0x17bd900911a262bb4c2bf6722c9612,
        0x3835d5390fe7e01b2ec9bbced084d9,
        0x97143f3b35fc7fde7e610b3f0ae5c0,
        0x40173a46535deda4adea842379123e,
        0x2d896b389a37aa012ba3812c5cd8bb,
        0xbfe4b1ae75e07d5ec49972bea3ee29,
        0x7c334ec1665f7b1e40f210431428e3,
        0x9b149e0e0d01bb62f11f08a0794dea,
        0xfc55c2bee47c40ab5539460f2e90f6,
        0xf682c1dae4732070f32bb339dfe469,
        0x2c1f76c7da5f780904e777ee21c857,
        0x00000000000000000000000000000d,
    ];

    let a_bn: U2048 = U2048::from_limbs(a);
    let b_bn: U2048 = U2048::from_limbs(b);

    // Safety: test code
    let c_bn: U2048 = unsafe { a_bn.__mul(&b_bn) };

    assert(c_bn.get_limbs() == c_expected);

    evaluate_quadratic_expression([[a_bn]], [[false]], [[b_bn]], [[false]], [c_bn], [true]);
}
