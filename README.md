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
> This library is derived from [noir-bignum](https://github.com/noir-lang/noir-bignum), with all finite-field functionality removed. Arithmetic is currently **wrapping** (i.e. performed modulo `2^BITS`). The goal of this library is to provide **checked** arithmetic, where overflow and underflow cause constraint failures. Until then, treat all operators as wrapping.

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
use bigint::{BigInt, U256};

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

The `limbs` array must have `N = ceil(BITS / 120)` elements. At least two limbs are required, and the top limb can hold at most 118 bits, so widths where `BITS % 120` is `0` or `119` are not supported. These are all checked at compile time.

At least two limbs are required. Single-limb types are not supported.

## Methods

### Constrained arithmetic

The overloaded operators are constrained:

- `+`, `-`, `*`: arithmetic modulo $2^X$ (wrapping)
- `/`, `%`: integer division (rounding down) and remainder, which fail if the divisor is zero
- `==`: equality
- `<`, `<=`, `>`, `>=`: integer comparison

Additional constrained methods:

- `div_rem`: integer division with remainder, i.e. `(a / b, a % b)`. Computing both together is cheaper than computing `/` and `%` separately

### Unconstrained arithmetic

Every arithmetic operation has an unconstrained counterpart prefixed with `__`: `__add`, `__sub`, `__mul`, `__div`, `__div_rem`, `__pow`, `__eq`, `__is_zero`.

These generate no constraints. Their results must be constrained, ideally with `evaluate_quadratic_expression` (see below).

### Constructors and limb access

- `zero`, `one`
- `from_limbs` (range-checks the limbs), `from_limbs_unsafe` (does not; the result must be range-checked with `validate_in_range` before use)
- `get_limbs`, `get_limb(idx)`
- `set_limb(idx, value)` (range-checks the new value), `set_limb_unsafe(idx, value)` (does not)
- `derive_from_seed`, `__derive_from_seed`: deterministically derive a value from a byte seed. Not cryptographically secure; intended for testing.

### Conversions

- `From<Field>`: `U256::from(x)`
- `to_field(x)`: converts to a `Field`, failing if the value does not fit
- `from_be_bytes`, `from_le_bytes`, `to_be_bytes`, `to_le_bytes`: byte conversions using `(BITS + 7) / 8` bytes

### Assertions and range checks

- `is_zero`: zero check, cheaper than `== zero()`
- `assert_is_not_equal`: cheaper than `assert(a != b)`
- `validate_in_range`: each limb is at most 120 bits and the value is less than $2^X$

### `evaluate_quadratic_expression`

Every constrained operator performs its own reduction and range checks, which makes chaining several of them expensive. A cheaper approach is to compute the result with unconstrained functions and then constrain the whole relation at once:

```rust
use bigint::{BigInt, U256};
use bigint::evaluate_quadratic_expression;

// Check that (x1 * x2) + x3 == expected (mod 2^256)
fn main(x1: U256, x2: U256, x3: U256, expected: U256) {
    // Safety: the result is constrained below
    let res = unsafe { x1.__mul(&x2).__add(&x3) };

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

$$\sum_{i=0}^{\text{NUM\_PRODUCTS}-1} \left(\sum_j \pm \text{lhs}_{i,j}\right)\left(\sum_k \pm \text{rhs}_{i,k}\right) + \sum_l \pm \text{linear}_l \equiv 0 \pmod{2^X}$$

where a `true` flag negates the corresponding term.

The combination of `NUM_PRODUCTS`, `LHS_N` and `RHS_N` must be small enough that intermediate product limbs do not exceed $2^{246}$. This is enforced, and expressions which could overflow are rejected. As a rough guide, keep `NUM_PRODUCTS * LHS_N * RHS_N` well below 64.

`compute_quadratic_expression` is the unconstrained counterpart. It returns the quotient and remainder of such an expression.

## Benchmarks

Gate counts and Brillig bytecode sizes for the exported benchmark functions in [`src/benchmarks.nr`](./src/benchmarks.nr) are tracked in CI. To generate them locally:

```bash
nargo export
BACKEND=/path/to/bb ./scripts/build-gates-report.sh
```

## License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
