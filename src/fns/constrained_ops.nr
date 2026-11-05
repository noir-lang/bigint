use crate::constants::{GRUMPKIN_MODULUS, TWO_POW_120, TWO_POW_240};

use crate::fns::{
    expressions::{evaluate_quadratic_expression, validate_div_rem_expression},
    unconstrained_helpers::{
        __from_field, compute_borrow_flags, compute_carry_flags, compute_gte_flags,
        compute_sub_borrow_flags,
    },
    unconstrained_ops::{__add, __div_rem, __mul, __sub},
};

use std::cmp::Ordering;

/// Lift the limbs of a `BigInt` value onto the circuit `Field`
///
/// Descent the `BigInt` value back into the `Field` and
///    - check that it's a proper `BigInt` value
///    - validate the limbs sum up to a `Field` value
pub(crate) fn limbs_to_field<let N: u32, let BITS: u32>(limbs: &[u128; N]) -> Field {
    validate_in_range::<N, BITS>(limbs);
    // `validate_in_range` bounds `limbs` by `2^BITS`, so when `BITS < 254` the value is
    // already known to be smaller than the Grumpkin modulus: the latter's top limb is `0x3064`,
    // hence `GRUMPKIN_MODULUS > 0x3064 * 2^240 > 2^253`. Only `BITS >= 254` needs the
    // explicit comparison below.
    //
    // The comparison must be *skipped* rather than left in as a redundant check: `validate_gt`
    // range-constrains the top limb of `GRUMPKIN_MODULUS - limbs` to `BITS - (N - 1) * 120`
    // bits, which for e.g. `BITS = 253, N = 3` is 13 bits — too tight to hold the Grumpkin
    // modulus' own 14-bit top limb, so every value would fail the range check.
    if (N > 2) & (BITS >= 254) {
        // validate that the `BigInt` is less than the Grumpkin modulus
        let mut grumpkin_modulus: [u128; N] = [0; N];
        grumpkin_modulus[0] = GRUMPKIN_MODULUS[0];
        grumpkin_modulus[1] = GRUMPKIN_MODULUS[1];
        grumpkin_modulus[2] = GRUMPKIN_MODULUS[2];
        validate_gt::<N, BITS>(&grumpkin_modulus, limbs);
    }

    limbs_to_field_unchecked(limbs)
}

/// Sum the (at most 3) limbs of a `BigInt` value whose value is below the circuit field modulus
/// into a `Field`, without any range checks.
fn limbs_to_field_unchecked<let N: u32>(limbs: &[u128; N]) -> Field {
    if N < 2 {
        limbs[0] as Field
    } else if N == 2 {
        (limbs[0] as Field) + (limbs[1] as Field) * (TWO_POW_120 as Field)
    } else {
        (limbs[0] as Field)
            + (limbs[1] as Field) * (TWO_POW_120 as Field)
            + (limbs[2] as Field) * TWO_POW_240
    }
}

/// Construct a `BigInt` value from a native `Field`
///
/// Decomposes the `Field` value into 120-bit limbs
/// then we have two cases:
///     - BITS <= 253: `2^BITS <= 2^253` is smaller than the Grumpkin modulus,
///       so the range check on the limbs is sufficient
///     - BITS > 253: we need to verify that the obtained `BigInt` `val < GRUMPKIN_MODULUS`
/// Next we verify that all the limbs are properly ranged
/// and that the accumulated limbs are equal to the input `Field` value
pub fn from_field<let N: u32, let BITS: u32>(val: Field) -> [u128; N] {
    // Safety: we check that the resulting limbs represent the intended field element
    // we check the bit length, the limbs being max 120 bits, and the value in total is less than the field modulus
    let result: [u128; N] = unsafe { __from_field::<N>(val) };

    if std::runtime::is_unconstrained() {
        // `__from_field` truncates values which do not fit in `N` limbs, so check that the limbs
        // encode `val` and that the top limb fits in `BITS - 120 * (N - 1)` bits.
        let top_limb_bits: u128 = (BITS - (N - 1) * 120) as u128;
        assert(
            (limbs_to_field_unchecked(&result) == val) & ((result[N - 1] >> top_limb_bits) == 0),
            "attempt to convert a Field which does not fit",
        );
    } else {
        // validate the limbs are in range and the value in total is less than the Grumpkin modulus
        if BITS > 253 {
            // `2^BITS` is larger than the Grumpkin modulus, so check against it explicitly.
            // N is always at least 3 here.
            let mut grumpkin_modulus: [u128; N] = [0; N];
            grumpkin_modulus[0] = GRUMPKIN_MODULUS[0];
            grumpkin_modulus[1] = GRUMPKIN_MODULUS[1];
            grumpkin_modulus[2] = GRUMPKIN_MODULUS[2];
            validate_gt::<N, BITS>(&grumpkin_modulus, &result);
        }
        validate_in_range::<N, BITS>(&result);

        // validate the limbs sum up to the field value
        assert_eq(limbs_to_field_unchecked(&result), val);
    }

    result
}

/// Split `x < 2^TOTAL_BITS` into `(lo, hi)` such that `x = lo + 2^LOW_BITS * hi`,
/// with `lo < 2^LOW_BITS` and `hi < 2^(TOTAL_BITS - LOW_BITS)`.
///
/// The caller must ensure that `x < 2^TOTAL_BITS` and `TOTAL_BITS <= 128`, so that the
/// decomposition is unique.
fn split_bits<let LOW_BITS: u32, let TOTAL_BITS: u32>(x: Field) -> (Field, Field) {
    // Safety: the decomposition is range checked and recomposed below
    let (lo, hi): (Field, Field) = unsafe { __split_bits::<LOW_BITS>(x) };
    lo.assert_max_bit_size::<LOW_BITS>();
    hi.assert_max_bit_size::<TOTAL_BITS - LOW_BITS>();
    assert_eq(x, lo + hi * (2 as Field).pow_32(LOW_BITS as Field));
    (lo, hi)
}

unconstrained fn __split_bits<let LOW_BITS: u32>(x: Field) -> (Field, Field) {
    let lo: Field = ((x as u128) % ((1 as u128) << (LOW_BITS as u128))) as Field;
    let hi: Field = (x - lo) / (2 as Field).pow_32(LOW_BITS as Field);
    (lo, hi)
}

/// Given an input seed, generate a pseudorandom `BigInt` value
///
/// This function *should* produce a uniformly randomly distributed value modulo `MOD = 2^BITS`
///
///  First we take the seed and pack its 31-byte chunks into `Field`s.
///  A length separator (SeedBytes) is appended to the seed before hashing
///  to prevent collisions between seeds that differ only in leading zeros.
///
///  We use a hash function that can be modelled as a random oracle.
///  We hash the packed seed using Poseidon2, then expand it into two 120-bit limbs
///  (the lower 240 bits of the output) per additional hash invocation.
///
///  As `MOD` is a power of two, a uniformly random value modulo `MOD` is just its
///  `BITS` least significant bits. We therefore fill the lower `N - 1` limbs with
///  120 bits each, and the top limb with the remaining `BITS - 120 * (N - 1)` bits.
///
/// The output is a deterministic, publicly computable function of the seed, intended for testing.
/// Do not use it where the seed is secret or guessable.
///
/// Fails if the seed has 256 or more bytes.
pub fn derive_from_seed<let N: u32, let BITS: u32, let SeedBytes: u32>(
    seed: [u8; SeedBytes],
) -> [u128; N] {
    // Pack seed bytes into Fields.
    // For the seed of length M, we construct a rolling_hash_field of size ceil(M / 31).
    // i.e.  31 bytes per Field
    // NOTE: the Fields produced are 248 bits in size

    assert(SeedBytes < 256, "derive_from_seed: seed is too big");
    let mut rolling_hash_fields: [Field; (SeedBytes + 31) / 31] = [0; (SeedBytes + 31) / 31];
    let mut seed_ptr: u32 = 0;
    for i in 0..(SeedBytes + 31) / 31 {
        let mut packed: Field = 0;
        for _ in 0..31 {
            if (seed_ptr < SeedBytes) {
                packed *= 256;
                packed += seed[seed_ptr] as Field;
                seed_ptr += 1;
            } else if seed_ptr == SeedBytes {
                packed *= 256;
                packed += SeedBytes as Field;
                seed_ptr += 1;
            }
        }
        rolling_hash_fields[i] = packed;
    }

    let compressed: Field =
        poseidon::poseidon2::Poseidon2::hash(rolling_hash_fields, (SeedBytes + 31) / 31);
    let mut rolling_hash: [Field; 2] = [compressed, 0];

    // Each hash produces 254 bits, of which we take only the lower 240 bits,
    // i.e. two 120-bit limbs. We therefore need ceil(N / 2) hashes.
    let mut hash_limbs: [Field; (N + 1) / 2 * 2] = [0; (N + 1) / 2 * 2];
    for i in 0..(N + 1) / 2 {
        let hash: Field = poseidon::poseidon2::Poseidon2::hash(rolling_hash, 2);
        // `decompose` is canonical, i.e. `hash = lo + 2^128 * hi` with `lo < 2^128`, `hi < 2^126`
        let (lo, hi): (Field, Field) = std::field::bn254::decompose(hash);
        // bits [0, 120) of the hash
        let (limb_0, lo_top): (Field, Field) = split_bits::<120, 128>(lo);
        // bits [120, 240) of the hash
        let (hi_bottom, _): (Field, Field) = split_bits::<112, 126>(hi);
        hash_limbs[2 * i] = limb_0;
        hash_limbs[2 * i + 1] = lo_top + hi_bottom * 256;
        rolling_hash[1] += 1;
    }

    let mut result: [u128; N] = [0; N];
    for i in 0..N - 1 {
        result[i] = hash_limbs[i] as u128;
    }

    // Truncate the top limb to `BITS - 120 * (N - 1)` bits
    let (top_limb, _): (Field, Field) = split_bits::<BITS - 120 * (N - 1), 120>(hash_limbs[N - 1]);
    result[N - 1] = top_limb as u128;

    result
}

// ------------------------------ COMPARISON FUNCTIONS ------------------------------

/// Validate lhs != rhs
///
/// We compare `A` and `B` via their encodings in the circuit `Field`, constraining that
/// `A - B != 0 (mod p)`.
///
/// ## Soundness
/// If `A == B`, then `A - B == 0` in `Field`, so the assertion fails.
///
/// ## Completeness
/// If `2^BITS > p`, distinct values may be congruent modulo `p`, in which case an honest prover
/// with `A != B` fails the assertion. For random `A, B` the probability of this is roughly 1/p.
/// For `BITS < 254`, `|A - B| < p` and this function is complete.
pub fn assert_is_not_equal<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) {
    let mut l: Field = 0;
    let mut r: Field = 0;
    for i in 0..N {
        l *= TWO_POW_120 as Field;
        r *= TWO_POW_120 as Field;

        l += lhs[N - i - 1] as Field;
        r += rhs[N - i - 1] as Field;
    }

    assert(l != r, "assert_is_not_equal fail");
}

/// Compute equality flag
///
/// Every range-checked `BigInt` value has a unique limb representation, so after range-checking
/// both inputs this is limb-wise equality.
///
/// ## Soundness
/// The inputs must be range-checked here: values which bypass the `BigInt` constructors (e.g.
/// circuit inputs, values returned from unconstrained functions, or `from_limbs_unsafe`) may
/// otherwise encode the same integer with different limbs, e.g. `[2^120, 0, 0]` and `[0, 1, 0]`,
/// and compare as unequal. Range checks are deduplicated per value, so this adds no constraints
/// for inputs which are already range-checked, e.g. the outputs of other operations.
pub fn eq<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> bool {
    validate_in_range::<N, BITS>(lhs);
    validate_in_range::<N, BITS>(rhs);
    *lhs == *rhs
}

/// Check whether a `BigInt` value is zero, i.e. all of its limbs are zero.
///
/// ## Note
/// This sums the limbs instead of testing `val == [0; N]`, which avoids creating per-limb boolean
/// equalities and chaining them with `and`s. As every limb is a `u128`, the sum is below
/// `N * 2^{128}`, which is far smaller than the circuit field modulus `p`, so the sum is zero in
/// `Field` exactly when every limb is zero. This holds even if `val` is not normalised.
pub fn is_zero<let N: u32>(val: &[u128; N]) -> bool {
    let mut limb_sum: Field = 0;
    for i in 0..N {
        limb_sum += val[i].into();
    }
    limb_sum == 0
}

/// Validate that a `BigInt` value is not zero, i.e. at least one of its limbs is non-zero.
///
/// See `is_zero`.
pub fn assert_is_not_zero<let N: u32>(val: &[u128; N]) {
    assert(!is_zero(val), "assert_is_not_zero fail");
}

/// Validate a `BigInt` instance is correctly range constrained to contain no more than `BITS` bits
///
/// Constrain the `BigInt` instance to be < 2^BITS by:
///     - Constraining each limb(0..N-2) to be 120-bit limb
///     - Constraining the last limb to be `BITS - 120 * (N - 1)`
///
/// ## Note
/// This can be a very expensive function, when the `TOP_LIMB_BITS` is uncommon
///
/// For example: a 253-bit modulus, with `TOP_LIMB_BITS`=13
/// It creates a new 13-bit range table, which consists of roughly 3k variables
/// And ~2k circuit gates
///
/// Compare this to `U256`, with `TOP_LIMB_BITS`=17
/// It is nicely decomposed into
/// 14-bit range check and 3-bit range check - much much cheaper, since 14-bit range checks
/// are already pretty common for 120-bit range checks
pub fn validate_in_range<let N: u32, let BITS: u32>(limbs: &[u128; N]) {
    for i in 0..(N - 1) {
        (limbs[i] as Field).assert_max_bit_size::<120>();
    }

    (limbs[N - 1] as Field).assert_max_bit_size::<BITS - ((N - 1) * 120)>();
}

/// Validate quotient produced from `evaluate_quadratic_expression` is well-formed
///
/// Because the inputs into `evaluate_quadratic_expression` may cause the quotient to extend beyond `MOD`.
///           We allow the quotient to extend `6` bits beyond the bit length of `MOD = 2^BITS`, i.e. `quotient < 2^{BITS + 7}`
///           Why is this?
///           several factors:    1. quotient * modulus , limbs cannot overflow `Field` boundary (254 bits)
///                               2. in `evaluate_quadratic_expression`, we require that for `expression - quotient * modulus`,
///                                  limbs cannot exceed `246` bits (246 magic number due to a higher number adding extra range check gates)
///           because of factor 2 and the fact that modulus limbs are 120 bits, quotient limbs cannot be > 126 bits
pub(crate) fn validate_quotient_in_range<let N: u32, let BITS: u32>(limbs: &[u128; N]) {
    for i in 0..(N - 1) {
        (limbs[i] as Field).assert_max_bit_size::<120>();
    }
    (limbs[N - 1] as Field).assert_max_bit_size::<BITS - (N - 1) * 120 + 7>();
}

/// Validate that `lhs - rhs` does not underflow i.e. that lhs > rhs over the integers
///
/// Compute `result = lhs - rhs` along with `borrow_flags`,
/// then constrain `result` to be a valid `BigInt` value.
///
/// ## Completeness
/// This function is complete: it will succeed for any `lhs > rhs` over the integers.
///
/// ## Soundness
/// This function is sound:
///     result[0]     = lhs[0]     - rhs[0]     + bf[0] * 2^{120}             < 2^{120}
///     result[i]     = lhs[i]     - rhs[i]     + bf[i] * 2^{120} - bf[i - 1] < 2^{120},  i = 1..N-2
///     result[N - 1] = lhs[N - 1] - rhs[N - 1]                   - bf[N - 2] < 2^{TOP_LIMB_BITS}
///     result != 0
///
/// If `lhs < rhs`, then some limb of `result` would have to borrow from a higher limb,
/// which is impossible because the top limb cannot borrow
/// Without the extra borrow, the resulting difference will be wrapped around the `Field` modulus
/// And won't satisfy the range constraint, since all the limbs are < 2^120
///
/// ## Note
/// `assert_is_not_zero(result)` is crucial. Without it, we could always provide
/// two identical inputs `x`, `x` and set `borrow_flags = [false; N]`,
/// which would satisfy the limb constraints.
pub(crate) fn validate_gt<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) {
    // Safety: borrow_flags are constrained by `assert_sub_no_overflow`:
    // - incorrect flags cause the computed result to fail 128-bit range checks
    // - if lhs < rhs, the subtraction overflows Field and fails range checks
    let borrow_flags: [bool; N - 1] = unsafe { compute_borrow_flags(lhs, rhs) };

    // Compute and validate the result in constrained code
    let result: [u128; N] = assert_sub_no_overflow::<N, BITS>(lhs, rhs, &borrow_flags);

    // Constrain it to be strict inequality
    assert_is_not_zero(&result);
}

/// Compute the result of lhs - rhs given borrow flags and validate it
///
/// This is the constrained analog of the result computation in the unconstrained helpers.
/// Given borrow_flags, computes result such that:
///     result[0]     = lhs[0]     - rhs[0]     + bf[0] * 2^{120}
///     result[i]     = lhs[i]     - rhs[i]     + bf[i] * 2^{120} - bf[i - 1],  i = 1..N-2
///     result[N - 1] = lhs[N - 1] - rhs[N - 1]                   - bf[N - 2]
///
/// Also validates that the result is a valid BigInt value (each limb in range).
/// If lhs < rhs, the result will have a negative value (wrapped in Field) and fail validation.
pub(crate) fn assert_sub_no_overflow<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
    borrow_flags: &[bool; N - 1],
) -> [u128; N] {
    let mut limbs: [Field; N] = [0; N];

    // Compute first limb
    limbs[0] =
        (lhs[0] as Field) - (rhs[0] as Field) + (borrow_flags[0] as Field) * (TWO_POW_120 as Field);

    // Compute middle limbs
    for i in 1..N - 1 {
        limbs[i] = (lhs[i] as Field) - (rhs[i] as Field)
            + (borrow_flags[i] as Field) * (TWO_POW_120 as Field)
            - (borrow_flags[i - 1] as Field);
    }

    // Compute last limb
    limbs[N - 1] = (lhs[N - 1] as Field) - (rhs[N - 1] as Field) - (borrow_flags[N - 2] as Field);

    // Validate that the result is a valid BigInt value (120-bit limbs, TOP_LIMB_BITS for last)
    field_limbs_to_bigint::<N, BITS>(limbs)
}

/// Range-checks limbs computed as `Field` elements and converts them to a `BigInt` value.
///
/// Limbs `0..N-1` are constrained to 120 bits and the top limb to `BITS - 120 * (N - 1)` bits.
/// Range-checking the `Field` values before casting them to `u128` ensures that the cast cannot
/// truncate.
fn field_limbs_to_bigint<let N: u32, let BITS: u32>(limbs: [Field; N]) -> [u128; N] {
    let mut result: [u128; N] = [0; N];
    for i in 0..N - 1 {
        limbs[i].assert_max_bit_size::<120>();
        result[i] = limbs[i] as u128;
    }
    limbs[N - 1].assert_max_bit_size::<BITS - (N - 1) * 120>();
    result[N - 1] = limbs[N - 1] as u128;
    result
}

/// Compare two `BigInt` values, returning their `Ordering`.
///
/// Performs a strict integer comparison over the limb representation,
/// **not** modular ordering.
pub fn cmp<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> Ordering {
    // `Equal` is decided by limb-wise equality, which requires the inputs to be range-checked.
    // See `eq` for details.
    validate_in_range::<N, BITS>(lhs);
    validate_in_range::<N, BITS>(rhs);

    // Safety: underflow and borrow_flags are constrained by `assert_sub_no_overflow`:
    // - we swap (a, b) based on underflow, then compute a - b
    // - if underflow is wrong, a < b and the subtraction overflows, failing range checks
    // - if borrow_flags are wrong, the computed limbs fail 128-bit range checks
    let (underflow, borrow_flags): (bool, [bool; N - 1]) = unsafe { compute_gte_flags(lhs, rhs) };

    // if underflow is true, swap lhs and rhs so we compute larger - smaller
    let (a, b): ([u128; N], [u128; N]) = if underflow {
        (*rhs, *lhs)
    } else {
        (*lhs, *rhs)
    };

    // Enforce correctness of `underflow` by asserting that the subtraction does not overflow.
    let _: [u128; N] = assert_sub_no_overflow::<N, BITS>(&a, &b, &borrow_flags);

    if *lhs == *rhs {
        Ordering::equal()
    } else if underflow {
        Ordering::less()
    } else {
        Ordering::greater()
    }
}

// ------------------------------ ARITHMETIC FUNCTIONS ------------------------------

/// Compute the `BigInt` multiplication
///
/// Computes `result = lhs * rhs (mod MOD)` by:
///   1. Computing `result` out of circuit via `__mul`.
///   2. Constraining the quadratic relation `lhs * rhs - result = 0` with
///      `evaluate_quadratic_expression`.
///
/// ## Soundness
/// Soundness reduces to `evaluate_quadratic_expression` for the relation
/// `lhs * rhs - result = 0`
///
/// ## Note
/// When possible, prefer expressing your computation directly as a quadratic
///   relation and calling `evaluate_quadratic_expression` instead of using `mul`
pub fn mul<let N: u32, let BITS: u32>(lhs: [u128; N], rhs: [u128; N]) -> [u128; N] {
    // Safety: we constrain the multiplication result immediately after
    let result: [u128; N] = unsafe { __mul::<N, BITS>(&lhs, &rhs) };
    if !std::runtime::is_unconstrained() {
        // lhs * rhs - result = 0
        let lhs_terms: [[[u128; N]; 1]; 1] = [[lhs]];
        let lhs_flags: [[bool; 1]; 1] = [[false]];
        let rhs_terms: [[[u128; N]; 1]; 1] = [[rhs]];
        let rhs_flags: [[bool; 1]; 1] = [[false]];
        let linear_terms: [[u128; N]; 1] = [result];
        let linear_flags: [bool; 1] = [true];
        evaluate_quadratic_expression::<N, BITS, 1, 1, 1, 1>(
            &lhs_terms,
            &lhs_flags,
            &rhs_terms,
            &rhs_flags,
            &linear_terms,
            &linear_flags,
        );
    }
    result
}

/// Add two `BigInt` values, failing if the sum overflows `2^BITS`.
///
/// Computes `result = lhs + rhs` limb-wise with carry flags provided by the prover:
///
///     result[0]     = lhs[0]     + rhs[0]                - c[0]     * 2^{120}
///     result[i]     = lhs[i]     + rhs[i]     + c[i - 1] - c[i]     * 2^{120}
///     result[N - 1] = lhs[N - 1] + rhs[N - 1] + c[N - 2]
///
/// and range-checks every limb of `result`.
///
/// ## Soundness
/// The carries telescope, so `\sum result[i] * 2^{120 i} = lhs + rhs` over the integers (each
/// limb is far below the circuit field modulus, so no wraparound occurs). The range checks then
/// enforce `0 <= result < 2^BITS`, so `result` is the unique valid representation of `lhs + rhs`,
/// and an overflowing sum fails the range check on the top limb. Incorrect carry flags make a
/// limb negative (i.e. a large `Field` element) or `>= 2^{120}`, and also fail.
///
/// This holds for any input limbs below `2^{128}`, i.e. the inputs do not need to be normalised.
pub fn add<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> [u128; N] {
    if std::runtime::is_unconstrained() {
        // Safety: unconstrained runtime requires no constraints
        unsafe {
            __add::<N, BITS>(lhs, rhs)
        }
    } else {
        // Safety: the carry flags are constrained by `assert_add_no_overflow`
        let carry_flags: [bool; N - 1] = unsafe { compute_carry_flags::<N, BITS>(lhs, rhs) };

        assert_add_no_overflow::<N, BITS>(lhs, rhs, &carry_flags)
    }
}

/// Compute `lhs + rhs` from prover-provided carry flags, and constrain it not to overflow `2^BITS`.
///
/// See `add` for the soundness argument: any carry flags which do not yield the unique valid
/// representation of `lhs + rhs`, or a sum `>= 2^BITS`, fail the range checks.
pub(crate) fn assert_add_no_overflow<let N: u32, let BITS: u32>(
    lhs: &[u128; N],
    rhs: &[u128; N],
    carry_flags: &[bool; N - 1],
) -> [u128; N] {
    let mut limbs: [Field; N] = [0; N];
    limbs[0] =
        (lhs[0] as Field) + (rhs[0] as Field) - (carry_flags[0] as Field) * (TWO_POW_120 as Field);
    for i in 1..N - 1 {
        limbs[i] = (lhs[i] as Field) + (rhs[i] as Field) + (carry_flags[i - 1] as Field)
            - (carry_flags[i] as Field) * (TWO_POW_120 as Field);
    }
    limbs[N - 1] = (lhs[N - 1] as Field) + (rhs[N - 1] as Field) + (carry_flags[N - 2] as Field);

    field_limbs_to_bigint::<N, BITS>(limbs)
}

/// Subtract two `BigInt` values, failing if `rhs > lhs`.
///
/// Computes `result = lhs - rhs` limb-wise with borrow flags provided by the prover, and
/// range-checks every limb of `result`. See `assert_sub_no_overflow`.
///
/// ## Soundness
/// As for `add`, the borrows telescope, so `\sum result[i] * 2^{120 i} = lhs - rhs` over the
/// integers, and the range checks enforce `0 <= result < 2^BITS`. If `rhs > lhs`, the top limb
/// is negative, i.e. a large `Field` element, and fails its range check.
pub fn sub<let N: u32, let BITS: u32>(lhs: &[u128; N], rhs: &[u128; N]) -> [u128; N] {
    if std::runtime::is_unconstrained() {
        // Safety: unconstrained runtime requires no constraints
        unsafe {
            __sub::<N, BITS>(lhs, rhs)
        }
    } else {
        // Safety: the borrow flags are constrained by `assert_sub_no_overflow`
        let borrow_flags: [bool; N - 1] = unsafe { compute_sub_borrow_flags(lhs, rhs) };
        assert_sub_no_overflow::<N, BITS>(lhs, rhs, &borrow_flags)
    }
}

/// Compute the `BigInt` integer division with remainder
///
/// Computes `quotient = floor(numerator / divisor)` and
/// `remainder = numerator % divisor`, i.e. Euclidean division (which coincides with floored and
/// truncated division for unsigned integers), by:
///   1. Computing `(quotient, remainder)` out of circuit via `__div_rem`.
///   2. Constraining the quadratic relation
///        quotient * divisor + remainder - numerator = 0
///      with `validate_div_rem_expression`.
///   3. Enforcing `remainder < divisor`.
///
/// ## Soundness
/// Soundness reduces to `validate_div_rem_expression` for the relation
///     quotient * divisor + remainder - numerator = 0,
/// together with `remainder < divisor` check enforced via `validate_gt`.
///
/// Under these checks, and as `numerator` and `divisor` are range-checked `BigInt` values,
/// any satisfying assignment corresponds to a valid integer division
/// `numerator = quotient * divisor + remainder` with
/// `0 <= remainder < divisor < 2^BITS`
/// `0 <= numerator < 2^BITS`
///
/// ## Note
/// Enforcing `divisor != 0` is not necessary. `remainder < divisor`
/// Already enforces this.
pub fn div_rem<let N: u32, let BITS: u32>(
    numerator: &[u128; N],
    divisor: &[u128; N],
) -> ([u128; N], [u128; N]) {
    // Safety: We constrain the result of __div_rem immediately after
    let (quotient, remainder): ([u128; N], [u128; N]) = unsafe { __div_rem(numerator, divisor) };
    if !std::runtime::is_unconstrained() {
        // quotient * divisor + remainder - numerator = 0
        validate_div_rem_expression::<N, BITS>(numerator, divisor, &quotient, &remainder);
        // remainder < divisor
        validate_gt::<N, BITS>(divisor, &remainder);
    }
    (quotient, remainder)
}

/// Compute the `BigInt` integer division.
///
/// Returns `floor(numerator / divisor)`.
/// All constraints and soundness details are handled inside `div_rem`.
pub fn div<let N: u32, let BITS: u32>(numerator: &[u128; N], divisor: &[u128; N]) -> [u128; N] {
    div_rem::<N, BITS>(numerator, divisor).0
}

/// Compute the `BigInt` remainder.
///
/// Returns `numerator % divisor`.
/// All constraints and soundness details are handled inside `div_rem`.
pub fn rem<let N: u32, let BITS: u32>(numerator: &[u128; N], divisor: &[u128; N]) -> [u128; N] {
    div_rem::<N, BITS>(numerator, divisor).1
}
