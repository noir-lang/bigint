# Specification

This document specifies the observable behaviour of the `BigInt` types in this library: the value each operation returns, its preconditions, and when it fails. It describes the code on `main`. It does not describe how the constraints are built, except where that affects behaviour.

Every pull request which changes behaviour must update this document in the same pull request. [Consistency review](#consistency-review) lists the known places where the code is inconsistent with itself or with its documentation.

## Conventions

- `N` is the number of limbs and `BITS` the bit width of a type. `TOP = BITS - 120 * (N - 1)` is the number of bits in the top limb.
- `p` is the modulus of the circuit field (BN254's scalar field, `p ≈ 2^253.6`). `Field` values are integers in `[0, p)`.
- `value(x)` is the integer represented by the limbs of `x`: `sum_i x.limbs[i] * 2^(120 * i)`.
- A value is **canonical** if limbs `0..N-2` are below `2^120` and the top limb is below `2^TOP`. Every canonical value is in `[0, 2^BITS)` and every integer in `[0, 2^BITS)` has exactly one canonical representation.
- An operation **range-checks** a value if it fails unless the value is canonical.
- An operation **fails** if no valid proof exists for it. For constrained code this is a constraint failure; most failures also abort execution with an assertion message. Unconstrained functions fail by aborting execution.
- **Unchecked values** are values which may not be canonical: circuit inputs (whose limbs are only known to be `u128`s), values returned from unconstrained functions, and values built with `from_limbs_unsafe` or `set_limb_unsafe`.

## Types

`#[derive_bigint(BITS)]` implements `BigInt` for a struct with a single field `limbs: [u128; N]`. It fails to compile unless:

- `N = ceil(BITS / 120)`,
- `N >= 2`, and
- `TOP <= 118`, i.e. `BITS % 120` is neither `0` nor `119`.

The library provides:

| Type    | `N` | `BITS` | `TOP` |
| ------- | --- | ------ | ----- |
| `U256`  | 3   | 256    | 16    |
| `U512`  | 5   | 512    | 32    |
| `U1024` | 9   | 1024   | 64    |
| `U2048` | 18  | 2048   | 8     |
| `U4096` | 35  | 4096   | 16    |
| `U8192` | 69  | 8192   | 32    |

Every shipped type has `BITS >= 254`, so `2^BITS > p`.

## Constructors and limb access

| Function | Result | Fails if |
| --- | --- | --- |
| `new()`, `zero()`, `Default::default()` | `0` | never |
| `one()` | `1` | never |
| `from_limbs(limbs)` | the value with these limbs | `limbs` is not canonical |
| `from_limbs_unsafe(limbs)` | the value with these limbs, unchecked | never |
| `get_limbs()` | the limbs | never |
| `get_limb(i)` | `limbs[i]` | `i >= N` |
| `set_limb(i, v)` | sets `limbs[i] = v` | `i >= N`, or `v >= 2^120` (`i < N - 1`) or `v >= 2^TOP` (`i = N - 1`) |
| `set_limb_unsafe(i, v)` | sets `limbs[i] = v`, unchecked | `i >= N` |
| `validate_in_range()` | nothing | the value is not canonical |
| `derive_from_seed(seed)`, `__derive_from_seed(seed)` | a pseudorandom canonical value | `seed` has 256 or more bytes |

`derive_from_seed` is a deterministic, public function of `seed`, built from Poseidon2. Its output should be close to uniform over `[0, 2^BITS)`. It is intended for testing, and must not be used where the seed is secret or guessable. The constrained and unconstrained versions return the same value.

## Conversions

| Function | Result | Fails if |
| --- | --- | --- |
| `From<Field>`: `T::from(x)` | `x` | `x >= 2^BITS` (only possible for `BITS <= 253`) |
| `to_field(a)` | `value(a)` as a `Field` | `a` is not canonical, or `value(a) >= p` |
| `from_be_bytes(bytes)`, `from_le_bytes(bytes)` | the integer encoded by the `(BITS + 7) / 8` bytes | the encoded integer is `>= 2^BITS` |
| `to_be_bytes(a)`, `to_le_bytes(a)` | the `(BITS + 7) / 8`-byte encoding of `value(a)` | a non-top limb of `a` is `>= 2^120`, or the top limb does not fit in its bytes |

`to_be_bytes` does not range-check the top limb to `TOP` bits, only to the bytes it occupies. For shipped types `BITS % 8 == 0`, so the two coincide. See [consistency review](#consistency-review), item 5.

## Comparisons

| Function | Result | Range-checks inputs |
| --- | --- | --- |
| `a == b`, `a != b` | `value(a) == value(b)` | yes |
| `a < b`, `a <= b`, `a > b`, `a >= b`, `cmp` | integer ordering of `value(a)` and `value(b)` | yes |
| `is_zero(a)` | `value(a) == 0` | no |
| `assert_is_not_zero(a)` | fails if `value(a) == 0` | no |
| `assert_is_not_equal(a, b)` | fails if `value(a) ≡ value(b) (mod p)` | no |

`is_zero` and `assert_is_not_zero` are correct for unchecked values, as a value whose limbs are all non-negative is zero only if every limb is zero.

`assert_is_not_equal` compares values via their encodings in `Field`. It is sound (it always fails if `value(a) == value(b)`), but when `BITS >= 254` it also fails for distinct values whose difference is a multiple of `p`. See [consistency review](#consistency-review), item 2.

## Arithmetic

All arithmetic is **wrapping**: results are reduced modulo `2^BITS`. Every result is canonical.

| Operation | Result | Fails if | Range-checks inputs |
| --- | --- | --- | --- |
| `a + b` | `(value(a) + value(b)) mod 2^BITS` | no valid witness exists (only possible for unchecked inputs) | no |
| `a - b` | `(value(a) - value(b)) mod 2^BITS` | no valid witness exists (only possible for unchecked inputs) | no |
| `a * b` | `(a * b) mod 2^BITS` | an input is not canonical, or `N > 65` (compile time) | yes |
| `a.sqr()` | `(a * a) mod 2^BITS` | as `*` | yes |
| `a.udiv_mod(b)` | `(floor(a / b), a mod b)` | `b == 0`, an input is not canonical, or `N > 65` (compile time) | yes |
| `a / b` | `floor(a / b)` | as `udiv_mod` | yes |
| `a.umod(b)` | `a mod b` | as `udiv_mod` | yes |

Division by zero fails with `attempt to divide by zero`. The circuit itself also rejects it, as it requires `remainder < divisor`.

For `+` and `-`, if the inputs are unchecked the result is still determined by `value(a)` and `value(b)`. Either the proof fails, or the result is the canonical representative of the sum or difference modulo `2^BITS`.

The compile-time failure for `N > 65` comes from the product bound described under [quadratic expressions](#quadratic-expressions). It affects `U8192`. See [consistency review](#consistency-review), item 1.

## Unconstrained functions

Functions prefixed with `__` generate no constraints. For canonical inputs they return the same values as their constrained counterparts. For non-canonical inputs their results are unspecified, and they may return non-canonical values.

| Function | Result | Fails if |
| --- | --- | --- |
| `__add(b)`, `__sub(b)`, `__mul(b)`, `__sqr()` | as `+`, `-`, `*`, `sqr` | never, for canonical inputs |
| `__udiv_mod(b)` | as `udiv_mod` | `b == 0` (`attempt to divide by zero`) |
| `__div(b)` | as `/` | `b == 0` (`attempt to divide by zero`) |
| `__pow(e)` | `a^e mod 2^BITS`, with `0^0 = 1` | never, for canonical inputs |
| `__eq(b)` | limb-wise equality | never |
| `__is_zero()` | `true` if every limb is zero | never |

`__eq` compares limbs, not values. It agrees with `==` for canonical inputs. For unchecked inputs `==` fails instead.

### Constrained functions in unconstrained code

When called from unconstrained code, `+`, `-`, `*`, `sqr`, `/`, `udiv_mod`, `umod` and `From<Field>` skip their checks and return the unconstrained result. All other functions perform their checks as assertions.

## Quadratic expressions

```rust
pub fn evaluate_quadratic_expression<T: BigInt, let LHS_N: u32, let RHS_N: u32, let NUM_PRODUCTS: u32, let ADD_N: u32>(
    lhs_terms: [[T; LHS_N]; NUM_PRODUCTS],
    lhs_flags: [[bool; LHS_N]; NUM_PRODUCTS],
    rhs_terms: [[T; RHS_N]; NUM_PRODUCTS],
    rhs_flags: [[bool; RHS_N]; NUM_PRODUCTS],
    linear_terms: [T; ADD_N],
    linear_flags: [bool; ADD_N],
)
```

Let `±x` be `-x` if the corresponding flag is `true` and `x` otherwise, and let

- `L_i = sum_j ±lhs_terms[i][j]`,
- `R_i = sum_k ±rhs_terms[i][k]`,
- `A = sum_l ±linear_terms[l]`, and
- `E = sum_i L_i * R_i + A`.

`evaluate_quadratic_expression` fails unless every term is canonical and

    E ≡ 0 (mod 2^BITS).

Because every term is range-checked, a relation such as `x * y - z ≡ 0` determines `z` uniquely as `(x * y) mod 2^BITS`.

Preconditions:

- **Size bound (compile time).** The parameters `(N, BITS, LHS_N, RHS_N, NUM_PRODUCTS)` must keep every limb of the product below `2^246`, assuming no negated terms. Expressions which may not satisfy this fail to compile with `product limbs may exceed 2^246 at limb k`. As a guide, keep `NUM_PRODUCTS * LHS_N * RHS_N` well below 64. For `N > 65` every expression is rejected, including `NUM_PRODUCTS = LHS_N = RHS_N = 1`.
- **Completeness.** If the size bound holds and `E ≡ 0 (mod 2^BITS)`, a proof can be generated. The size bound does not account for negated terms, which add `2^(BITS + 1)` per term internally. An expression with many negated terms may therefore satisfy the size bound and still be impossible to prove. See [consistency review](#consistency-review), item 6.

```rust
pub unconstrained fn compute_quadratic_expression<T: BigInt, ...>(/* as above */) -> (T, T)
```

Returns `(q, r)`, where `r = E mod 2^BITS` is canonical. `q` is the quotient `floor(E' / 2^BITS)`, where `E'` is `E` with every negated term `x` replaced by `2^(BITS + 1) - x`. `q` is not range-checked and may not be a valid value of `T`. See [consistency review](#consistency-review), item 7.

## Consistency review

Known inconsistencies on `main`, and the open pull requests which address them.

1. **`U8192` cannot do arithmetic.** `*`, `sqr`, `/`, `umod`, `udiv_mod` and `evaluate_quadratic_expression` all fail to compile for types with `N > 65`, which includes the shipped `U8192`. This is far stricter than for every other shipped type. Addressed by #18.
2. **`assert_is_not_equal` has a stricter precondition than `!=`.** For every shipped type (`BITS >= 254`) it fails for distinct values congruent modulo `p`, whereas `assert(a != b)` does not. An honest prover with such values cannot produce a proof. Not addressed.
3. **`+` and `-` do not range-check their inputs; every other binary operation does.** The results are still correct modulo `2^BITS` (see [arithmetic](#arithmetic)), so this is not unsound, but the behaviour on unchecked inputs differs: `a + b` succeeds where `a == b` or `a * b` fails. #20 documents the behaviour.
4. **Unconstrained `From<Field>` does not check the width.** For a custom type with `BITS <= 253`, the constrained conversion fails for `x >= 2^BITS`, but the unconstrained one returns non-canonical limbs. Addressed by #16.
5. **`to_be_bytes` and `to_le_bytes` only range-check the top limb to a byte boundary.** For a custom type with `BITS % 8 != 0`, they can serialize a non-canonical value into bytes which `from_be_bytes` rejects. Addressed by #19.
6. **The expression size bound ignores negated terms.** The compile-time check bounds the product limbs for unnegated terms only, so it may accept expressions which an honest prover cannot prove. The code comments describe this, but no test covers it. Not addressed.
7. **`compute_quadratic_expression` returns a quotient which includes internal offsets.** When any flag is set, `q` is not the quotient of `E` by `2^BITS`, and it may not be a valid value of `T`. #8 changes the function to return the value of the expression instead.
8. **Documentation drift.** These comments disagree with the code:
   - The `BigInt` trait documentation says negation wraps; negation has been removed. It says single-limb types "may produce incorrect results"; `derive_bigint` rejects them at compile time.
   - The doc comments of `compute_quadratic_expression` and `evaluate_quadratic_expression` describe `product(lhs_terms[i])`. The code computes a sum, as the README says.
   - `derive_from_seed` says it derives `BITS * 2` bits and reduces modulo `MOD`. It truncates hash output to `BITS` bits.
   - The `add` and `sub` "limitations" sections in `src/fns/constrained_ops.nr` describe spurious witnesses when `lhs + rhs + MOD < 2^BITS`. As `MOD = 2^BITS` for every type, this cannot happen.
   - `compute_linear_expressions` refers to a test, `test_evaluate_quadratic_expression_limb_overflow`, which does not exist.
   - The 256-byte limit on `derive_from_seed` seeds is not documented on the trait.

   #20 fixes some of these.
