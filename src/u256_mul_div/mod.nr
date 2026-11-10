//! `MulDiv` (from the `mul_div` library) for `U256`: exact `a * b / d` with the
//! 512-bit intermediate product kept in full.
//!
//! An unconstrained helper computes the quotient and remainder with 64-bit digits
//! (`division.nr`). From constrained code, `constraints.nr` then proves the integer
//! relation `a*b = q*d + r` with `evaluate_quadratic_expression`, plus `d != 0`,
//! `r < d` and the limb ranges of `q` and `r`.

use crate::{BigInt, U256};
use mul_div::MulDiv;

mod constraints;
mod division;

mod random_tests;
mod tests;

impl MulDiv for U256 {
    fn mul_div_rem(self, rhs: Self, denominator: Self) -> (Self, Self) {
        // The helper interprets 120/120/16-bit limbs, so validate input encoding
        // before splitting it into 64-bit digits in either execution context.
        self.validate_in_range();
        rhs.validate_in_range();
        denominator.validate_in_range();
        // Safety: the constrained path verifies the complete integer relation,
        // result limb ranges and Euclidean bounds; it does not trust helper checks.
        let (q, r) = unsafe { division::div_rem(self, rhs, denominator) };
        if !std::runtime::is_unconstrained() {
            constraints::verify_division(self, rhs, denominator, q, r);
        }
        (q, r)
    }

    fn mul_div_ceil(self, rhs: Self, denominator: Self) -> Self {
        let (q, r) = self.mul_div_rem(rhs, denominator);
        if r == U256::zero() {
            q
        } else {
            assert(q < U256::from_le_bytes([255; 32]), "mul_div: ceiling overflow");
            q + U256::one()
        }
    }
}
