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
- **Unchecked values** are values which may not be canonical: circuit inputs (whose limbs are only known to be `u128`s), values returned from unconstrained functions, and values built with `from_limbs_unsafe` or `set_limb_unsafe`. As limbs have type `u128`, every limb of every value is below `2^128`. A non-canonical value may encode an integer in `[0, 2^BITS)` with different limbs (e.g. `[2^120, 0, 0]` for `2^120`), or an integer `>= 2^BITS`. [Canonical inputs](#canonical-inputs) describes how each function handles them.

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
| `zero()`, `Default::default()` | `0` | never |
| `one()` | `1` | never |
| `from_limbs(limbs)` | the value with these limbs | `limbs` is not canonical |
| `from_limbs_unsafe(limbs)` | the value with these limbs, unchecked | never |
| `get_limbs()` | the limbs | never |
| `get_limb(i)` | `limbs[i]` | `i >= N` |
| `set_limb(i, v)` | sets `limbs[i] = v` | `i >= N`, or `v >= 2^120` (`i < N - 1`) or `v >= 2^TOP` (`i = N - 1`) |
| `set_limb_unsafe(i, v)` | sets `limbs[i] = v`, unchecked | `i >= N` |
| `validate_in_range()` | nothing | the value is not canonical |

## Conversions

| Function | Result | Fails if |
| --- | --- | --- |
| `From<Field>`: `T::from(x)` | `x` | `x >= 2^BITS` (only possible for `BITS <= 253`). In unconstrained execution this fails with `attempt to convert a Field which does not fit` |
| `From<u8>`, `From<u16>`, `From<u32>`, `From<u64>`: `T::from(x)` | `x` | never |
| `From<u128>`: `T::from(x)` | `x` | as `From<Field>`: `x >= 2^BITS` (only possible for `BITS < 128`) |
| `From<A> for B`, `a.into()`, for pre-defined types `A` narrower than `B` | `value(a)` | `a` is not canonical |
| `to_field(a)` | `value(a)` as a `Field` | `a` is not canonical, or `value(a) >= p` |
| `from_be_bytes(bytes)`, `from_le_bytes(bytes)` | the integer encoded by the `(BITS + 7) / 8` bytes | the encoded integer is `>= 2^BITS` |
| `to_be_bytes(a)`, `to_le_bytes(a)` | the `(BITS + 7) / 8`-byte encoding of `value(a)` | `a` is not canonical |

## Comparisons

| Function | Result | Range-checks inputs |
| --- | --- | --- |
| `a == b`, `a != b` | `value(a) == value(b)` | yes |
| `a < b`, `a <= b`, `a > b`, `a >= b`, `cmp` | integer ordering of `value(a)` and `value(b)` | yes |
| `is_zero(a)` | `value(a) == 0` | no |
| `assert_is_not_equal(a, b)` | fails if `value(a) ≡ value(b) (mod p)` | no |

`is_zero` is correct for unchecked values, as a value whose limbs are all non-negative is zero only if every limb is zero.

`assert_is_not_equal` compares values via their encodings in `Field`. It is sound (it always fails if `value(a) == value(b)`), but when `BITS >= 254` it also fails for distinct values whose difference is a multiple of `p`. See [consistency review](#consistency-review), item 2.

## Arithmetic

All arithmetic is **wrapping**: results are reduced modulo `2^BITS`. Every result is canonical.

| Operation | Result | Fails if | Range-checks inputs |
| --- | --- | --- | --- |
| `a + b` | `(value(a) + value(b)) mod 2^BITS` | no valid witness exists (only possible for unchecked inputs) | no |
| `a - b` | `(value(a) - value(b)) mod 2^BITS` | no valid witness exists (only possible for unchecked inputs) | no |
| `a * b` | `(a * b) mod 2^BITS` | an input is not canonical, or `N > 65` (compile time) | yes |
| `a.div_rem(b)` | `(floor(a / b), a mod b)` | `b == 0`, an input is not canonical, or `N > 65` (compile time) | yes |
| `a / b` | `floor(a / b)` | as `div_rem` | yes |
| `a % b` | `a mod b` | as `div_rem` | yes |

Division by zero fails with `attempt to divide by zero`. The circuit itself also rejects it, as it requires `remainder < divisor`.

For unchecked inputs, `+` and `-` never return an incorrect result: either the proof fails, or the result is the canonical representative of the sum or difference of `value(a)` and `value(b)` modulo `2^BITS`. They may fail for some non-canonical inputs even when the result exists, e.g. `[2^120, 0, 0] - [0, 1, 0]`.

The compile-time failure for `N > 65` comes from the product bound described under [quadratic expressions](#quadratic-expressions). It affects `U8192`. See [consistency review](#consistency-review), item 1.

## Unconstrained functions

Functions prefixed with `__` generate no constraints. For canonical inputs they return the same values as their constrained counterparts. [Canonical inputs](#canonical-inputs) describes their results for non-canonical inputs.

| Function | Result | Fails if |
| --- | --- | --- |
| `__add(b)`, `__sub(b)`, `__mul(b)` | as `+`, `-`, `*` | never, for canonical inputs |
| `__div_rem(b)` | as `div_rem` | `b == 0` (`attempt to divide by zero`) |
| `__div(b)` | as `/` | `b == 0` (`attempt to divide by zero`) |
| `__pow(e)` | `a^e mod 2^BITS`, with `0^0 = 1` | never, for canonical inputs |
| `__eq(b)` | limb-wise equality | never |
| `__is_zero()` | `true` if every limb is zero | never |

`__eq` compares limbs, not values. It agrees with `==` for canonical inputs. For unchecked inputs `==` fails instead.

### Constrained functions in unconstrained code

When called from unconstrained code, `+`, `-`, `*`, `/`, `%` and `div_rem` skip their checks and return the unconstrained result. All other functions perform their checks as assertions. The results agree with constrained execution for canonical inputs, but not for unchecked inputs: see [canonical inputs](#canonical-inputs).

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
- **Completeness.** If the size bound holds and `E ≡ 0 (mod 2^BITS)`, a proof can be generated. The size bound does not account for negated terms, which add `2^(BITS + 1)` per term internally. An expression with many negated terms may therefore satisfy the size bound and still be impossible to prove. See [consistency review](#consistency-review), item 4.

```rust
pub unconstrained fn compute_quadratic_expression<T: BigInt, ...>(/* as above */) -> (T, T)
```

Returns `(q, r)`, where `r = E mod 2^BITS` is canonical. `q` is the quotient `floor(E' / 2^BITS)`, where `E'` is `E` with every negated term `x` replaced by `2^(BITS + 1) - x`. `q` is not range-checked and may not be a valid value of `T`. See [consistency review](#consistency-review), item 5.

## Internal functions

These functions are not part of the public API, but other parts of the library, its tests or its benchmarks rely on their behaviour.

### `derive_from_seed`

```rust
pub fn derive_from_seed<let N: u32, let BITS: u32, let SeedBytes: u32>(seed: [u8; SeedBytes]) -> [u128; N]
```

In `src/fns/constrained_ops.nr`. Returns the canonical limbs of a pseudorandom value in `[0, 2^BITS)`, which is a fixed function of `seed`:

1. The seed bytes, followed by one byte holding `SeedBytes`, are packed big-endian into `Field`s of 31 bytes each. The length byte separates seeds which differ only in leading zero bytes.
2. The packed `Field`s are hashed with Poseidon2 to a single `Field` `h`.
3. For `i` in `0..ceil(N / 2)`, the low 240 bits of `Poseidon2([h, i])` give two 120-bit limbs, the lower bits first.
4. The first `N - 1` limbs are used as they are. The top limb is truncated to its low `TOP` bits.

It fails if `SeedBytes >= 256`.

Every step is constrained: the hash uses the Poseidon2 permutation, `Field`s are split into 128-bit halves with `std::field::bn254::decompose` (which constrains the decomposition to be canonical), and the remaining bit splits are range-checked and recomposed. So a prover cannot choose the output for a given seed. In unconstrained execution the function returns the same value.

The output is close to, but not exactly, uniform: the low 240 bits of a uniform `Field` are biased by a relative factor of up to about `2^-13.6`, as `p` is not a power of two. It is intended for testing. As the output is publicly computable from the seed, it must not be used where the seed is secret or guessable, and if the seed is a private input the prover can choose the output by choosing the seed.

## Canonical inputs

Every function falls into one of four classes for unchecked inputs:

- **Checks**: the function fails unless its inputs are canonical.
- **Correct for any limbs**: the function returns the correct result for the integer values of its inputs, whatever their limbs. It fails only if the correct result is out of range.
- **Never incorrect**: for non-canonical inputs the function returns the correct result or fails. It may fail even if the correct result is in range.
- **Requires but does not check**: the function is only specified for canonical inputs. For other inputs it may return a wrong or non-canonical result without failing.

A function in the last class may return a wrong or non-canonical result. That is acceptable only where the result is constrained afterwards, as for witness hints. It is not acceptable for code whose result is used as is, e.g. unconstrained programs.

| Function | Constrained execution | Unconstrained execution |
| --- | --- | --- |
| `+`, `-` | never incorrect | requires but does not check |
| `*` | checks | requires but does not check |
| `/`, `%`, `div_rem` | checks | requires but does not check |
| `==`, `!=`, `<`, `<=`, `>`, `>=`, `cmp` | checks | checks |
| `is_zero` | correct for any limbs | correct for any limbs |
| `assert_is_not_equal` | correct for any limbs (compares modulo `p`) | correct for any limbs (compares modulo `p`) |
| `to_field` | checks | checks |
| `From<A> for B` (widening) | checks | checks |
| `to_be_bytes`, `to_le_bytes` | checks | checks |
| `evaluate_quadratic_expression` | checks | checks |
| `set_limb` | checks the new limb only | checks the new limb only |
| `__add`, `__sub`, `__mul`, `__pow`, `__div`, `__div_rem`, `compute_quadratic_expression` | — | requires but does not check |
| `__eq` | — | requires but does not check (compares limbs, not values) |
| `__is_zero` | — | correct for any limbs |

Observed results on `main` for `U256`, with `a = [2^120, 0, 0]` (`2^120` with non-canonical limbs) and `b = [0, 0, 2^17]` (`2^257`):

| Expression | Constrained | Unconstrained |
| --- | --- | --- |
| `a + 1` | `[1, 1, 0]` (correct) | — |
| `b + 0` | fails | `[0, 0, 2^16]`, i.e. `2^256`: not a valid `U256` (correct: `0`) |
| `a - [0, 1, 0]` | fails (correct: `0`) | `[0, 0, 0]` (correct) |
| `a * 1` | fails | `[0, 1, 0]` (correct) |
| `c * c`, with `c = [2^127, 0, 0]` | fails | a canonical but wrong value, `2^254 mod p` (correct: `2^254`) |
| `a / 1` | fails | `[2^120 - 1, 0, 0]`: wrong (correct: `2^120`) |
| `b / 1` | fails | `[0, 0, 2^17]`: not a valid `U256` |
| `a == [0, 1, 0]` | fails | fails |
| `a.__eq([0, 1, 0])` | — | `false`, although the values are equal |
| `a.assert_is_not_equal([0, 1, 0])` | fails (the values are equal) | — |

So in constrained execution no function returns a wrong result for unchecked inputs. In unconstrained execution, the same operator can return a wrong result where constrained execution fails. See [consistency review](#consistency-review), item 3.

## Consistency review

Known inconsistencies on `main`, and the open pull requests which address them.

1. **`U8192` cannot do arithmetic.** `*`, `/`, `%`, `div_rem` and `evaluate_quadratic_expression` all fail to compile for types with `N > 65`, which includes the shipped `U8192`. This is far stricter than for every other shipped type. Addressed by #18.
2. **`assert_is_not_equal` has a stricter precondition than `!=`.** For every shipped type (`BITS >= 254`) it fails for distinct values congruent modulo `p`, whereas `assert(a != b)` does not. An honest prover with such values cannot produce a proof. Not addressed.
3. **Canonical-input handling differs between functions and between execution modes** (see [canonical inputs](#canonical-inputs)):
   - In unconstrained execution, `+`, `-`, `*`, `/`, `%`, `div_rem` and the `__` functions require canonical inputs but do not check them, and can return wrong or non-canonical results (e.g. `[2^120, 0, 0] / 1` returns `2^120 - 1`, and `[2^127, 0, 0]^2` returns `2^254 mod p`). In constrained execution the same operators either check or never return an incorrect result. `==` and the comparisons check in both modes. Not addressed.
   - In constrained execution, `+` and `-` do not check their inputs, while every other binary operation does. They never return an incorrect result, but `a + b` may succeed where `a == b` or `a * b` fails, and may also fail for non-canonical inputs whose result exists. The README documents this.
   - `__eq` compares limbs, so it returns `false` for different encodings of the same value, where `==` fails. Not addressed.
4. **The expression size bound ignores negated terms.** The compile-time check bounds the product limbs for unnegated terms only, so it may accept expressions which an honest prover cannot prove. The code comments describe this, but no test covers it. Not addressed.
5. **`compute_quadratic_expression` returns a quotient which includes internal offsets.** When any flag is set, `q` is not the quotient of `E` by `2^BITS`, and it may not be a valid value of `T`. #8 changes the function to return the value of the expression instead.
6. **Documentation drift.** These comments disagree with the code:
   - The `BigInt` trait documentation says negation wraps; negation has been removed. It says single-limb types "may produce incorrect results"; `derive_bigint` rejects them at compile time.
   - The `add` and `sub` "limitations" sections in `src/fns/constrained_ops.nr` describe spurious witnesses when `lhs + rhs + MOD < 2^BITS`. As `MOD = 2^BITS` for every type, this cannot happen.
   - `compute_linear_expressions` refers to a test, `test_evaluate_quadratic_expression_limb_overflow`, which does not exist.
