use crate::{BigInt, evaluate_quadratic_expression, U256};

/// Bigint's verifier range-checks all input/result limbs and bounded carries.
pub(crate) fn verify_division(a: U256, b: U256, d: U256, q: U256, r: U256) {
    assert(d != U256::zero(), "mul_div: zero denominator");
    assert(r < d, "mul_div: remainder out of range");
    evaluate_quadratic_expression(
        [[a], [q]],
        [[false], [true]],
        [[b], [d]],
        [[false], [false]],
        [r],
        [true],
    );
}

#[test]
fn accepts_wide_witness() {
    let maximum = U256::from_le_bytes([255; 32]);
    check_supplied(maximum, maximum, maximum, maximum, U256::zero());
}

#[test]
fn accepts_inexact_witness() {
    check_supplied(
        U256::from(7),
        U256::from(9),
        U256::from(4),
        U256::from(15),
        U256::from(3),
    );
}

#[test(should_fail)]
fn rejects_wrong_quotient() {
    check_supplied(
        U256::from(7),
        U256::from(9),
        U256::from(4),
        U256::from(16),
        U256::from(3),
    );
}

#[test(should_fail)]
fn rejects_wrong_remainder() {
    check_supplied(
        U256::from(7),
        U256::from(9),
        U256::from(4),
        U256::from(15),
        U256::from(2),
    );
}

#[test(should_fail_with = "mul_div: remainder out of range")]
fn rejects_noncanonical_remainder() {
    check_supplied(
        U256::from(7),
        U256::from(9),
        U256::from(4),
        U256::from(14),
        U256::from(7),
    );
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn rejects_zero_denominator() {
    check_supplied(
        U256::zero(),
        U256::one(),
        U256::zero(),
        U256::zero(),
        U256::zero(),
    );
}

#[test(should_fail)]
fn rejects_noncanonical_quotient_width() {
    let two_to_128 = U256::from_limbs([0, 256, 0]);
    let two_to_256 = U256::from_limbs_unsafe([0, 0, 65536]);
    check_supplied(
        two_to_128,
        two_to_128,
        U256::one(),
        two_to_256,
        U256::zero(),
    );
}

fn as_witness(value: U256) -> U256 {
    let mut limbs = value.get_limbs();
    for i in 0..3 {
        let limb = limbs[i] as Field;
        std::as_witness(limb);
        limbs[i] = limb as u128;
    }
    U256::from_limbs_unsafe(limbs)
}

fn check_supplied(a: U256, b: U256, d: U256, q: U256, r: U256) {
    verify_division(
        as_witness(a),
        as_witness(b),
        as_witness(d),
        as_witness(q),
        as_witness(r),
    );
}

#[test(should_fail)]
fn rejects_field_congruent_integer_mismatch() {
    let maximum = U256::from_le_bytes([255; 32]);
    let product_mod_field = U256::from_limbs([
        297052298261446512361737393446940083,
        247306941045266840038115125213562382,
        5734,
    ]);
    check_supplied(maximum, maximum, maximum, U256::zero(), product_mod_field);
}
