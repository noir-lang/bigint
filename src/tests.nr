use crate::bigint::BigInt;
use crate::bigint::{compute_quadratic_expression, evaluate_quadratic_expression, to_field};
use crate::bigint::derive_bigint;
use crate::constants::{GRUMPKIN_MODULUS, TWO_POW_120, TWO_POW_240};
use crate::fns::constrained_ops::{
    assert_add_no_overflow, assert_sub_no_overflow, from_field, validate_gt,
};
use crate::fns::expressions::{assert_product_limbs_fit_in_246_bits, validate_mul_add_expression};
use crate::fns::unconstrained_helpers::__helper_add;

use crate::types::U1024::U1024;
use crate::types::U2048::U2048;
use crate::types::U256::U256;
use crate::types::U4096::U4096;
use crate::types::U512::U512;
use crate::types::U8192::U8192;

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
// - `U125`: a type narrower than `u128`, so `From<u128>` must reject values which do not fit.

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

// Returns the limbs of `2^BITS`, which is not representable as a `BITS`-bit `BigInt`.
fn two_pow_bits<let N: u32, let BITS: u32>() -> [u128; N] {
    let mut limbs: [u128; N] = [0; N];
    limbs[N - 1] = 1 << ((BITS - (N - 1) * 120) as u128);
    limbs
}

// A 125-bit unsigned integer, narrower than `u128`
#[derive_bigint(125)]
pub struct U125 {
    limbs: [u128; 2],
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

// Tests to confirm that a witness cannot hide an extra multiple of `2^BITS`, as the relations are
// exact and `2^BITS` is not representable

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_evaluate_quadratic_expression_add_rejects_hidden_two_pow_bits_fuzz(
    xseed: [u8; 4],
    yseed: [u8; 3],
) {
    let x: U256 = derive_from_seed(xseed);
    let y: U256 = derive_from_seed(yseed);

    let modulus: [u128; 3] = two_pow_bits::<3, 256>();

    // compute honest z = x + y
    // Safety: test code
    let mut z_: [u128; 3] = unsafe { __helper_add(&x.get_limbs(), &y.get_limbs()) };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };

    let z: U256 = U256::from_limbs_unsafe(z_);

    evaluate_quadratic_expression([[]], [[]], [[]], [[]], [x, y, z], [false, false, true]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_evaluate_quadratic_expression_mul_rejects_hidden_two_pow_bits_fuzz(
    xseed: [u8; 1],
    yseed: [u8; 2],
) {
    let x: U256 = small_from_seed(xseed);
    let y: U256 = small_from_seed(yseed);

    let modulus: [u128; 3] = two_pow_bits::<3, 256>();

    // compute honest z = x * y
    // Safety: test code
    let mut z_: [u128; 3] = unsafe { x.__mul(&y).get_limbs() };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };
    // Safety: test code
    z_ = unsafe { __helper_add(&z_, &modulus) };

    let z: U256 = U256::from_limbs_unsafe(z_);

    evaluate_quadratic_expression([[x]], [[false]], [[y]], [[false]], [z], [true]);
}

// A wrapped sum is rejected: (2^256 - 1) + 1 - 0 != 0
#[test(should_fail)]
fn test_evaluate_quadratic_expression_rejects_wrapped_sum() {
    let x: U256 = U256::from_limbs(U256_MAX);
    let y: U256 = U256::one();
    let z: U256 = U256::zero();
    evaluate_quadratic_expression([[]], [[]], [[]], [[]], [x, y, z], [false, false, true]);
}

// A wrapped product is rejected: 2^128 * 2^128 - 0 != 0
#[test(should_fail)]
fn test_evaluate_quadratic_expression_rejects_wrapped_product() {
    let x: U256 = U256::from_limbs([0, 0x100, 0]);
    let z: U256 = U256::zero();
    evaluate_quadratic_expression([[x]], [[false]], [[x]], [[false]], [z], [true]);
}

// A wrapped difference is rejected: 0 - 1 + (2^256 - 1) != 0
#[test(should_fail)]
fn test_evaluate_quadratic_expression_rejects_wrapped_difference() {
    let one: U256 = U256::one();
    let max: U256 = U256::from_limbs(U256_MAX);
    evaluate_quadratic_expression(
        [[]],
        [[]],
        [[]],
        [[]],
        [U256::zero(), one, max],
        [false, true, false],
    );
}

// The `div_rem` relation is exact, so the quotient cannot hide an extra `2^BITS`
#[test(should_fail)]
fn test_div_rem_rejects_hidden_two_pow_bits(xseed: [u8; 1], yseed: [u8; 2]) {
    let x: U256 = derive_from_seed(xseed);
    let y: U256 = derive_from_seed(yseed);

    let modulus: [u128; 3] = two_pow_bits::<3, 256>();

    // Safety: test code
    let (q, r): (U256, U256) = unsafe { x.__div_rem(&y) };

    let mut q_: [u128; 3] = q.get_limbs();
    // Safety: test code
    q_ = unsafe { __helper_add(&q_, &modulus) };

    validate_mul_add_expression::<3, 256>(&q_, &y.get_limbs(), &r.get_limbs(), &x.get_limbs());
}

// This tests that `validate_gt` no longer accepts identical inputs
#[test(should_fail)]
fn test_validate_gt_regression_U256() {
    let x: U256 = derive_from_seed([1, 2, 3, 4]);
    let y: U256 = derive_from_seed([1, 2, 3, 4]);
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
    let zero: U256 = BigInt::zero();
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
    let zero: U256 = BigInt::zero();
    // NUM_PRODUCTS=1, LHS_N=6, RHS_N=6
    // Fails the (N-2)th limb check: 1 * 6 * 6 * 2 * (2^120-1)^2 > 2^246
    evaluate_quadratic_expression([[zero; 6]], [[false; 6]], [[zero; 6]], [[false; 6]], [], []);
}

// The (N-1)th limb bound only dominates when `TOP_LIMB_BITS == 120`, i.e. when
// `BITS = N * 120`. None of the shipped `BigInt` types hit that case, so we
// exercise the check directly via `assert_product_limbs_fit_in_246_bits` with a
// synthetic `<N, BITS>` pair.
//
// With N=3, BITS=360, LHS_N=RHS_N=1, NUM_PRODUCTS=22:
//   - (N-2)th bound: 22 * 2 * (2^120-1)^2 ~ 44 * 2^240 < 2^246  (passes)
//   - (N-1)th bound: 22 * 3 * (2^120-1)^2 ~ 66 * 2^240 > 2^246  (fails first)
#[test(should_fail_with = "product limbs may exceed 2^246 at limb 2")]
fn test_assert_product_limbs_fit_in_246_bits_n_minus_1() {
    assert_product_limbs_fit_in_246_bits::<3, 360, 1, 1, 22>();
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
    assert_eq(<U256 as BigInt>::N, 3)
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

// Derives a pseudorandom value of type `BN` from `seed`, using `fns::constrained_ops::derive_from_seed`.
fn derive_from_seed<BN, let SeedBytes: u32>(seed: [u8; SeedBytes]) -> BN
where
    BN: BigInt,
{
    BN::from_limbs(
        crate::fns::constrained_ops::derive_from_seed::<<BN as BigInt>::N, <BN as BigInt>::BITS, SeedBytes>(
            seed,
        ),
    )
}

// `derive_from_seed`, executed as unconstrained code.
unconstrained fn __derive_from_seed<BN, let SeedBytes: u32>(seed: [u8; SeedBytes]) -> BN
where
    BN: BigInt,
{
    BN::from_limbs_unsafe(
        crate::fns::constrained_ops::derive_from_seed::<<BN as BigInt>::N, <BN as BigInt>::BITS, SeedBytes>(
            seed,
        ),
    )
}

#[test]
fn test_derive_from_seed() {
    let seed: [u8; 4] = [1, 2, 3, 4];
    let result_bn: U256 = derive_from_seed(seed);
    result_bn.validate_in_range();
}

#[test]
fn test_validate_derive_from_seed() {
    let seed: [u8; 4] = [1, 2, 3, 4];
    let result_bn: U256 = derive_from_seed(seed);
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
        let a: U252 = derive_from_seed(seed);
        // Safety: test code
        let b: U252 = unsafe { __derive_from_seed(seed) };
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

// Unconstrained `From<Field>` must fail for values which do not fit, as the constrained version
// does, rather than truncating them.
#[test(should_fail_with = "attempt to convert a Field which does not fit")]
unconstrained fn test_from_field_unconstrained_overflow() {
    // 2^252
    let _: U252 = U252::from(0x1000 * TWO_POW_240);
}

#[test]
unconstrained fn test_from_field_unconstrained() {
    // 2^252 - 1
    let max: Field = 0x1000 * TWO_POW_240 - 1;
    let a: U252 = U252::from(max);
    assert(a.get_limbs() == [TWO_POW_120 - 1, TWO_POW_120 - 1, 0xfff]);
    assert(U256::from(-1).get_limbs() == from_field::<3, 256>(-1));
}

// ------------------------------ CONVERSIONS FROM NATIVE INTEGERS ------------------------------

#[test]
fn test_from_native_integers() {
    let expected: U256 = U256::from(200);
    assert(U256::from(200 as u8) == expected);
    assert(U256::from(200 as u16) == expected);
    assert(U256::from(200 as u32) == expected);
    assert(U256::from(200 as u64) == expected);
    assert(U256::from(200 as u128) == expected);

    let u64_max: u64 = 0xffffffffffffffff;
    assert(U2048::from(u64_max).get_limb(0) == u64_max as u128);

    // u128::MAX = 2^128 - 1 spans two limbs
    let u128_max: u128 = 0xffffffffffffffffffffffffffffffff;
    assert(U256::from(u128_max).get_limbs() == [TWO_POW_120 - 1, 0xff, 0]);
    assert(
        U125::from(0x1fffffffffffffffffffffffffffffff as u128).get_limbs()
            == [TWO_POW_120 - 1, 0x1f],
    );
}

#[test]
unconstrained fn test_from_native_integers_unconstrained() {
    let u128_max: u128 = 0xffffffffffffffffffffffffffffffff;
    assert(U256::from(u128_max).get_limbs() == [TWO_POW_120 - 1, 0xff, 0]);
    assert(U256::from(7 as u64) == U256::from(7));
}

// A `u128` which does not fit in a 125-bit type is rejected
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_from_u128_overflow() {
    let _: U125 = U125::from(0x20000000000000000000000000000000 as u128);
}

#[test(should_fail_with = "attempt to convert a Field which does not fit")]
unconstrained fn test_from_u128_overflow_unconstrained() {
    let _: U125 = U125::from(0x20000000000000000000000000000000 as u128);
}

// ------------------------------ WIDENING CONVERSIONS ------------------------------

#[test]
fn test_widening_conversions() {
    let max: U256 = U256::from_limbs(U256_MAX);
    let wide: U512 = U512::from(max);
    assert(wide.get_limbs() == [TWO_POW_120 - 1, TWO_POW_120 - 1, 0xffff, 0, 0]);

    // Converting directly and via intermediate widths agree
    let a: U256 = derive_from_seed([1, 2, 3, 4]);
    let direct: U8192 = U8192::from(a);
    let chained: U8192 = U8192::from(U4096::from(U2048::from(U1024::from(U512::from(a)))));
    assert(direct == chained);

    // `Into` is available through `From`
    let b: U1024 = a.into();
    assert(b == U1024::from(a));
}

// Widening allows computing values which would overflow the narrower type
#[test]
fn test_widening_avoids_overflow() {
    let max: U256 = U256::from_limbs(U256_MAX);
    let wide: U512 = U512::from(max);
    // (2^256 - 1)^2 = 2^512 - 2^257 + 1
    let square: U512 = wide * wide;
    assert(square.get_limbs()[0] == 1);
    assert(square / wide == wide);
}

// Widening an unnormalised value is rejected rather than producing an unnormalised result
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_widening_rejects_unnormalised() {
    let a: U256 = U256::from_limbs_unsafe([TWO_POW_120, 0, 0]);
    let _: U512 = U512::from(a);
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
    let max = U252::from_limbs([TWO_POW_120 - 1, TWO_POW_120 - 1, 0xfff]);
    assert_eq(to_field(max), U252_MODULUS_MINUS_ONE);
}

#[test]
fn fuzz_to_from_field_bits_below_254(seed: [u8; 5]) {
    let a: U252 = derive_from_seed(seed);
    let b: Field = to_field(a);
    let c: U252 = U252::from(b);
    assert_eq(a, c);
}

#[test]
fn fuzz_from_le_bytes(seed: [u8; 5]) {
    let a: U256 = derive_from_seed(seed);
    let bytes: [u8; 32] = a.to_le_bytes();
    let b: U256 = U256::from_le_bytes(bytes);
    assert(a == b);
}

#[test]
fn fuzz_to_be_bytes(seed: [u8; 5]) {
    let a: U256 = derive_from_seed(seed);
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

// Byte conversions must not serialise an unnormalised value as a value `>= 2^BITS`: the top limb
// of a `U252` holds 12 bits, so `[0, 0, 2^13]` (i.e. 2^253) is rejected.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_to_be_bytes_rejects_out_of_range() {
    let a: U252 = U252::from_limbs_unsafe([0, 0, 0x2000]);
    let _ = a.to_be_bytes();
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_to_le_bytes_rejects_out_of_range() {
    let a: U252 = U252::from_limbs_unsafe([0, 0, 0x2000]);
    let _ = a.to_le_bytes();
}

#[test]
fn test_from_be_bytes_max_U252() {
    let mut bytes: [u8; 32] = [0xff; 32];
    bytes[0] = 0x0f;
    let a: U252 = U252::from_be_bytes(bytes);
    assert(a == U252::from_limbs([TWO_POW_120 - 1, TWO_POW_120 - 1, 0xfff]));
    assert(a.to_be_bytes() == bytes);
}

// 2^BITS is not representable.
fn test_from_limbs_rejects_two_pow_bits<let N: u32, BN>()
where
    BN: BigInt,
{
    let _: BN = BN::from_limbs(two_pow_bits::<<BN as BigInt>::N, <BN as BigInt>::BITS>());
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
    let a: BN = derive_from_seed([1, 2, 3, 4]);
    let b: BN = derive_from_seed([1, 2, 3, 4]);
    let c: BN = derive_from_seed([2, 2, 3, 4]);

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

    let a: BN = derive_from_seed([1, 2, 3, 4]);
    assert(a.is_zero() == false);
    assert(!a.is_zero());
}

fn test_assert_is_not_equal<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = derive_from_seed([1, 2, 3, 4]);
    let b: BN = derive_from_seed([4, 5, 6, 7]);

    a.assert_is_not_equal(&b);
}

fn test_assert_is_not_equal_fail<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = derive_from_seed([1, 2, 3, 4]);
    let b: BN = derive_from_seed([1, 2, 3, 4]);

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
    let mut a: U256 = derive_from_seed(seed);
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
    let a: U256 = derive_from_seed([1, 2, 3]);
    let b: U256 = derive_from_seed([1, 2, 3]);
    let c: bool = a < b;
    assert(c == false);
}

#[test]
fn fuzz_cmp_equal(seed: [u8; 5]) {
    let a: U256 = derive_from_seed(seed);
    let b: U256 = derive_from_seed(seed);
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

// Derive a value from `seed` which only uses the lower `(N - 1) / 2` limbs, so that the
// identities in `test_add`, `test_mul` and `test_sqr` (e.g. `(a + b)^2`) do not overflow.
fn small_from_seed<BN, let SeedBytes: u32>(seed: [u8; SeedBytes]) -> BN
where
    BN: BigInt,
{
    let mut value: BN = derive_from_seed(seed);
    for i in (<BN as BigInt>::N - 1) / 2..<BN as BigInt>::N {
        value.set_limb(i, 0);
    }
    value
}

fn test_add<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = small_from_seed([1, 2, 3, 4]);
    let b: BN = small_from_seed([4, 5, 6, 7]);
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

#[test(should_fail_with = "attempt to add with overflow")]
fn test_add_U256_overflow() {
    // (2^256 - 1) + 1 = 2^256 overflows
    let _: U256 = U256::from_limbs(U256_MAX) + U256::one();
}

#[test(should_fail_with = "attempt to add with overflow")]
unconstrained fn test_add_U256_overflow_unconstrained() {
    let _: U256 = U256::from_limbs(U256_MAX) + U256::one();
}

#[test(should_fail_with = "attempt to add with overflow")]
unconstrained fn test_unconstrained_add_U256_overflow() {
    let _: U256 = U256::from_limbs(U256_MAX).__add(&U256::one());
}

// The witness hints fail first with a descriptive message, so check the constraints directly: no
// choice of carry or borrow flags lets an overflowing sum or an underflowing difference through.
#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_add_constraints_reject_overflow_honest_flags() {
    // (2^256 - 1) + 1: the honest flags carry out of every limb
    let _ = assert_add_no_overflow::<3, 256>(&U256_MAX, &[1, 0, 0], &[true, true]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_add_constraints_reject_overflow_no_carries() {
    let _ = assert_add_no_overflow::<3, 256>(&U256_MAX, &[1, 0, 0], &[false, false]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_add_constraints_reject_overflow_partial_carries() {
    let _ = assert_add_no_overflow::<3, 256>(&U256_MAX, &[1, 0, 0], &[true, false]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_sub_constraints_reject_underflow_honest_flags() {
    // 0 - 1: the honest flags borrow into every limb
    let _ = assert_sub_no_overflow::<3, 256>(&[0, 0, 0], &[1, 0, 0], &[true, true]);
}

#[test(should_fail_with = "call to assert_max_bit_size")]
fn test_sub_constraints_reject_underflow_no_borrows() {
    let _ = assert_sub_no_overflow::<3, 256>(&[0, 0, 0], &[1, 0, 0], &[false, false]);
}

#[test]
fn test_add_U256_max() {
    // (2^256 - 3) + 2 = 2^256 - 1
    let mut a: U256 = U256::from_limbs(U256_MAX);
    a.set_limb(0, a.get_limb(0) - 2);
    let b: U256 = U256::from_limbs([2, 0, 0]);

    let c: U256 = a + b;
    assert(c == U256::from_limbs(U256_MAX));
}

#[test]
fn test_add_U256_carry() {
    // (2^120 - 1) + 1 = 2^120 carries into the second limb
    let a: U256 = U256::from_limbs([TWO_POW_120 - 1, 0, 0]);
    let c: U256 = a + U256::one();
    assert(c.get_limbs() == [0, 1, 0]);
}

#[test(should_fail_with = "attempt to subtract with overflow")]
fn test_sub_U256_underflow() {
    let _: U256 = U256::zero() - U256::one();
}

#[test(should_fail_with = "attempt to subtract with overflow")]
unconstrained fn test_sub_U256_underflow_unconstrained() {
    let _: U256 = U256::zero() - U256::one();
}

#[test(should_fail_with = "attempt to subtract with overflow")]
unconstrained fn test_unconstrained_sub_U256_underflow() {
    let _: U256 = U256::zero().__sub(&U256::one());
}

#[test]
fn test_sub_U256() {
    let max: U256 = U256::from_limbs(U256_MAX);
    assert(max - max == U256::zero());

    // 2^120 - 1 borrows from the second limb
    let a: U256 = U256::from_limbs([0, 1, 0]);
    let c: U256 = a - U256::one();
    assert(c.get_limbs() == [TWO_POW_120 - 1, 0, 0]);
}

#[test(should_fail_with = "attempt to subtract with overflow")]
fn test_sub_U2048_underflow() {
    let a: U2048 = small_from_seed([1, 2, 3, 4]);
    let b: U2048 = a + U2048::one();
    let _: U2048 = a - b;
}

fn test_mul<let N: u32, BN>()
where
    BN: BigInt,
{
    let a: BN = small_from_seed([1, 2, 3, 4]);
    let b: BN = small_from_seed([4, 5, 6, 7]);
    let c: BN = (a + b) * (a + b);
    let d: BN = (a * a) + (b * b) + (a * b) + (b * a);
    assert(c.eq(d));
}

#[test]
fn test_mul_U256_with_one() {
    let a: U256 = U256::from_limbs([TWO_POW_120 - 2, TWO_POW_120 - 1, 0xffff]);
    let b: U256 = U256::one();
    let c: U256 = a * b;
    assert(c == a);
}

fn test_div_div_rem_equality<let N: u32, BN>()
where
    BN: BigInt,
{
    let mut a: BN = BN::zero();
    a.set_limb(0, 0x1000);

    let two: BN = BN::one() + BN::one();

    let c: BN = a / two;
    let (d, _): (BN, BN) = a.div_rem(&two);

    assert(c == d);
}

#[test]
fn test_div_rem_U256() {
    let a: U256 = U256::from_limbs([
        0xec0ca0c0adce359af6fcea1a7ab2dc,
        0xdd52c4aa3fde93685d3f7cc285de32,
        0x6fea,
    ]);
    let b: U256 = U256::from_limbs([12, 0, 0]);

    let (q, r): (U256, U256) = a.div_rem(&b);

    // Safety: test code
    let product: U256 = unsafe { q.__mul(&b).__add(&r) };
    assert(product == a);
}

#[test]
fn test_1_div_rem_2() {
    let _0: U256 = U256::zero();
    let _1: U256 = U256::one();
    let _2: U256 = _1 + _1;
    assert(_1.div_rem(&_2) == (_0, _1));
}

#[test]
fn test_20_div_rem_11() {
    let _1: U256 = U256::one();
    let _2_POW_120: U256 = U256::from_limbs([0, 1, 0]);
    let _2_POW_121: U256 = U256::from_limbs([0, 2, 0]);
    let divisor: U256 = _2_POW_120 + _1;
    assert(_2_POW_121.div_rem(&divisor) == (_1, _2_POW_120 - _1));
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
fn test_div_div_rem_equality_U256() {
    test_div_div_rem_equality::<3, U256>();
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
fn test_div_div_rem_equality_U2048() {
    test_div_div_rem_equality::<18, U2048>();
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

#[test]
fn test_rem_U256() {
    assert(U256::from(20) % U256::from(11) == U256::from(9));
    assert(U256::from(22) % U256::from(11) == U256::zero());
    assert(U256::from(3) % U256::from(11) == U256::from(3));
}

#[test]
fn test_div_rem_consistency_U2048() {
    let a: U2048 = derive_from_seed([1, 2, 3, 4]);
    // Clear the upper limbs so that the quotient is non-trivial
    let mut b: U2048 = derive_from_seed([5, 6, 7, 8]);
    for i in 9..18 {
        b.set_limb(i, 0);
    }
    let (q, r): (U2048, U2048) = a.div_rem(&b);
    assert(q == a / b);
    assert(r == a % b);
    assert(r < b);
    assert(q * b + r == a);
}

// ------------------------------ DIVISION BY ZERO TESTS ------------------------------

#[test(should_fail_with = "attempt to divide by zero")]
fn test_div_rem_by_zero() {
    let _ = U256::from(7).div_rem(&U256::zero());
}

#[test(should_fail_with = "attempt to divide by zero")]
fn test_div_by_zero() {
    let _ = U256::from(7) / U256::zero();
}

#[test(should_fail_with = "attempt to divide by zero")]
fn test_rem_by_zero() {
    let _ = U256::from(7) % U256::zero();
}

#[test(should_fail_with = "attempt to divide by zero")]
unconstrained fn test_unconstrained_div_rem_by_zero() {
    let _ = U256::from(7).__div_rem(&U256::zero());
}

#[test(should_fail_with = "attempt to divide by zero")]
unconstrained fn test_unconstrained_div_by_zero() {
    let _ = U256::from(7).__div(&U256::zero());
}

// Intermediate values within an expression may exceed 2^BITS: a * a - a * d - r = 0, where
// a = 2^128, d = 2^128 - 1 and r = 2^128, although a * a = 2^256 does not fit in a `U256`
#[test]
fn test_evaluate_quadratic_expression_overflowing_intermediates() {
    let a: U256 = U256::from_limbs([0, 0x100, 0]);
    let d: U256 = U256::from_limbs([TWO_POW_120 - 1, 0xff, 0]);
    let r: U256 = U256::from_limbs([0, 0x100, 0]);
    evaluate_quadratic_expression(
        [[a], [a]],
        [[false], [false]],
        [[a], [d]],
        [[false], [true]],
        [r],
        [true],
    );

    // Safety: test code
    let computed: U256 = unsafe {
        compute_quadratic_expression(
            [[a], [a]],
            [[false], [false]],
            [[a], [d]],
            [[false], [true]],
            [],
            [],
        )
    };
    assert(computed == r);
}

// The same computation with the checked operators fails at `a * a`
#[test(should_fail_with = "attempt to multiply with overflow")]
fn test_operators_reject_overflowing_intermediates() {
    let a: U256 = U256::from_limbs([0, 0x100, 0]);
    let d: U256 = U256::from_limbs([TWO_POW_120 - 1, 0xff, 0]);
    let _: U256 = a * a - a * d;
}

// ------------------------------ CHECKED MULTIPLICATION TESTS ------------------------------

#[test]
fn test_mul_U256_max() {
    // (2^128 - 1) * (2^128 - 1) = 2^256 - 2^129 + 1 fits
    let a: U256 = U256::from_limbs([TWO_POW_120 - 1, 0xff, 0]);
    let c: U256 = a * a;
    // Safety: test code
    let expected: U256 = unsafe {
        U256::from_limbs(U256_MAX).__sub(&U256::from_limbs([0, 0x200, 0])).__add(&U256::from(2))
    };
    assert(c == expected);
}

#[test(should_fail_with = "attempt to multiply with overflow")]
fn test_mul_U256_overflow() {
    // 2^128 * 2^128 = 2^256 overflows
    let a: U256 = U256::from_limbs([0, 0x100, 0]);
    let _: U256 = a * a;
}

#[test(should_fail_with = "attempt to multiply with overflow")]
unconstrained fn test_unconstrained_mul_U256_overflow() {
    let a: U256 = U256::from_limbs([0, 0x100, 0]);
    let _: U256 = a.__mul(&a);
}

// Even if the prover supplies the wrapped product, the multiplication relation is rejected
#[test(should_fail)]
fn test_mul_U256_rejects_wrapped_product() {
    let a: [u128; 3] = [0, 0x100, 0];
    validate_mul_add_expression::<3, 256>(&a, &a, &[0, 0, 0], &[0, 0, 0]);
}

#[test]
unconstrained fn test_pow() {
    let three: U256 = U256::from(3);
    assert(three.__pow(&U256::from(5)) == U256::from(243));
    assert(three.__pow(&U256::zero()) == U256::one());
    assert(U256::zero().__pow(&U256::zero()) == U256::one());
    assert(U256::zero().__pow(&U256::from(7)) == U256::zero());
    assert(U256::one().__pow(&U256::from_limbs(U256_MAX)) == U256::one());

    // 2^255 is the largest power of two which fits
    let two_pow_255: U256 = U256::from_limbs([0, 0, 0x8000]);
    assert(U256::from(2).__pow(&U256::from(255)) == two_pow_255);
}

#[test(should_fail_with = "attempt to multiply with overflow")]
unconstrained fn test_pow_overflow() {
    let _: U256 = U256::from(2).__pow(&U256::from(256));
}

#[test]
unconstrained fn test_compute_quadratic_expression() {
    let a: U256 = U256::from(6);
    let b: U256 = U256::from(7);
    let c: U256 = U256::from(5);
    // a * b - c = 37
    let r: U256 = compute_quadratic_expression([[a]], [[false]], [[b]], [[false]], [c], [true]);
    assert(r == U256::from(37));
}

#[test(should_fail_with = "attempt to subtract with overflow")]
unconstrained fn test_compute_quadratic_expression_negative() {
    let a: U256 = U256::from(6);
    let b: U256 = U256::from(7);
    let c: U256 = U256::from(50);
    // a * b - c < 0
    let _: U256 = compute_quadratic_expression([[a]], [[false]], [[b]], [[false]], [c], [true]);
}

#[test(should_fail_with = "attempt to evaluate quadratic expression with overflow")]
unconstrained fn test_compute_quadratic_expression_overflow() {
    let a: U256 = U256::from_limbs([0, 0x100, 0]);
    // a * a = 2^256
    let _: U256 = compute_quadratic_expression([[a]], [[false]], [[a]], [[false]], [], []);
}

#[test(should_fail_with = "attempt to divide by zero")]
unconstrained fn test_div_by_zero_unconstrained() {
    let _ = U256::from(7) / U256::zero();
}

// ------------------------------ EXPRESSIONS TESTS ------------------------------

#[test]
fn test_expressions() {
    let y: U256 = U256::from_limbs([0x1, 0x1, 0x0]);
    let z: U256 = U256::from_limbs([0x2, 0x2, 0x0]);
    // Safety: test code
    let yy: U256 = unsafe { y.__add(&y) };

    assert(yy.get_limbs() == z.get_limbs());

    // Values below 2^127, so that `uu * vv + w * x` fits in 256 bits
    let uu: U256 = U256::from_limbs([0xb4a832748da6ad742a1fd81b787643, 0x75, 0x0]);
    let vv: U256 = U256::from_limbs([0xb4aec2748da6ad742a1fd81b787643, 0x62, 0x0]);
    let w: U256 = U256::from_limbs([0xb4a832748da6ad742a1fd81b787643, 0x1f, 0x0]);
    let x: U256 = U256::from_limbs([0xb4aec2748da6ad742a1fd81b787643, 0xf, 0x0]);
    // Safety: test code
    let wx: U256 = unsafe { w.__mul(&x) };
    // Safety: test code
    let uv: U256 = unsafe { uu.__mul(&vv) };
    // Safety: test code
    let z: U256 = unsafe { uv.__add(&wx) };
    assert(
        z.get_limbs()
            == [0xd652754f81ecae21b4d9626ee3ab12, 0x3249dee05564b0c430d352ec4798ac, 0x2f54],
    );

    // uu * vv + w * x - z = 0
    evaluate_quadratic_expression(
        [[uu], [w]],
        [[false], [false]],
        [[vv], [x]],
        [[false], [false]],
        [z],
        [true],
    );
    // (-uu) * vv + w * (-x) + z = 0
    evaluate_quadratic_expression(
        [[uu], [w]],
        [[true], [false]],
        [[vv], [x]],
        [[false], [true]],
        [z],
        [false],
    );

    let wx_constrained = w * x;
    assert(wx_constrained.get_limbs() == wx.get_limbs());
}

#[test]
fn test_2048_bit_quadratic_expression() {
    // `a` uses 8 limbs and `b` uses 9 limbs, so `a * b` fits in 2048 bits
    let a: [u128; 18] = [
        0x83684820ff40795b8d9f1be2220cba,
        0xd4924fbdc522b07b6cd0ef5508fd66,
        0xd48f6c43c5930f3d70d6db09a48f4a,
        0xe7f72b2c0756704bea85be38352b34,
        0x8337197826e2e9ea000ed5b05d5ac5,
        0x40680101b43f6d17de8e3507f3d820,
        0x0c6ba0cdcf77cff1c10355ea48d387,
        0xe51717a72902214a9dbeb90e4f225f,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
    ];
    let b: [u128; 18] = [
        0xc5694493e9bcc76e68dfcf73e0fde1,
        0xede5e4b8b3e0dec1f4705c35521620,
        0x7aa800bab1b33eda0f07695af6c583,
        0x45892edea2c02bf0b8b1d2d9a4ebcc,
        0x4dffb06bf396f3d0a5b67cff714bdd,
        0x4d691db495235e1e032f1ef3e90274,
        0xd92c069d0f2675b2f46cb497aa62d4,
        0x3d3f23584f113cef1a4b8b7d183f5c,
        0x289ba11d897837f9cec57dcc430bfc,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
        0x000000000000000000000000000000,
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
        0xa593a2ded0895cc1aa1d9dbc2f36cc,
        0x920b0ea0d765292b79a4ef7dbe7533,
        0xd3529783a8ed7079ae9979ef18d0e9,
        0xd62863784dcbd70fd50c666787164d,
        0x74ad917740e1fb3bb84ed0608fd0c4,
        0x071c35e998e252da4ff84e347bd74b,
        0x9b0453d62318670745684f82c6daa3,
        0x8490d711ae8cb07d08a8ee40b1dd2f,
        0x2456e0db6520e8cadae29aa4c2382d,
        0x000000000000000000000000000000,
    ];

    let a_bn: U2048 = U2048::from_limbs(a);
    let b_bn: U2048 = U2048::from_limbs(b);

    // Safety: test code
    let c_bn: U2048 = unsafe { a_bn.__mul(&b_bn) };

    assert(c_bn.get_limbs() == c_expected);

    evaluate_quadratic_expression([[a_bn]], [[false]], [[b_bn]], [[false]], [c_bn], [true]);
    assert(a_bn * b_bn == c_bn);
}

// The product of two full-width values overflows
#[test(should_fail_with = "attempt to multiply with overflow")]
unconstrained fn test_2048_bit_mul_overflow_unconstrained() {
    let a: U2048 = U2048::from_limbs([
        0x83684820ff40795b8d9f1be2220cba,
        0xd4924fbdc522b07b6cd0ef5508fd66,
        0xd48f6c43c5930f3d70d6db09a48f4a,
        0xe7f72b2c0756704bea85be38352b34,
        0x8337197826e2e9ea000ed5b05d5ac5,
        0x40680101b43f6d17de8e3507f3d820,
        0x0c6ba0cdcf77cff1c10355ea48d387,
        0xe51717a72902214a9dbeb90e4f225f,
        0xc1bd5bec78406b691f71cbcddb4574,
        0x1ce5e532cfb306d7b52e7d9f1aa442,
        0x19575932f75ddf00595b22782e1ba2,
        0xd630b3fbf0a9e55861e4399900feb9,
        0xd6b37aeb2daa8d2e2f7e29b0f7752a,
        0xe9cacdd93406256b9eb46b73948849,
        0x1400e1f0a38695db66993fe042c48b,
        0xe1d829cb4fa8cabb7d0265efbd8527,
        0x55f1a92a5dd099ef2bcd89ac175b52,
        0x0000000000000000000000000000fc,
    ]);
    let b: U2048 = U2048::from_limbs([
        0xc5694493e9bcc76e68dfcf73e0fde1,
        0xede5e4b8b3e0dec1f4705c35521620,
        0x7aa800bab1b33eda0f07695af6c583,
        0x45892edea2c02bf0b8b1d2d9a4ebcc,
        0x4dffb06bf396f3d0a5b67cff714bdd,
        0x4d691db495235e1e032f1ef3e90274,
        0xd92c069d0f2675b2f46cb497aa62d4,
        0x3d3f23584f113cef1a4b8b7d183f5c,
        0x289ba11d897837f9cec57dcc430bfc,
        0x765dc64f6ed4a6efd7b26c38f79e59,
        0x8edf31fabf5c330ecf7f92fb6487cd,
        0x53392f8b14dd78af702b3be2e0d557,
        0x34abf357bfd56e9786a7e47ed9a5ae,
        0xa9ebb234064c8ab10d4e7900d4b973,
        0x2a6850cce14a20463913002ddc0fa6,
        0xa97e3b06586bfa62325ef7557ab536,
        0xb942b0d26e5be2e08cd425107c59f7,
        0x000000000000000000000000000031,
    ]);
    let _: U2048 = a * b;
}

#[test(should_fail_with = "attempt to multiply with overflow")]
fn test_2048_bit_mul_overflow() {
    let a: U2048 = U2048::from_limbs([
        0x83684820ff40795b8d9f1be2220cba,
        0xd4924fbdc522b07b6cd0ef5508fd66,
        0xd48f6c43c5930f3d70d6db09a48f4a,
        0xe7f72b2c0756704bea85be38352b34,
        0x8337197826e2e9ea000ed5b05d5ac5,
        0x40680101b43f6d17de8e3507f3d820,
        0x0c6ba0cdcf77cff1c10355ea48d387,
        0xe51717a72902214a9dbeb90e4f225f,
        0xc1bd5bec78406b691f71cbcddb4574,
        0x1ce5e532cfb306d7b52e7d9f1aa442,
        0x19575932f75ddf00595b22782e1ba2,
        0xd630b3fbf0a9e55861e4399900feb9,
        0xd6b37aeb2daa8d2e2f7e29b0f7752a,
        0xe9cacdd93406256b9eb46b73948849,
        0x1400e1f0a38695db66993fe042c48b,
        0xe1d829cb4fa8cabb7d0265efbd8527,
        0x55f1a92a5dd099ef2bcd89ac175b52,
        0x0000000000000000000000000000fc,
    ]);
    let b: U2048 = U2048::from_limbs([
        0xc5694493e9bcc76e68dfcf73e0fde1,
        0xede5e4b8b3e0dec1f4705c35521620,
        0x7aa800bab1b33eda0f07695af6c583,
        0x45892edea2c02bf0b8b1d2d9a4ebcc,
        0x4dffb06bf396f3d0a5b67cff714bdd,
        0x4d691db495235e1e032f1ef3e90274,
        0xd92c069d0f2675b2f46cb497aa62d4,
        0x3d3f23584f113cef1a4b8b7d183f5c,
        0x289ba11d897837f9cec57dcc430bfc,
        0x765dc64f6ed4a6efd7b26c38f79e59,
        0x8edf31fabf5c330ecf7f92fb6487cd,
        0x53392f8b14dd78af702b3be2e0d557,
        0x34abf357bfd56e9786a7e47ed9a5ae,
        0xa9ebb234064c8ab10d4e7900d4b973,
        0x2a6850cce14a20463913002ddc0fa6,
        0xa97e3b06586bfa62325ef7557ab536,
        0xb942b0d26e5be2e08cd425107c59f7,
        0x000000000000000000000000000031,
    ]);
    let _: U2048 = a * b;
}
