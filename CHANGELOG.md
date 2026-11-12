# Changelog

## 0.1.0-rc.1 (2026-11-12)


### ⚠ BREAKING CHANGES

* `assert_is_not_equal` range-checks its inputs, so it fails for non-canonical inputs, as `==` and `!=` do.
* `+`, `-`, `__add` and `__sub` fail on overflow and underflow instead of wrapping.
* `+`, `-`, `__add` and `__sub` fail on overflow and underflow instead of wrapping.
* `+`, `-`, `__add` and `__sub` fail on overflow and underflow instead of wrapping.
* remove `derive_from_seed` from the public API ([#28](https://github.com/noir-lang/bigint/issues/28))
* `BigInt::num_limbs`, `BigInt::new`, `BigInt::sqr`, `BigInt::__sqr` and the corresponding `internal` functions are removed.
* `udiv_mod` and `__udiv_mod` are renamed to `div_rem` and `__div_rem`, and `umod(&b)` is replaced by `% b`.
* `udiv_mod` and `__udiv_mod` are renamed to `div_rem` and `__div_rem`, and `umod(&b)` is replaced by `% b`.
* `derive_bigint(N, BITS)` is now `derive_bigint(BITS)`.
* `BigInt` no longer requires or implements `Neg`, and `__neg` is removed.
* `BigInt::modulus_bits()` and `conditional_select` are removed.
* the `U384` and `U768` types are removed.
* `BigIntParams`, `BigIntParams::new` and `BigInt::params()` are removed. `derive_bigint` takes only `N` and `MOD_BITS`, and rejects values outside `(N - 1) * 120 < MOD_BITS < N * 120` at compile time.

### Features

* Add conversions from native integers and between widths ([#17](https://github.com/noir-lang/bigint/issues/17)) ([94a5054](https://github.com/noir-lang/bigint/commit/94a505410e22f5b7bb4111b852c455903a1efcbd))
* Derive the modulus from MOD_BITS and remove BigIntParams ([aac12db](https://github.com/noir-lang/bigint/commit/aac12db3cba2debd605e9f80e3314dbb99d1c24e))
* Implement mul_div's MulDiv trait for U256 ([#35](https://github.com/noir-lang/bigint/issues/35)) ([05702fd](https://github.com/noir-lang/bigint/commit/05702fd955d31b6c6f287db23c2e338acf9c5e20))
* Make `*` and `evaluate_quadratic_expression` checked ([#8](https://github.com/noir-lang/bigint/issues/8)) ([1f83ac4](https://github.com/noir-lang/bigint/commit/1f83ac4e07047b5209504d164b93983eaa976376))
* Make `+` and `-` checked ([#7](https://github.com/noir-lang/bigint/issues/7)) ([1456cf6](https://github.com/noir-lang/bigint/commit/1456cf69246d970976d5ca377d8f4d8966ed257a))
* Remove U384 and U768 ([233ab37](https://github.com/noir-lang/bigint/commit/233ab3746e837894f5166417aed262866f0eace8))
* Rename `udiv_mod` to `div_rem` and implement `%` ([#13](https://github.com/noir-lang/bigint/issues/13)) ([ae69cff](https://github.com/noir-lang/bigint/commit/ae69cff8e47052b1f0766409b84cd6ad6824cc4d))
* Use exact-width types with a unique representation per value ([#2](https://github.com/noir-lang/bigint/issues/2)) ([9124512](https://github.com/noir-lang/bigint/commit/912451215ccd3dde9817230a3f2417c8d920f0b1))


### Bug Fixes

* Check inputs of unconstrained operations which require canonical values ([#32](https://github.com/noir-lang/bigint/issues/32)) ([5621420](https://github.com/noir-lang/bigint/commit/56214208663e94c15e44d7ca31a1f6a116a0010c))
* Fail in unconstrained `From<Field>` for values which do not fit ([#16](https://github.com/noir-lang/bigint/issues/16)) ([72e9ec6](https://github.com/noir-lang/bigint/commit/72e9ec65e009db2eb2ee05699ab114acfa0b0989))
* Fail on division by zero in `__udiv_mod` ([#10](https://github.com/noir-lang/bigint/issues/10)) ([ed59d2c](https://github.com/noir-lang/bigint/commit/ed59d2cbcde81512018e4187f7910524d1b25dbb))
* Make `assert_is_not_equal` exact and a free function ([#31](https://github.com/noir-lang/bigint/issues/31)) ([58a77eb](https://github.com/noir-lang/bigint/commit/58a77ebaf1b4c72b02ae2d51137293851b7ca795))
* Range-check the top limb in `to_be_bytes` for widths not divisible by 8 ([#19](https://github.com/noir-lang/bigint/issues/19)) ([af22e68](https://github.com/noir-lang/bigint/commit/af22e68382b2630aa9b82d1967093fe893bce0f6))
* Support multiplication of types with more than 65 limbs ([#18](https://github.com/noir-lang/bigint/issues/18)) ([198595e](https://github.com/noir-lang/bigint/commit/198595e3855deb9373c9fecf79b7cff9295f943d))


### Performance Improvements

* Derive `derive_from_seed` values directly from hash bits ([#1](https://github.com/noir-lang/bigint/issues/1)) ([a743139](https://github.com/noir-lang/bigint/commit/a743139efc1162a2b334e0b140f0097b1d74c6f5))


### Miscellaneous Chores

* Remove `assert_is_not_zero` ([#23](https://github.com/noir-lang/bigint/issues/23)) ([2b7bdc5](https://github.com/noir-lang/bigint/commit/2b7bdc592046ce897c14b08ab1bca2eeab08414c))
* Remove `derive_from_seed` from the public API ([#28](https://github.com/noir-lang/bigint/issues/28)) ([d915631](https://github.com/noir-lang/bigint/commit/d9156314bffc98d503e469afe42645409ec4178c))
* Remove `modulus_bits` and `conditional_select` ([#5](https://github.com/noir-lang/bigint/issues/5)) ([36a18b2](https://github.com/noir-lang/bigint/commit/36a18b209fb8c9f6ec33d005b7c9a8e6127474ba))
* Remove negation ([#6](https://github.com/noir-lang/bigint/issues/6)) ([f9037a4](https://github.com/noir-lang/bigint/commit/f9037a4daa19323caa20da00a8e72a3f5f1096cd))
* Remove redundant `BigInt` functions ([#9](https://github.com/noir-lang/bigint/issues/9)) ([c90b487](https://github.com/noir-lang/bigint/commit/c90b4872242c4b671f26a9870851b52d77132aaa))
