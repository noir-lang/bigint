# bigint

> [!WARNING]
> **This library is experimental software. It has not been audited and is not guaranteed to be secure. Expect bugs!**
>
> bigint is provided "as is", without warranty of any kind (see [LICENSE](LICENSE)). Bugs in this library can lead to under-constrained circuits, allowing invalid proofs to be accepted. Do not rely on it to protect real assets or sensitive data without your own independent review.
>
> If you find a vulnerability, please **do not** open a public issue. Report it privately via [GitHub's "Report a vulnerability"](https://github.com/noir-lang/bigint/security/advisories/new) form instead.

Efficient constrained and unconstrained arithmetic over large unsigned integers (`U256`, `U512`, ...) for [Noir](https://noir-lang.org).

The Noir standard library provides unsigned integers up to 128 bits and a native `Field` of ~254 bits. This library provides fixed-width unsigned integers of 256 bits and above.

> [!NOTE]
> This library is derived from [noir-bignum](https://github.com/noir-lang/noir-bignum), with all finite-field functionality removed. All arithmetic is **checked**: overflow and underflow cause constraint failures rather than wrapping.

## Noir version compatibility

This library is tested with all stable releases since 1.0.0 as well as nightly.

Refer to [Noir's docs](https://noir-lang.org/docs/getting_started/noir_installation) for installation steps.

## Installation

In your `Nargo.toml` file, add the version of this library you would like to install under `[dependencies]`:

```toml
[dependencies]
bigint = { tag = "vX.Y.Z", git = "https://github.com/noir-lang/bigint" }
```

## Quick example

```rust
use bigint::U256;

fn main(a: U256, b: U256, expected: U256) {
    assert(a + b == expected);
}
```

## Types

The following types are provided (see [`src/types/`](./src/types/)):

| Type    | Limbs (`N`) | `BITS` |
| ------- | ----------- | ------ |
| `U256`  | 3           | 256    |
| `U512`  | 5           | 512    |
| `U1024` | 9           | 1024   |
| `U2048` | 18          | 2048   |
| `U4096` | 35          | 4096   |
| `U8192` | 69          | 8192   |

Values are stored as arrays of `N` little-endian 120-bit limbs held in `u128`s, i.e. `[a, b, c]` represents $a + b \cdot 2^{120} + c \cdot 2^{240}$. The headroom left in each `u128` allows intermediate sums and products to be computed without overflow.

A `UX` holds values in $[0, 2^X)$: the top limb is range-checked to `X - 120 * (N - 1)` bits, so every value has exactly one limb representation. Every constructor (other than the `*_unsafe` ones, see below) and every operation range-checks its result.

Values which bypass the constructors are not range-checked until they are used: circuit inputs (e.g. `fn main(a: U256)`, whose limbs are only checked to be `u128`s), values returned from unconstrained functions, and values built with `from_limbs_unsafe` or `set_limb_unsafe`. In circuits, no operation returns an incorrect result for such values: `+` and `-` do not range-check their inputs, but return the correct result or fail, and the other operations (`*`, `/`, `%`, `div_rem`, `==`, comparisons, conversions, `evaluate_quadratic_expression` and the `MulDiv` methods) range-check their inputs. In unconstrained code, no operation returns an incorrect result either: `+` and `__add` return the correct result or fail, and `-` and the other `__` functions (`__sub`, `__mul`, `__div`, `__div_rem`, `__pow`, `__eq`), as well as `compute_quadratic_expression` and the `MulDiv` methods, range-check their inputs as the operations above do, failing with `BigInt is not in range`. Call `validate_in_range` to check such a value explicitly. See [SPEC.md](SPEC.md) for the behaviour of each operation.

### Defining your own width

A new width can be created with the `derive_bigint` macro, passing the bit width:

```rust
use bigint::{BigInt, derive_bigint};

// An unsigned 320-bit integer
#[derive_bigint(320)]
pub struct U320 {
    limbs: [u128; 3],
}
```

The `limbs` array must have `N = ceil(BITS / 120)` elements. Between 2 and 129 limbs are supported (i.e. widths from 121 to 15,478 bits), and the top limb can hold at most 118 bits, so widths where `BITS % 120` is `0` or `119` are not supported. These are all checked at compile time.

## Methods

### Constrained arithmetic

The overloaded operators are constrained:

- `+`, `-`: checked addition and subtraction, which fail if the result overflows $2^X$ or is negative
- `*`: checked multiplication, which fails if the product overflows $2^X$
- `/`, `%`: integer division (rounding down) and remainder, which fail if the divisor is zero
- `==`: equality
- `<`, `<=`, `>`, `>=`: integer comparison

Additional constrained methods:

- `div_rem`: integer division with remainder, i.e. `(a / b, a % b)`. Computing both together is cheaper than computing `/` and `%` separately

### Unconstrained arithmetic

Every arithmetic operation has an unconstrained counterpart prefixed with `__`: `__add`, `__sub`, `__mul`, `__div`, `__div_rem`, `__pow`, `__eq`, `__is_zero`.

These generate no constraints. Their results must be constrained, ideally with `evaluate_quadratic_expression` (see below).

### Multiply-divide

`U256` implements the `MulDiv` trait from [`mul_div`](https://github.com/noir-lang/mul-div), re-exported as `bigint::MulDiv`. It computes `a * b / d` with the full 512-bit product, so `a * b` itself never overflows:

- `a.mul_div_floor(b, d)`: `floor(a * b / d)`
- `a.mul_div_ceil(b, d)`: `ceil(a * b / d)`
- `a.mul_div_rem(b, d)`: floor quotient and remainder `(q, r)`

They fail if `d` is zero or the result does not fit in 256 bits.

```rust
use bigint::{BigInt, MulDiv, U256};

let max = U256::from_le_bytes([255; 32]);
assert_eq(max.mul_div_floor(max, max), max);
```

### Constructors and limb access

- `zero`, `one`
- `from_limbs` (range-checks the limbs), `from_limbs_unsafe` (does not; the result must be range-checked with `validate_in_range` before use)
- `get_limbs`, `get_limb(idx)`
- `set_limb(idx, value)` (range-checks the new value), `set_limb_unsafe(idx, value)` (does not)

### Conversions

- `From<Field>`: `U256::from(x)`, failing if the value does not fit
- `From<u8>`, `From<u16>`, `From<u32>`, `From<u64>`, `From<u128>`: from native integers, e.g. `U256::from(x as u64)`. `From<u128>` fails if the value does not fit, for types narrower than 128 bits
- Widening conversions between the pre-defined types: `From<U256> for U512`, `From<U256> for U1024`, ..., `From<U4096> for U8192`. These zero-extend the value, e.g. `let b: U512 = a.into();`
- `to_field(x)`: converts to a `Field`, failing if the value does not fit
- `from_be_bytes`, `from_le_bytes`, `to_be_bytes`, `to_le_bytes`: byte conversions using `(BITS + 7) / 8` bytes

### Assertions and range checks

- `is_zero`: zero check, cheaper than `== zero()`
- `assert_is_not_equal(a, b)`: a free function, like `to_field`. Asserts `a != b`, and is cheaper than `assert(a != b)`
- `validate_in_range`: each limb is at most 120 bits and the value is less than $2^X$

### `evaluate_quadratic_expression`

Every constrained operator range-checks its own result and checks its own relation, which makes chaining several of them expensive. A cheaper approach is to compute the result with unconstrained code and then constrain the whole relation at once:

```rust
use bigint::{compute_quadratic_expression, evaluate_quadratic_expression, U256};

// Check that (x1 * x2) + x3 == expected
fn main(x1: U256, x2: U256, x3: U256, expected: U256) {
    // Safety: the result is constrained below
    let res = unsafe { compute_quadratic_expression([[x1]], [[false]], [[x2]], [[false]], [x3], [false]) };

    // Constrain (x1 * x2) + x3 - res == 0
    evaluate_quadratic_expression(
        [[x1]],
        [[false]],
        [[x2]],
        [[false]],
        [x3, res],
        [false, true],
    );

    assert(res == expected);
}
```

The full interface is:

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

This constrains

$$\sum_{i=0}^{\text{NUM\_PRODUCTS}-1} \left(\sum_j \pm \text{lhs}_{i,j}\right)\left(\sum_k \pm \text{rhs}_{i,k}\right) + \sum_l \pm \text{linear}_l = 0$$

over the integers, where a `true` flag negates the corresponding term. As every term is range-checked to $X$ bits, a relation such as `x * y - z = 0` constrains `z` to be exactly `x * y`, and fails if the product overflows.

Only the terms are range-checked: intermediate values within the expression may exceed $2^X$ or be negative, as long as the relation holds. For example, with `a = 2^128` and `d = 2^128 - 1`, the relation `a * a - a * d - r = 0` holds for `r = 2^128` in `U256`, even though `a * a = 2^256` does not fit in a `U256` (so computing `a * a - a * d` with the checked operators fails). This makes expressions useful for relations which cannot be computed step by step, such as checking `a * b == c * d` when the products exceed $2^X$.

Combining several operations into one expression is also cheaper than using the operators, as only the terms are range-checked and the relation is checked once. For example, `a * b + c * d` costs 55 gates for `U256` (952 for `U2048`) on top of range-checking the inputs, compared to 90 (1,190) using `*` and `+`, when the result is computed in a single unconstrained call (see below). For a single product, `*` is cheaper.

The combination of `NUM_PRODUCTS`, `LHS_N` and `RHS_N` must be small enough that intermediate product limbs do not exceed $2^{246}$. This is enforced, and expressions which could overflow are rejected. As a rough guide, keep `NUM_PRODUCTS * LHS_N * RHS_N` well below 64.

`compute_quadratic_expression` is the unconstrained counterpart: it returns the value of an expression, failing if the value is negative or overflows $2^X$, or if a term is not in range.

Each call to an unconstrained function from constrained code range-checks the values it returns, so compute a witness in a single call (e.g. with `compute_quadratic_expression`, or your own `unconstrained fn`) rather than by chaining `__` methods. For `a * b + c * d`, chaining (`a.__mul(&b).__add(&c.__mul(&d))`) makes three calls and costs about 40 more gates than a single call for `U256`, which removes most of the saving over the operators.

Each call to an unconstrained function from constrained code range-checks the values it returns, so compute a witness in a single call (e.g. with `compute_quadratic_expression`, or your own `unconstrained fn`) rather than by chaining `__` methods. For example, `a.__mul(&b).__add(&c.__mul(&d))` makes three calls, and so range-checks two intermediate values which a single call would not.

## Benchmarks

Gate counts and Brillig bytecode sizes for the exported benchmark functions in [`src/benchmarks.nr`](./src/benchmarks.nr) are tracked in CI. To generate them locally:

```bash
nargo export
BACKEND=/path/to/bb ./scripts/build-gates-report.sh
```

## License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
