use crate::fns::constrained_ops::limbs_to_field;
use std::ops::{Add, Div, Mul, Rem, Sub};

/// The core trait for fixed-width unsigned integers.
///
/// A `BigInt` is an unsigned integer in `[0, 2^BITS)`. Values are stored as arrays of 120-bit
/// limbs in little-endian format. Every value has exactly one limb representation, and all
/// constructors (other than the `*_unsafe` ones) and operations range-check their results.
///
/// # Important Notes
///
/// - **Single-limb BigInt is not supported**: This library assumes at least two 120-bit limbs
///   (`BITS > 120`). Operations on single-limb BigInts may produce incorrect results.
///
/// - **Constrained vs Unconstrained**: Methods prefixed with `__` are unconstrained and do not
///   generate circuit constraints. Use them for witness computation, then constrain results with
///   `evaluate_quadratic_expression` for optimal performance.
///
/// - **Performance**: The overloaded operators (`+`, `-`, `*`, `/`) are constrained and
///   expensive. For multiple operations, prefer using unconstrained methods followed by
///   `evaluate_quadratic_expression`.
///
/// - **Wrapping semantics**: `+`, `-`, `*` and negation wrap, i.e. are computed modulo `2^BITS`.
///
/// # Example
/// ```
/// use bigint::U256;
/// use bigint::BigInt;
///
/// fn example(a: U256, b: U256) -> U256 {
///     // Constrained multiplication
///     a * b
/// }
/// ```
pub trait BigInt: Add + Sub + Mul + Div + Rem + Eq {
    /// Number of 120-bit limbs used to represent this BigInt.
    let N: u32;
    /// Bit width of this BigInt.
    let BITS: u32;

    /// Returns the number of limbs used to represent this BigInt.
    ///
    /// Note: Takes a dummy `Self` parameter for trait method resolution.
    fn num_limbs(_: Self) -> u32;

    /// Creates a new BigInt with value 0.
    ///
    /// Equivalent to `zero()`.
    fn new() -> Self;

    /// Returns the additive identity (0).
    fn zero() -> Self;

    /// Returns the multiplicative identity (1).
    fn one() -> Self;

    /// Constructs a BigInt from raw limbs.
    ///
    /// Each limb is range-checked automatically: at most 120 bits for non-top limbs,
    /// and at most `BITS - 120 * (N - 1)` bits for the top limb.
    fn from_limbs(limbs: [u128; N]) -> Self;

    /// Constructs a BigInt from raw limbs without range-checking.
    ///
    /// # Safety
    /// No range checks are performed on the limbs. The resulting value may not
    /// represent a valid BigInt. Use for cases where limbs intentionally exceed
    /// the normal range (e.g. quotients from unconstrained computation).
    fn from_limbs_unsafe(limbs: [u128; N]) -> Self;

    /// Returns the raw limb representation.
    ///
    /// Limbs are in little-endian order: `limbs[0]` contains the least significant 120 bits.
    fn get_limbs(&self) -> [u128; N];

    /// Sets a specific limb to a new value.
    ///
    /// The new value is range-checked automatically: at most 120 bits for non-top limbs,
    /// and at most `BITS - 120 * (N - 1)` bits for the top limb.
    fn set_limb(self: &mut Self, idx: u32, value: u128);

    /// Sets a specific limb to a new value without range-checking.
    ///
    /// # Safety
    /// No range check is performed on the new value.
    fn set_limb_unsafe(self: &mut Self, idx: u32, value: u128);

    /// Returns the limb at the given index.
    fn get_limb(&self, idx: u32) -> u128;

    /// Generates a deterministic pseudorandom BigInt from a seed.
    ///
    /// Uses Poseidon2 hash to derive `BITS * 2` bits of entropy, then reduces modulo `MOD`.
    ///
    /// # Security Warning
    /// **NOT cryptographically secure for all use cases**. The output is deterministic and
    /// uniformly distributed modulo `MOD`, but the seed-to-output mapping is publicly computable.
    /// Do not use for secret key generation where the seed might be guessable.
    ///
    /// # Constrained
    /// This is a constrained function that generates range check constraints.
    fn derive_from_seed<let SeedBytes: u32>(seed: [u8; SeedBytes]) -> Self;

    /// Unconstrained version of `derive_from_seed`.
    ///
    /// # Safety
    /// No constraints are generated. Use only for witness computation in unconstrained contexts.
    unconstrained fn __derive_from_seed<let SeedBytes: u32>(seed: [u8; SeedBytes]) -> Self;

    /// Constructs a BigInt from big-endian bytes.
    ///
    /// The byte array length must be exactly `(BITS + 7) / 8`.
    ///
    /// # Panics
    /// Panics if the value represented by the bytes is >= 2^BITS.
    fn from_be_bytes(x: [u8; (BITS + 7) / 8]) -> Self;

    /// Converts to big-endian byte representation.
    fn to_be_bytes(&self) -> [u8; (BITS + 7) / 8];

    /// Constructs a BigInt from little-endian bytes.
    ///
    /// The byte array length must be exactly `(BITS + 7) / 8`.
    ///
    /// # Panics
    /// Panics if the value represented by the bytes is >= 2^BITS.
    fn from_le_bytes(x: [u8; (BITS + 7) / 8]) -> Self;

    /// Converts to little-endian byte representation.
    fn to_le_bytes(&self) -> [u8; (BITS + 7) / 8];

    /// Unconstrained equality check.
    ///
    /// Returns `true` if `self == other` as integers (not modular equality).
    ///
    /// # Safety
    /// No constraints are generated. Use `==` operator for constrained equality.
    unconstrained fn __eq(&self, other: &Self) -> bool;

    /// Unconstrained zero check.
    ///
    /// Returns `true` if all limbs are zero.
    ///
    /// # Safety
    /// No constraints are generated. Use `is_zero()` for constrained check.
    unconstrained fn __is_zero(&self) -> bool;

    /// Unconstrained addition: computes `self + other (mod 2^BITS)`.
    ///
    /// # Safety
    /// No constraints are generated. Constrain the result using `evaluate_quadratic_expression`.
    unconstrained fn __add(&self, other: &Self) -> Self;

    /// Unconstrained subtraction: computes `self - other (mod 2^BITS)`.
    ///
    /// # Safety
    /// No constraints are generated. Constrain the result using `evaluate_quadratic_expression`.
    unconstrained fn __sub(&self, other: &Self) -> Self;

    /// Unconstrained multiplication: computes `self * other (mod 2^BITS)`.
    ///
    /// # Safety
    /// No constraints are generated. Constrain the result using `evaluate_quadratic_expression`.
    unconstrained fn __mul(&self, other: &Self) -> Self;

    /// Unconstrained squaring: computes `self * self (mod 2^BITS)`.
    ///
    /// # Safety
    /// No constraints are generated. Constrain the result using `evaluate_quadratic_expression`.
    unconstrained fn __sqr(&self) -> Self;

    /// Unconstrained unsigned integer division: computes `floor(self / other)`.
    ///
    /// # Requirements
    /// - `other` must not be zero
    ///
    /// # Safety
    /// No constraints are generated. Constrain the result using `evaluate_quadratic_expression`.
    unconstrained fn __div(&self, other: &Self) -> Self;

    /// Unconstrained integer division with remainder.
    ///
    /// Returns `(quotient, remainder)` where `self == quotient * divisor + remainder`
    /// and `0 <= remainder < divisor`.
    ///
    /// # Safety
    /// No constraints are generated. Use `div_rem()` for the constrained version.
    unconstrained fn __div_rem(&self, divisor: &Self) -> (Self, Self);

    /// Unconstrained modular exponentiation: computes `self^exponent (mod 2^BITS)`.
    ///
    /// # Performance Warning
    /// **EXPENSIVE**: Complexity is O(BITS) multiplications.
    ///
    /// # Safety
    /// No constraints are generated.
    unconstrained fn __pow(&self, exponent: &Self) -> Self;

    /// Asserts that `self != other`.
    ///
    /// # Performance Note
    /// This is cheaper than `assert(self != other)` because it avoids creating a boolean result.
    ///
    /// # Completeness
    /// The values are compared via their encodings in the circuit `Field`, so this fails for
    /// distinct values which are congruent modulo the circuit field modulus `p`. For values
    /// with `BITS < 254` this cannot happen; otherwise there's a negligible (~1/p) probability
    /// for random inputs.
    fn assert_is_not_equal(&self, other: &Self);

    /// Returns `true` if `self == 0`.
    fn is_zero(&self) -> bool;

    /// Validates that each limb is properly range-constrained.
    ///
    /// Ensures:
    /// - Limbs 0 to N-2 are < 2^120
    /// - Limb N-1 is < 2^(BITS - 120*(N-1))
    ///
    /// # When to Use
    /// Call this after `from_limbs()` or `set_limb()` when the input comes from untrusted sources.
    ///
    /// # Performance Note
    /// Range constraints are deduplicated per value, so calling this multiple times on the same
    /// BigInt does not add duplicate constraints.
    fn validate_in_range(&self);

    /// Constrained squaring: computes `self * self (mod 2^BITS)`.
    ///
    /// # Performance Note
    /// For multiple operations, prefer using `__sqr()` followed by `evaluate_quadratic_expression`.
    fn sqr(&self) -> Self;

    /// Constrained integer division with remainder.
    ///
    /// Returns `(quotient, remainder)` where `self == quotient * divisor + remainder`
    /// and `0 <= remainder < divisor`, i.e. `(self / divisor, self % divisor)`. This is Euclidean
    /// division, which for unsigned integers coincides with floored and truncated division.
    ///
    /// Computing both together is cheaper than computing `/` and `%` separately.
    ///
    /// # Panics
    /// Fails if `divisor == 0`.
    fn div_rem(&self, divisor: &Self) -> (Self, Self);
}

/// Returns `N` for a struct whose only field is `limbs: [u128; N]`.
comptime fn num_limbs_of(strukt: TypeDefinition) -> u32 {
    let fields = strukt.fields_as_written();
    assert(
        fields.len() == 1,
        "derive_bigint: expected a struct with a single field `limbs: [u128; N]`",
    );
    let field = fields[0];
    assert(
        field.name() == quote { limbs },
        "derive_bigint: expected a struct with a single field `limbs: [u128; N]`",
    );
    let array = field.typ().as_array();
    assert(array.is_some(), "derive_bigint: expected `limbs` to have type `[u128; N]`");
    let array = array.unwrap();
    assert(
        array.element_type() == quote { u128 }.as_type(),
        "derive_bigint: expected `limbs` to have type `[u128; N]`",
    );
    let length = array.length_type().as_constant();
    assert(length.is_some(), "derive_bigint: expected `limbs` to have a constant length");
    length.unwrap()
}

/// Implements `BigInt` and the arithmetic and comparison traits for a `BITS`-bit unsigned integer.
///
/// The struct must have a single field `limbs: [u128; N]`, where `N` is the number of 120-bit limbs
/// needed to hold `BITS` bits, i.e. `ceil(BITS / 120)`:
///
/// ```
/// #[derive_bigint(256)]
/// pub struct U256 {
///     limbs: [u128; 3],
/// }
/// ```
///
/// At least two limbs are required, and the top limb must hold between 1 and 118 bits, so widths
/// with `BITS % 120` equal to `0` or `119` are not supported.
pub comptime fn derive_bigint(strukt: TypeDefinition, BITS: u32) -> Quoted {
    let N: u32 = num_limbs_of(strukt);
    let expected_limbs: u32 = (BITS + 119) / 120;
    assert(
        N == expected_limbs,
        f"derive_bigint: a {BITS}-bit integer needs {expected_limbs} limbs, but `limbs` has {N}",
    );
    assert(N >= 2, "derive_bigint: at least two limbs are required");
    let top_limb_bits: u32 = BITS - (N - 1) * 120;
    assert(
        top_limb_bits <= 118,
        f"derive_bigint: unsupported width {BITS}: the top limb would hold {top_limb_bits} bits, but at most 118 are supported",
    );
    let typ = strukt.as_type();
    quote {

        // implement BigInt for BigInt 
        impl $crate::BigInt for $typ {
            let N: u32 = $N; 
            let BITS: u32 = $BITS;
            
            fn num_limbs(_: Self) -> u32 {
                $N
            }

            fn new() -> Self {
                Self {limbs: [0; $N]}
            }

            fn from_limbs(limbs: [u128; $N]) -> Self {
                let res = Self { limbs };
                res.validate_in_range();
                res
            }

            fn from_limbs_unsafe(limbs: [u128; $N]) -> Self {
                Self { limbs }
            }

            fn get_limbs(&self) -> [u128; $N] {
                self.limbs
            }

            fn set_limb(self: &mut Self, idx: u32, value: u128) {
                if idx != ($N - 1){
                    (value as Field).assert_max_bit_size::<120>();
                } else {
                    (value as Field).assert_max_bit_size::<$BITS - 120 * ($N - 1)>();
                }
                self.limbs[idx] = value;
            }

            fn set_limb_unsafe(self: &mut Self, idx: u32, value: u128) {
                self.limbs[idx] = value;
            }

            fn get_limb(&self, idx: u32) -> u128 {
                self.limbs[idx]
            }

            fn zero() -> Self {
                Self { limbs: [0; $N] }
            }

            fn one() -> Self {
                let mut limbs = [0; $N];
                limbs[0] = 1;
                Self { limbs }
            }

            fn derive_from_seed<let SeedBytes: u32>(seed: [u8; SeedBytes]) -> Self {
                $typ::from_limbs($crate::internal::derive_from_seed::<$N, $BITS, SeedBytes>(seed))
            }

            unconstrained fn __derive_from_seed<let SeedBytes: u32>(seed: [u8; SeedBytes]) -> Self {
                Self { limbs: $crate::internal::__derive_from_seed::<$N, $BITS, SeedBytes>(seed) }
            }

            fn from_be_bytes(x: [u8; ($BITS + 7) / 8]) -> Self {
                Self { limbs: $crate::internal::from_be_bytes::<$N, $BITS>(&x) }
            }

            fn to_be_bytes(&self) -> [u8; ($BITS + 7) / 8] {
                $crate::internal::to_be_bytes::<$N, $BITS>(&self.limbs)
            }

            fn from_le_bytes(x: [u8; ($BITS + 7) / 8]) -> Self {
                Self { limbs: $crate::internal::from_le_bytes::<$N, $BITS>(&x) }
            }

            fn to_le_bytes(&self) -> [u8; ($BITS + 7) / 8] {
                $crate::internal::to_le_bytes::<$N, $BITS>(&self.limbs)
            }

            unconstrained fn __eq(&self, other: &Self) -> bool {
                $crate::internal::__eq(&self.get_limbs(), &other.get_limbs())
            }

            unconstrained fn __is_zero(&self) -> bool {
                $crate::internal::__is_zero(&self.get_limbs())
            }

            unconstrained fn __add(&self, other: &Self) -> Self {
                Self {limbs: $crate::internal::__add(&$crate::internal::get_modulus::<$N, $BITS>(), &self.get_limbs(), &other.get_limbs())}
            }

            unconstrained fn __sub(&self, other: &Self) -> Self {
                Self {limbs: $crate::internal::__sub(&$crate::internal::get_modulus::<$N, $BITS>(), &self.get_limbs(), &other.get_limbs())}
            }

            unconstrained fn __mul(&self, other: &Self) -> Self {
                Self {limbs: $crate::internal::__mul::<$N, $BITS>(&self.get_limbs(), &other.get_limbs())}
            }

            unconstrained fn __sqr(&self) -> Self {
                Self {limbs: $crate::internal::__sqr::<$N, $BITS>(&self.get_limbs()) }
            }

            unconstrained fn __div(&self, divisor: &Self) -> Self {
                Self { limbs: $crate::internal::__div_rem(&self.get_limbs(), &divisor.get_limbs()).0 }
            }

            unconstrained fn __div_rem(&self, divisor: &Self) -> (Self, Self) {
                let (q, r) = $crate::internal::__div_rem(&self.get_limbs(), &divisor.get_limbs());
                (Self{limbs: q}, Self{limbs: r})
            }

            unconstrained fn __pow(&self, exponent: &Self) -> Self {
                Self {limbs: $crate::internal::__pow::<$N, $BITS>(&self.get_limbs(), &exponent.get_limbs())}
            }

            fn assert_is_not_equal(&self, other: &Self) {
                let self_limbs = self.get_limbs();
                let other_limbs = other.get_limbs();
                $crate::internal::assert_is_not_equal::<$N, $BITS>(
                    &self_limbs,
                    &other_limbs,
                );
            }

            fn validate_in_range(&self) {
                let limbs = self.get_limbs();
                $crate::internal::validate_in_range::<$N, $BITS>(&limbs);
            }

            fn sqr(&self) -> Self {
                Self { limbs: $crate::internal::sqr::<$N, $BITS>(self.get_limbs()) }
            }

            fn div_rem(&self, divisor: &Self) -> (Self, Self) {
                let self_limbs = self.get_limbs();
                let divisor_limbs = divisor.get_limbs();
                let (q, r) = $crate::internal::div_rem::<$N, $BITS>(&self_limbs, &divisor_limbs);
                (Self {limbs: q}, Self {limbs: r})
            }

            fn is_zero(&self) -> bool {
                let limbs = self.get_limbs();
                $crate::internal::is_zero::<$N, $BITS>(&limbs)
            }

        }

        // implement Default for BigInt
        impl Default for $typ {
            fn default() -> Self {
                $typ::from_limbs([0; $N])
            }
        }

        impl std::convert::From<Field> for $typ {
            fn from(input: Field) -> Self {
                $typ { limbs: $crate::internal::from_field::<$N, $BITS>(input) }
            }
        }

        impl std::ops::Add for $typ {
            fn add(self, other: Self) -> Self {
                $typ { limbs: $crate::internal::add::<$N, $BITS>(&self.limbs, &other.limbs) }
            }
        }

        impl std::ops::Sub for $typ {
            fn sub(self, other: Self) -> Self {
                $typ { limbs: $crate::internal::sub::<$N, $BITS>(&self.limbs, &other.limbs) }
            }
        }

        impl std::ops::Mul for $typ {
            fn mul(self, other: Self) -> Self {
                $typ { limbs: $crate::internal::mul::<$N, $BITS>(self.limbs, other.limbs) }
            }
        }

        impl std::ops::Rem for $typ {
            fn rem(self, other: Self) -> Self {
                $typ { limbs: $crate::internal::rem::<$N, $BITS>(&self.limbs, &other.limbs) }
            }
        }

        impl std::ops::Div for $typ {
            fn div(self, other: Self) -> Self {
                $typ { limbs: $crate::internal::div::<$N, $BITS>(&self.limbs, &other.limbs) }
            }
        }

        impl std::cmp::Eq for $typ {
            fn eq(self, other: Self) -> bool {
                $crate::internal::eq::<$N, $BITS>(&self.limbs, &other.limbs)
            }
        }

        /// Integer ordering comparison (`>`, `>=`, `<`, `<=`).
        ///
        /// Compares values as integers over their limb representation.
        impl std::cmp::Ord for $typ {
            fn cmp(self, other: Self) -> std::cmp::Ordering {
                $crate::internal::cmp::<$N, $BITS>(&self.limbs, &other.limbs)
            }
        }

    }
}

/// Computes the quotient and remainder of a quadratic expression (unconstrained).
///
/// Evaluates `sum_i(product(lhs_terms[i]) * product(rhs_terms[i])) + sum(linear_terms) = q * 2^BITS + r`
/// and returns `(q, r)`.
///
/// # Parameters
/// - `lhs_terms`: Left-hand side terms for each product. Shape: `[NUM_PRODUCTS][LHS_N]`
/// - `lhs_flags`: If `true`, the corresponding lhs_term is negated
/// - `rhs_terms`: Right-hand side terms for each product. Shape: `[NUM_PRODUCTS][RHS_N]`
/// - `rhs_flags`: If `true`, the corresponding rhs_term is negated
/// - `linear_terms`: Terms to add to the sum. Shape: `[ADD_N]`
/// - `linear_flags`: If `true`, the corresponding linear_term is negated
///
/// # Safety
/// **UNCONSTRAINED**: This function generates no constraints. Use `evaluate_quadratic_expression`
/// to constrain the result, or use the returned values as witnesses that you constrain separately.
///
/// # Example
/// Computing `a * b + c`:
/// ```
/// // Safety: unconstrained witness computation
/// let (q, r) = unsafe {
///     compute_quadratic_expression(
///         [[a]],      // lhs_terms
///         [[false]],  // lhs_flags (not negated)
///         [[b]],      // rhs_terms
///         [[false]],  // rhs_flags
///         [c],        // linear_terms
///         [false],    // linear_flags
///     )
/// };
/// // r now contains (a * b + c) mod 2^BITS
/// ```
pub unconstrained fn compute_quadratic_expression<T: BigInt, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: [[T; LHS_N]; NUM_PRODUCTS],
    lhs_flags: [[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: [[T; RHS_N]; NUM_PRODUCTS],
    rhs_flags: [[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: [T; ADD_N],
    linear_flags: [bool; ADD_N],
) -> (T, T) {
    let (q_limbs, r_limbs) = crate::fns::expressions::__compute_quadratic_expression::<<T as BigInt>::N, <T as BigInt>::BITS, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        &crate::utils::map::map(
            &lhs_terms,
            |bns| crate::utils::map::map(bns, |bn: &T| bn.get_limbs()),
        ),
        &lhs_flags,
        &crate::utils::map::map(
            &rhs_terms,
            |bns| crate::utils::map::map(bns, |bn: &T| bn.get_limbs()),
        ),
        &rhs_flags,
        &crate::utils::map::map(&linear_terms, |bn: &T| bn.get_limbs()),
        &linear_flags,
    );
    (T::from_limbs_unsafe(q_limbs), T::from_limbs_unsafe(r_limbs))
}

/// Constrains a quadratic expression to equal zero modulo `2^BITS`.
///
/// This is the **recommended** way to constrain BigInt arithmetic for optimal performance.
/// Instead of using multiple constrained operations (`+`, `-`, `*`), compute results using
/// unconstrained functions (`__add`, `__mul`, etc.) and then constrain them with a single
/// call to this function.
///
/// # Expression Format
/// Constrains: `sum_i(product(lhs_terms[i]) * product(rhs_terms[i])) + sum(linear_terms) == 0 (mod 2^BITS)`
///
/// # Parameters
/// - `lhs_terms`: Left-hand side terms for each product. Shape: `[NUM_PRODUCTS][LHS_N]`
/// - `lhs_flags`: If `true`, the corresponding lhs_term is negated
/// - `rhs_terms`: Right-hand side terms for each product. Shape: `[NUM_PRODUCTS][RHS_N]`
/// - `rhs_flags`: If `true`, the corresponding rhs_term is negated
/// - `linear_terms`: Terms to add to the sum. Shape: `[ADD_N]`
/// - `linear_flags`: If `true`, the corresponding linear_term is negated
///
/// # Example: Constraining `a * b + c - result == 0`
/// ```
/// // First compute result unconstrainedly
/// // Safety: witness computation, constrained below
/// let result = unsafe { a.__mul(b).__add(c) };
///
/// // Then constrain: a * b + c - result == 0
/// evaluate_quadratic_expression(
///     [[a]],           // lhs: [a]
///     [[false]],       // not negated
///     [[b]],           // rhs: [b]
///     [[false]],       // not negated
///     [c, result],     // linear: c + (-result)
///     [false, true],   // c positive, result negated
/// );
/// ```
///
/// # Example: Constraining `(a + b) * c - d == 0`
/// ```
/// // Safety: witness computation
/// let d = unsafe { (a.__add(b)).__mul(c) };
///
/// // Constrain: (a + b) * c - d == 0
/// evaluate_quadratic_expression(
///     [[a, b]],        // lhs: (a + b)
///     [[false, false]],
///     [[c]],           // rhs: c
///     [[false]],
///     [d],             // linear: -d
///     [true],          // d is negated
/// );
/// ```
///
/// # Performance Note
/// This function generates far fewer constraints than equivalent sequences of `+`, `-`, `*`
/// operations. For complex expressions, the savings can be substantial.
///
/// # Panics
/// Fails if the expression does not equal zero modulo `2^BITS`.
pub fn evaluate_quadratic_expression<T: BigInt, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: [[T; LHS_N]; NUM_PRODUCTS],
    lhs_flags: [[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: [[T; RHS_N]; NUM_PRODUCTS],
    rhs_flags: [[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: [T; ADD_N],
    linear_flags: [bool; ADD_N],
) {
    crate::fns::expressions::evaluate_quadratic_expression::<<T as BigInt>::N, <T as BigInt>::BITS, LHS_N, RHS_N, NUM_PRODUCTS, ADD_N>(
        &crate::utils::map::map(
            &lhs_terms,
            |bns| crate::utils::map::map(bns, |bn: &T| bn.get_limbs()),
        ),
        &lhs_flags,
        &crate::utils::map::map(
            &rhs_terms,
            |bns| crate::utils::map::map(bns, |bn: &T| bn.get_limbs()),
        ),
        &rhs_flags,
        &crate::utils::map::map(&linear_terms, |bn: &T| bn.get_limbs()),
        &linear_flags,
    )
}

/// Converts a BigInt to a native circuit Field element.
///
/// # Requirements
/// - The BigInt value must be less than the circuit field modulus (Grumpkin: ~2^254)
/// - For N > 2, the value is validated to be less than the Grumpkin modulus
///
/// # Panics
/// - Fails range validation if the value is >= circuit field modulus
/// - Fails if limbs are not properly range-constrained
///
/// # Note
/// This is a constrained operation that validates the BigInt is representable as a Field.
/// For BigInts with `BITS > 253`, ensure your value is actually less than the circuit
/// field modulus before calling this.
pub fn to_field<T: BigInt>(bn: T) -> Field {
    let limbs = bn.get_limbs();
    limbs_to_field::<<T as BigInt>::N, <T as BigInt>::BITS>(&limbs)
}
