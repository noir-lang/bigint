use crate::utils::split_bits;

use crate::constants::{TWO_POW_120, TWO_POW_126, TWO_POW_127, TWO_POW_246, TWO_POW_247};

use crate::fns::constrained_ops::validate_in_range;
use crate::fns::unconstrained_helpers::__helper_sub;
use crate::fns::unconstrained_ops::__gte;

/// Whether `validate_expression_is_zero` uses 127-bit rather than 126-bit carries, for `BigInt`s
/// with `N` limbs.
///
/// Each limb of an expression is a sum of products of 120-bit limbs, which must be below
/// `2^{120 + CARRY_BITS}` in absolute value for the borrow encoding to represent it (see
/// `assert_product_limbs_fit`). 126-bit carries suffice for a single product of `BigInt`s with up
/// to 65 limbs; wider types use 127-bit carries, which suffice for up to 129 limbs. A 126-bit range
/// check is cheaper than a 127-bit one in barretenberg, so the smaller bound is used where possible.
///
/// `N` is a numeric generic, so this is a comparison of constants: the carry constants and range
/// checks which depend on it are selected at compile time.
pub(crate) fn uses_wide_carries<let N: u32>() -> bool {
    N > 65
}

// ------------------------------ UNCONSTRAINED EXPRESSIONS ------------------------------

/// Split a linear combination of (possibly negated) `BigInt` values into the limb-wise sums of
/// its positive and its negated terms (unconstrained).
///
/// Neither sum is normalised to 120-bit limbs.
unconstrained fn __signed_linear_expression<let N: u32, let M: u32>(
    vals: &[[u128; N]; M],
    flags: &[bool; M],
) -> ([Field; N], [Field; N]) {
    let mut positive: [Field; N] = [0; N];
    let mut negative: [Field; N] = [0; N];
    for i in 0..M {
        for j in 0..N {
            if flags[i] {
                negative[j] += vals[i][j] as Field;
            } else {
                positive[j] += vals[i][j] as Field;
            }
        }
    }
    (positive, negative)
}

/// Compute a quadratic expression as the difference `P - Q` of two values with non-negative,
/// non-normalised limbs (unconstrained).
///
/// The expression is `\sum_k L_k * R_k + A`, where `L_k`, `R_k` and `A` are linear
/// combinations of (possibly negated) terms. Writing each combination as the difference of its
/// positive and negated terms, e.g. `L_k = L_k^+ - L_k^-`:
///
///     P = \sum_k (L_k^+ * R_k^+ + L_k^- * R_k^-) + A^+
///     Q = \sum_k (L_k^+ * R_k^- + L_k^- * R_k^+) + A^-
///
/// The returned arrays have `2N` limbs, of which the top limb is always zero, so that they can be
/// normalised without overflow.
unconstrained fn __compute_quadratic_expression_parts<let N: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) -> ([Field; 2 * N], [Field; 2 * N]) {
    let mut positive: [Field; 2 * N] = [0; 2 * N];
    let mut negative: [Field; 2 * N] = [0; 2 * N];

    for k in 0..NUM_PRODUCTS {
        let (lhs_positive, lhs_negative): ([Field; N], [Field; N]) =
            __signed_linear_expression::<N, LHS_N>(&lhs_terms[k], &lhs_flags[k]);
        let (rhs_positive, rhs_negative): ([Field; N], [Field; N]) =
            __signed_linear_expression::<N, RHS_N>(&rhs_terms[k], &rhs_flags[k]);
        for i in 0..N {
            for j in 0..N {
                positive[i + j] +=
                    lhs_positive[i] * rhs_positive[j] + lhs_negative[i] * rhs_negative[j];
                negative[i + j] +=
                    lhs_positive[i] * rhs_negative[j] + lhs_negative[i] * rhs_positive[j];
            }
        }
    }

    let (linear_positive, linear_negative): ([Field; N], [Field; N]) =
        __signed_linear_expression::<N, ADD_N>(linear_terms, linear_flags);
    for i in 0..N {
        positive[i] += linear_positive[i];
        negative[i] += linear_negative[i];
    }

    (positive, negative)
}

/// Compute the borrow flags for a limb-wise subtraction `lhs - rhs` (unconstrained).
///
/// The numbers below are for 126-bit carries. For `BigInt`s with more than 65 limbs, `2^{246}` and
/// `2^{126}` (and the 126-bit range check) become `2^{247}` and `2^{127}`; see `uses_wide_carries`.
///
/// This helper operates on `N`-limb values where each limb is interpreted as a
/// 120-bit chunk (base `B = 2^{120}`), but where intermediate limbs may exceed
/// `2^{120}` due to sums of products.
///
/// Conceptually, we want to model the integer subtraction
///
///     lhs - rhs
///
/// as a base-`B` subtraction with borrows, without allowing any intermediate
/// values to go negative in the circuit field. We achieve this by:
///
///   1. Working with widened 246-bit ranges per limb.
///   2. Encoding a borrow from limb `i+1` into limb `i` by:
///        - adding `2^{246}` into limb `i`,
///        - subtracting `2^{126}` (= 2^{246 - 120}) from limb `i+1` after
///          scaling by `2^{-120}`.
///
/// The returned `borrow_flags[i]` indicate whether the canonical integer
/// subtraction would borrow from limb `i+1` into limb `i`. These flags are
/// later re-applied in-circuit via `apply_borrow_flags`, and the resulting
/// limbs are checked by `validate_expression_is_zero`.
unconstrained fn __compute_borrow_flags<let N: u32, let LIMBS: u32>(
    mut lhs_limbs: [Field; N],
    rhs_limbs: [Field; N],
) -> [bool; N - 1] {
    // compute borrow flags from mulout_p and mulout_n
    let mut borrow_flags: [bool; N - 1] = [false; N - 1];
    let wide: bool = uses_wide_carries::<LIMBS>();
    let borrow_carry: Field = if wide { TWO_POW_127 } else { TWO_POW_126 }; // 2^{CARRY_BITS}
    let borrow_shift: Field = if wide { TWO_POW_247 } else { TWO_POW_246 }; // 2^{120 + CARRY_BITS}
    let downshift_120: Field = 1 / (TWO_POW_120 as Field);

    // determine whether we need to borrow from more significant limbs.
    // initial limb is "simple" comparison operation
    borrow_flags[0] = lhs_limbs[0].lt(rhs_limbs[0]);

    // we have N - 1 borrow flags. The number of limbs is N
    // and there is nothing to borrow against for the final limb.
    let mut hi_bits: Field =
        (lhs_limbs[0] - rhs_limbs[0] + ((borrow_flags[0] as Field) * borrow_shift)) * downshift_120;

    for i in 1..(N - 1) {
        // compute the contribution from limb `i-1` that gets added into limb `i`, and add into limb `i`
        lhs_limbs[i] += hi_bits;

        let subtrahend: Field = rhs_limbs[i] + (borrow_flags[i - 1] as Field) * borrow_carry;

        // determine whether negative limb values are greater than positive limb values
        borrow_flags[i] = lhs_limbs[i].lt(subtrahend);
        let minuend: Field = lhs_limbs[i] + (borrow_flags[i] as Field) * borrow_shift;

        hi_bits = (minuend - subtrahend) * downshift_120;
    }
    borrow_flags
}

/// Compute the borrow flags used to evaluate a quadratic expression in-circuit (unconstrained).
///
/// See `__compute_quadratic_expression_parts` and `__compute_borrow_flags`.
unconstrained fn __compute_quadratic_expression_borrow_flags<let N: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) -> [bool; 2 * N - 2] {
    let (positive, negative): ([Field; 2 * N], [Field; 2 * N]) = __compute_quadratic_expression_parts::<N, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_terms,
        lhs_flags,
        rhs_terms,
        rhs_flags,
        linear_terms,
        linear_flags,
    );

    // The expression has `2N - 1` limbs; the top limb of each part is always zero.
    let mut positive_limbs: [Field; 2 * N - 1] = [0; 2 * N - 1];
    let mut negative_limbs: [Field; 2 * N - 1] = [0; 2 * N - 1];
    for i in 0..2 * N - 1 {
        positive_limbs[i] = positive[i];
        negative_limbs[i] = negative[i];
    }
    __compute_borrow_flags::<_, N>(positive_limbs, negative_limbs)
}

/// Computes the value of a quadratic expression (unconstrained).
///
/// Fails if the expression is negative or `>= 2^BITS`.
///
/// See `__compute_quadratic_expression_parts` for the form of the expression.
pub(crate) unconstrained fn __compute_quadratic_expression<let N: u32, let BITS: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) -> [u128; N] {
    let (positive, negative): ([Field; 2 * N], [Field; 2 * N]) = __compute_quadratic_expression_parts::<N, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_terms,
        lhs_flags,
        rhs_terms,
        rhs_flags,
        linear_terms,
        linear_flags,
    );
    // `__normalize_limbs` validates that neither part overflows `2N` limbs
    let positive: [u128; 2 * N] = split_bits::__normalize_limbs(positive);
    let negative: [u128; 2 * N] = split_bits::__normalize_limbs(negative);

    assert(__gte(&positive, &negative), "attempt to subtract with overflow");
    let value: [u128; 2 * N] = __helper_sub(&positive, &negative);

    let mut result: [u128; N] = [0; N];
    for i in 0..N {
        result[i] = value[i];
    }
    let top_limb_bits: u128 = (BITS - (N - 1) * 120) as u128;
    let mut overflow: bool = (result[N - 1] >> top_limb_bits) != 0;
    for i in N..2 * N {
        overflow |= value[i] != 0;
    }
    assert(!overflow, "attempt to evaluate quadratic expression with overflow");

    result
}

// ------------------------------ CONSTRAINED EXPRESSIONS ------------------------------

/// Constrained version of `__signed_linear_expression`
///
/// Computes all the linear parts of an expression in-circuit, as limb-wise signed sums of the
/// terms, i.e. negated terms are subtracted. The resulting limbs are not normalised and may be
/// negative.
fn compute_linear_expressions<let N: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) -> ([[Field; N]; NUM_PRODUCTS], [[Field; N]; NUM_PRODUCTS], [Field; N]) {
    let mut lhs_linear: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
    let mut rhs_linear: [[Field; N]; NUM_PRODUCTS] = [[0; N]; NUM_PRODUCTS];
    let mut lin_expr: [Field; N] = [0; N];

    for k in 0..NUM_PRODUCTS {
        for i in 0..N {
            for j in 0..LHS_N {
                // Note: if lhs_flags[k][j] - `is_negative` is not known at comptime this is very expensive
                if (lhs_flags[k][j]) {
                    lhs_linear[k][i] -= lhs_terms[k][j][i] as Field;
                } else {
                    lhs_linear[k][i] += lhs_terms[k][j][i] as Field;
                }
            }
            for j in 0..RHS_N {
                // Note: if rhs_flags[k][j] - `is_negative` is not known at comptime this is very expensive
                if (rhs_flags[k][j]) {
                    rhs_linear[k][i] -= rhs_terms[k][j][i] as Field;
                } else {
                    rhs_linear[k][i] += rhs_terms[k][j][i] as Field;
                }
            }
        }
    }

    for i in 0..N {
        for j in 0..ADD_N {
            // Note: if linear_flags[j] - `is_negative` is not known at comptime this is very expensive
            if (linear_flags[j]) {
                lin_expr[i] -= linear_terms[j][i] as Field;
            } else {
                lin_expr[i] += linear_terms[j][i] as Field;
            }
        }
    }

    (lhs_linear, rhs_linear, lin_expr)
}

/// Computes the limbs of `\sum L_i * R_i + A` in-circuit, with prover-provided borrow flags
/// The numbers below are for 126-bit carries. For `BigInt`s with more than 65 limbs, `2^{246}` and
/// `2^{126}` (and the 126-bit range check) become `2^{247}` and `2^{127}`; see `uses_wide_carries`.
///
/// applied.
///
/// Each limb of the expression is a signed value. To allow `validate_expression_is_zero` to check
/// that the limbs encode zero using non-negative carries, the prover provides a sequence of
/// borrow flags, and the limbs are adjusted by:
///
///   - for each limb `i` we may add `2^{246}` (via a flag at position `i`);
///   - for each limb `i` we may subtract `2^{126 = 246 - 120}` (via the flag
///     at position `i - 1`).
///
/// This corresponds to borrowing `2^{126}` from limb `i + 1` and adding `2^{246}` into limb `i`,
/// which leaves the integer value encoded by the limbs unchanged. After this adjustment, an honest
/// prover can ensure that every running sum of limbs and carries lies in `[0, 2^{246})`.
fn compute_quadratic_expression_limbs<let N: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) -> [Field; 2 * N - 1] {
    // Safety: the borrow flags are constrained by `validate_expression_is_zero`, which fails for
    // any flags which do not make every running sum a non-negative multiple of 2^{120}
    let borrow_flags: [bool; 2 * N - 2] = unsafe {
        __compute_quadratic_expression_borrow_flags::<N, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
            lhs_terms,
            lhs_flags,
            rhs_terms,
            rhs_flags,
            linear_terms,
            linear_flags,
        )
    };

    // Compute the linear sums that represent L_i, R_i, A
    let (lhs_linear, rhs_linear, lin_expr): ([[Field; N]; NUM_PRODUCTS], [[Field; N]; NUM_PRODUCTS], [Field; N]) = compute_linear_expressions::<N, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_terms,
        lhs_flags,
        rhs_terms,
        rhs_flags,
        linear_terms,
        linear_flags,
    );

    let mut expression_limbs: [Field; 2 * N - 1] = [0; 2 * N - 1];
    for i in 0..N {
        for j in 0..N {
            for k in 0..NUM_PRODUCTS {
                expression_limbs[i + j] += lhs_linear[k][i] * rhs_linear[k][j];
            }
        }
        expression_limbs[i] += lin_expr[i];
    }

    apply_borrow_flags::<_, N>(expression_limbs, borrow_flags)
}

/// Apply a precomputed borrow chain to a limb array.
///
/// The numbers below are for 126-bit carries. For `BigInt`s with more than 65 limbs, `2^{246}` and
/// `2^{126}` (and the 126-bit range check) become `2^{247}` and `2^{127}`; see `uses_wide_carries`.
///
/// Given:
///
///   - `expression_limbs`: an `N`-limb array of `Field` values representing a
///     (possibly non-normalized) degree-2-style expression, and
///   - `borrow_flags[i]` indicating that we "borrow" from limb `i+1` into limb `i`,
///
/// this function applies the same 2^{246}/2^{126} encoding used in
/// `__compute_borrow_flags` to produce an adjusted limb array
///
/// This matches the behavior of `__compute_borrow_flags`, which conceptually:
///
///   1. Adds `2^{246}` into a limb when a borrow is taken at that limb;
///   2. After scaling by `2^{-120}`, contributes `2^{126}` into the next limb.
///
/// The resulting `expression_limbs` can then be passed to
/// `validate_expression_is_zero`, which:
///
///   - right-shifts by 120 bits per limb,
///   - enforces a 126-bit bound,
///   - and propagates carries forward, finally checking that the most
///     significant limb is zero.
///
/// ## Assumptions
///
/// - `borrow_flags` was computed consistently with the original construction
///   of `expression_limbs` (e.g. via `__compute_borrow_flags` on the
///   corresponding unconstrained expression).
/// - The caller has ensured that each adjusted limb remains < 2^{246} for
///   honest witnesses (e.g. via `NUM_PRODUCTS < 64`).
///
/// ## Note
///
/// This function does not itself enforce any bit-size bounds; it only applies
/// the borrow encoding. The actual range checks happen later in
/// `validate_expression_is_zero`.
///
/// ## TODO
/// define trade-offs regarding the value of borrow_shift
/// (the larger the value, the greater the range check that is required on product_limbs)
/// (126-bit range check is a sweet spot for the barretenberg backend as it decomposes into 9 14-bit range checks)
/// (the barretenberg backend can evaluate these in 5.25 gates. 127 bits costs 6.5 gates)
fn apply_borrow_flags<let N: u32, let LIMBS: u32>(
    mut expression_limbs: [Field; N],
    borrow_flags: [bool; N - 1],
) -> [Field; N] {
    let wide: bool = uses_wide_carries::<LIMBS>();
    let borrow_carry: Field = if wide { TWO_POW_127 } else { TWO_POW_126 }; // 2^{CARRY_BITS}
    let borrow_shift: Field = if wide { TWO_POW_247 } else { TWO_POW_246 }; // 2^{120 + CARRY_BITS}

    // Get the product_limbs into the form where each entry is a 246-bit value
    expression_limbs[0] += (borrow_flags[0] as Field) * borrow_shift;
    for i in 1..(N - 1) {
        expression_limbs[i] += (borrow_flags[i] as Field) * borrow_shift
            - (borrow_flags[i - 1] as Field) * borrow_carry;
    }
    expression_limbs[N - 1] -= (borrow_flags[N - 2] as Field) * borrow_carry;
    expression_limbs
}

/// Validate that `limbs` represent the integer value `0`
///
/// The numbers below are for 126-bit carries. For `BigInt`s with more than 65 limbs, `2^{246}` and
/// `2^{126}` (and the 126-bit range check) become `2^{247}` and `2^{127}`; see `uses_wide_carries`.
///
/// ## Assumptions
///     - `limbs` is an array of `Field` values that was derived arithmetically as
///        a degree-2 expression
///     - each limb satisfies `limbs[i] < 2^{246}`, as ensured by
///       `compute_quadratic_expression_limbs` under its parameter bounds.
///
/// ## Details
/// Each element `i` in `limbs` overlaps in bit-range with element `i+1`, EXCEPT for the low 120 bits
/// i.e. we need to do the following for each limb `i`:
///      1. validate the limb's low-120 bits equals zero
///      2. compute the limb "carry" by right-shifting by 2^{120}
///      3. propagate the "carry" into limb `i+1`
/// We can efficiently do all of the above by multiplying the limb by 2^{-120} and constraining the result to be <2^{126}
///
/// If the low 120 bits are nonzero, there is no value in `[0, 2^{126})` that
/// could have produced this limb after multiplying by `2^{120}`. Since
/// multiplication by `2^{120}` is a bijection on the Field, any limb with
/// non-zero low 120 bits must map outside the `[0, 2^{126})` range after
/// scaling by `2^{-120}`.
///
/// The most significant limb has no limb to "carry" values into - the entire limb must equal zero
///
/// ## Note
/// The constant 126 is not arbitrary. We use 120-bit limbs and allow up to 64
/// products per limb, which contributes at most `log2(64) = 6` bits of headroom.
/// After scaling by `2^{-120}`, honest witnesses fit in 126 bits. We could in
/// principle go higher (up to roughly `CircuitModulusBits - 121`), but 126 is
/// the minimal bound consistent with `NUM_PRODUCTS < 64` and is significantly
/// cheaper than larger bounds for the barretenberg backend.
fn validate_expression_is_zero<let N: u32, let LIMBS: u32>(mut limbs: [Field; N]) {
    let hi_shift: Field = TWO_POW_120 as Field;
    let hi_downshift: Field = 1 / hi_shift;
    for i in 0..N - 1 {
        limbs[i] *= hi_downshift;
        std::as_witness(limbs[i]);
        // `LIMBS` is known at compile time, so only one of these range checks is generated
        if uses_wide_carries::<LIMBS>() {
            limbs[i].assert_max_bit_size::<127>();
        } else {
            limbs[i].assert_max_bit_size::<126>();
        }
        limbs[i + 1] += limbs[i];
    }
    assert(limbs[N - 1] == 0);
}

/// Completeness check for `evaluate_quadratic_expression`: ensure that each limb
/// The numbers below are for 126-bit carries. For `BigInt`s with more than 65 limbs, `2^{246}` and
/// `2^{126}` (and the 126-bit range check) become `2^{247}` and `2^{127}`; see `uses_wide_carries`.
///
/// of the convolution product `lhs_linear * rhs_linear` is strictly below `2^{246}`,
/// so that the 126-bit range check in `validate_expression_is_zero` can succeed for
/// honest witnesses.
///
/// Each input is validated to have limbs `< 2^{120}` (non-top) or `< 2^{TOP_LIMB_BITS}`
/// (top), where `TOP_LIMB_BITS = BITS - (N - 1) * 120`. After
/// `compute_linear_expressions` sums `LHS_N` terms per side, each non-top limb of
/// `lhs_linear` is at most `LHS_N * (2^{120} - 1)` and the top limb is at most
/// `LHS_N * (2^{TOP_LIMB_BITS} - 1)`. Similarly for `rhs_linear`.
///
/// The product has `2N - 1` limbs. At position `k`, the convolution is
/// `sum_{i + j = k} lhs_linear[i] * rhs_linear[j]`. The two candidate positions for
/// the largest value are:
///
///   - Position `N - 2`: `N - 1` pairs, all non-top * non-top. Dominates when
///     `TOP_LIMB_BITS < 120` (the common case).
///   - Position `N - 1`: `N` pairs, two of which mix a top limb with a non-top limb.
///     Dominates only when `TOP_LIMB_BITS == 120`.
///
/// ## Note on negation flags
/// When a flag is true the term is subtracted rather than added, so each limb of `lhs_linear`
/// and `rhs_linear` lies in `(-LHS_N * 2^{120}, LHS_N * 2^{120})`, and the bounds below bound the
/// absolute value of each product limb.
///
/// ## Note on `Field.lt()` precision
/// These checks use `Field` arithmetic. If the product exceeds the field modulus
/// `p` (`~2^{254}`), `Field.lt()` could wrap around and give a false pass. This
/// requires roughly `NUM_PRODUCTS * LHS_N * RHS_N * (N - 1) > 2^{14}`, which is
/// unrealistic in practice.
pub(crate) fn assert_product_limbs_fit<let N: u32, let BITS: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32>() {
    let top_limb_bits: u128 = (BITS - (N - 1) * 120) as u128;
    let max_non_top_limb: Field = (TWO_POW_120 - 1) as Field;
    let max_top_limb: Field = ((1u128 << top_limb_bits) - 1) as Field;

    // Over the whole expression, each convolution coefficient is summed `NUM_PRODUCTS`
    // times, and each pair of linear combinations contributes `LHS_N * RHS_N` sub-products.
    let num_sub_products_per_limb: Field = NUM_PRODUCTS as Field * LHS_N as Field * RHS_N as Field;

    // Each product limb must be below `2^{120 + CARRY_BITS}`, see `uses_wide_carries`
    let wide: bool = uses_wide_carries::<N>();
    let limit_bits: u32 = if wide { 247 } else { 246 };
    let limit: Field = if wide { TWO_POW_247 } else { TWO_POW_246 };

    // Position `N - 1` has `N` pairs: two mix a top limb with a non-top limb,
    // the remaining `N - 2` are both non-top.
    let n_minus_1: u32 = N - 1;
    let max_limb_at_pos_n_minus_1: Field =
        max_non_top_limb * (2 * max_top_limb + (N - 2) as Field * max_non_top_limb);
    assert(
        (num_sub_products_per_limb * max_limb_at_pos_n_minus_1).lt(limit),
        f"product limbs may exceed 2^{limit_bits} at limb {n_minus_1}",
    );

    // Position `N - 2` has `N - 1` pairs, all non-top * non-top.
    let n_minus_2: u32 = N - 2;
    let max_limb_at_pos_n_minus_2: Field = (N - 1) as Field * max_non_top_limb * max_non_top_limb;
    assert(
        (num_sub_products_per_limb * max_limb_at_pos_n_minus_2).lt(limit),
        f"product limbs may exceed 2^{limit_bits} at limb {n_minus_2}",
    );
}

/// Constrain a degree-2 `BigInt` expression to be equal to 0 over the integers
///
/// ## Details
///
/// The constrained expression, viewed over the integers, is:
///
///       \sum_{i=0}^{NUM_PRODUCTS-1} (L_i * R_i)
///     + \sum_{i=0}^{ADD_N-1} (A_i)
///     = 0
///
/// Each `L_i`, `R_i` is a linear combination of `BigInt` terms assembled from the
/// `(terms, flags)` arrays, where a `true` flag negates the term. For example, for `i = 0`:
///
///     L_0 = \sum_{j=0}^{LHS_N-1} (-1)^{lhs_flags[0][j]} lhs[0][j]
///     R_0 = \sum_{j=0}^{RHS_N-1} (-1)^{rhs_flags[0][j]} rhs[0][j]
///
/// The intent is to capture a generic degree-2 expression within Noir's
/// limitations (no efficient dynamically sized vectors).
///
/// As the relation must hold exactly, and every term is range-checked to `BITS` bits, an
/// expression such as `x * y - z = 0` constrains `z` to be exactly `x * y`, and so fails if
/// `x * y >= 2^BITS`.
///
/// The expensive parts of this algorithm are:
///   1. evaluating the limb products required to compute the `L_i * R_i` values;
///   2. applying range constraints to validate that the result encodes 0.
///
/// ## Note
/// When the expression is evaluated over `N`-limb `BigInt` values, the product
/// has up to `2N - 1` significant limbs. Each limb is a sum of at most
/// `NUM_PRODUCTS` products of `linear` 120-bit limbs and `quadratic` 240-bit-ish limbs
///
/// Note that:
///   * limb-wise multiplication is not uniform across indices. For example:
///
///       [x0, x1, x2] * [y0, y1, y2] =
///       [
///         x0*y0,                               // 1 term
///         x0*y1 + x1*y0,                       // 2 terms
///         x0*y2 + x1*y1 + x2*y0,               // 3 terms
///         x1*y2 + x2*y1,                       // 2 terms
///         x2*y2                                // 1 term
///       ]
///       The number of partial products per limb grows linearly from 1 to N,
///       then decreases linearly back to 1.
///
///   * we also allow linear combinations inside the products, which further increases the bound
///     on a `quadratic` limb
///
/// ## Assumptions
///
/// Each `BigInt` value used in this gadget is range constrained by this function:
///   - limbs `0..N-2` satisfy `limb_i < 2^{120}`
///   - limb `N-1` satisfies `limb_{N-1} < 2^{TOP_LIMB_BITS}`
///
/// ## Completeness
/// If an honest prover supplies inputs that satisfy the assumptions above and the relation, it
/// can always find `borrow_flags` such that all constraints are satisfied, provided every limb of
/// the expression is below `2^{246}` in absolute value. This is enforced at compile time by
/// `assert_product_limbs_fit`.
///
/// ## Soundness
/// `validate_expression_is_zero` constrains the (borrow-adjusted) limbs to encode `0` over the
/// integers. The magnitudes of all limbs and carries are far below the circuit field modulus, so
/// the `Field` constraints coincide with the corresponding integer relations.
pub(crate) fn evaluate_quadratic_expression<let N: u32, let BITS: u32, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: &[[[u128; N]; LHS_N]; NUM_PRODUCTS],
    lhs_flags: &[[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: &[[[u128; N]; RHS_N]; NUM_PRODUCTS],
    rhs_flags: &[[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: &[[u128; N]; ADD_N],
    linear_flags: &[bool; ADD_N],
) {
    assert_product_limbs_fit::<N, BITS, LHS_N, RHS_N, NUM_PRODUCTS>();

    lhs_terms.for_each(|lhs_limbs: [[u128; N]; LHS_N]| {
        lhs_limbs.for_each(|term: [u128; N]| validate_in_range::<N, BITS>(&term))
    });
    rhs_terms.for_each(|rhs_limbs: [[u128; N]; RHS_N]| {
        rhs_limbs.for_each(|term: [u128; N]| validate_in_range::<N, BITS>(&term))
    });
    linear_terms.for_each(|term: [u128; N]| validate_in_range::<N, BITS>(&term));

    let expression_limbs: [Field; 2 * N - 1] = compute_quadratic_expression_limbs::<N, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        lhs_terms,
        lhs_flags,
        rhs_terms,
        rhs_flags,
        linear_terms,
        linear_flags,
    );
    validate_expression_is_zero::<_, N>(expression_limbs);
}

// ------------------------------ MUL ADD EXPRESSION ------------------------------

/// Compute the borrow flags for the expression `lhs * rhs + addend - result`, which is equal to
/// `0` over the integers (unconstrained)
///
/// A specialisation of `__compute_quadratic_expression_borrow_flags` for a single product of
/// non-negative values. As `lhs * rhs + addend = result < 2^{120 * N}` for an honest witness, only
/// the least-significant `N` limbs of the product are needed.
unconstrained fn __compute_mul_add_expression_borrow_flags<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
    addend: &[u128; N],
    result: &[u128; N],
) -> [bool; N - 1] {
    let mut product_limbs: [Field; N] = [0; N];
    let mut result_field: [Field; N] = [0; N];
    for i in 0..N {
        for j in 0..N - i {
            product_limbs[i + j] += (lhs[i] as Field) * (rhs[j] as Field);
        }
        product_limbs[i] += (addend[i] as Field);

        result_field[i] = result[i] as Field;
    }

    __compute_borrow_flags::<_, N>(product_limbs, result_field)
}

/// Constrained version of `__compute_mul_add_expression_borrow_flags`
///
/// Computes the limbs of `lhs * rhs + addend - result` in-circuit, with borrow flags applied.
///
/// ## Soundness note
/// We compute the full convolution `lhs * rhs` into `2N - 1` limbs and then constrain all limbs
/// with index `i >= N` to be zero. For `i >= N` the value `expression_limbs_full[i]` is a sum of
/// products
///     sum_{j+k=i} lhs[j] * rhs[k]
/// with no contribution from `addend` or `result`.
///
/// Every limb of `lhs` and `rhs` is range-constrained to be a 120-bit integer, so each product
/// term is non-negative and < 2^{240}, and each coefficient of the convolution is strictly smaller
/// than the field modulus. In this regime, the constraint `expression_limbs_full[i] == 0` in
/// `Field` coincides with the same equality over the integers, and as every product is
/// non-negative, it holds exactly when every product in the limb is zero.
///
/// Vanishing of all high limbs `i >= N` is therefore an integer statement that the product has
/// degree < N, i.e. `lhs * rhs < 2^{120 * N}`.
fn compute_mul_add_expression<let N: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
    addend: &[u128; N],
    result: &[u128; N],
) -> [Field; N] {
    // Safety: the borrow flags are constrained by `validate_expression_is_zero`
    let borrow_flags: [bool; N - 1] =
        unsafe { __compute_mul_add_expression_borrow_flags::<N>(lhs, rhs, addend, result) };

    let mut expression_limbs_full: [Field; 2 * N - 1] = [0; 2 * N - 1];
    for i in 0..N {
        for j in 0..N {
            expression_limbs_full[i + j] += (lhs[i] as Field) * (rhs[j] as Field);
        }
        expression_limbs_full[i] += (addend[i] as Field) - (result[i] as Field);
    }

    let mut expression_limbs: [Field; N] = [0; N];
    for i in 0..N {
        expression_limbs[i] = expression_limbs_full[i];
    }
    for i in N..2 * N - 1 {
        assert(expression_limbs_full[i] == 0);
    }

    apply_borrow_flags::<_, N>(expression_limbs, borrow_flags)
}

/// Constrain `lhs * rhs + addend == result` over the integers
///
/// All four values are range-checked to be valid `BigInt` values, i.e. `< 2^BITS`. In particular
/// `lhs * rhs + addend < 2^BITS`, so the operation does not overflow.
///
/// This is used for multiplication (`addend = 0`) and for integer division with remainder
/// (`quotient * divisor + remainder == numerator`).
///
/// ## Completeness
/// If an honest prover supplies valid `BigInt` inputs that satisfy the equation, it can always
/// find `borrow_flags` such that all constraints are satisfied, provided `N < 64`.
///
/// ## Soundness
/// See `compute_mul_add_expression` and `validate_expression_is_zero`. Note that this only
/// constrains the relation itself: e.g. for division it does not by itself enforce
/// `remainder < divisor`.
pub(crate) fn validate_mul_add_expression<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
    addend: &[u128; N],
    result: &[u128; N],
) {
    // The relation `lhs * rhs + addend - result = 0` is a single degree-2 product with no linear
    // combinations, i.e. NUM_PRODUCTS = LHS_N = RHS_N = 1.
    assert_product_limbs_fit::<N, BITS, 1, 1, 1>();

    validate_in_range::<N, BITS>(lhs);
    validate_in_range::<N, BITS>(rhs);
    validate_in_range::<N, BITS>(addend);
    validate_in_range::<N, BITS>(result);

    let expression_limbs: [Field; N] = compute_mul_add_expression::<N>(lhs, rhs, addend, result);
    validate_expression_is_zero::<_, N>(expression_limbs);
}
