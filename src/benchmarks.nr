comptime fn make_bench(m: Module, typ_path: Quoted) -> Quoted {
    let module_name = m.name();

    // Constrained methods' benchmarks

    let add_bench_name = f"add_{module_name}".quoted_contents();

    let sub_bench_name = f"sub_{module_name}".quoted_contents();

    let mul_bench_name = f"mul_{module_name}".quoted_contents();

    let div_rem_bench_name = f"div_rem_{module_name}".quoted_contents();
    let rem_bench_name = f"rem_{module_name}".quoted_contents();
    let div_bench_name = f"div_{module_name}".quoted_contents();

    let eq_bench_name = f"eq_{module_name}".quoted_contents();
    let cmp_bench_name = f"cmp_{module_name}".quoted_contents();
    let is_zero_bench_name = f"is_zero_{module_name}".quoted_contents();

    let assert_is_not_equal_bench_name = f"assert_is_not_equal_{module_name}".quoted_contents();

    let validate_in_range_bench_name = f"validate_in_range_{module_name}".quoted_contents();

    let from_field_bench_name = f"from_field_{module_name}".quoted_contents();
    let to_field_bench_name = f"to_field_{module_name}".quoted_contents();

    let to_be_bytes_bench_name = f"to_be_bytes_{module_name}".quoted_contents();
    let from_be_bytes_bench_name = f"from_be_bytes_{module_name}".quoted_contents();
    let to_le_bytes_bench_name = f"to_le_bytes_{module_name}".quoted_contents();
    let from_le_bytes_bench_name = f"from_le_bytes_{module_name}".quoted_contents();

    let derive_from_seed_13_elements_bench_name =
        f"derive_from_seed_13_elements_{module_name}".quoted_contents();

    let evaluate_quadratic_expression_1_element_bench_name =
        f"evaluate_quadratic_expression_1_element_{module_name}".quoted_contents();
    let evaluate_quadratic_expression_3_elements_bench_name =
        f"evaluate_quadratic_expression_3_elements_{module_name}".quoted_contents();

    // Unconstrained methods' benchmarks
    let pow_bench_name = f"pow_{module_name}".quoted_contents();

    let BigInt = quote { crate::bigint::BigInt };
    let typ = typ_path.as_type();

    let typ_token = typ_path;
    let BITS = quote { <$typ_token as $BigInt>::BITS };
    let N = quote { <$typ_token as $BigInt>::N };

    quote {
        #[export]
        fn $add_bench_name(a: $typ, b: $typ) -> $typ {
            a + b
        }

        #[export]
        fn $sub_bench_name(a: $typ, b: $typ) -> $typ {
            a - b
        }

        #[export]
        fn $mul_bench_name(a: $typ, b: $typ) -> $typ {
            a * b
        }

        #[export]
        fn $rem_bench_name(a: $typ, b: $typ) -> $typ {
            a % b
        }

        #[export]
        fn $div_rem_bench_name(a: $typ, b: $typ) -> ($typ, $typ) {
            $BigInt::div_rem(&a, &b)
        }

        #[export]
        fn $div_bench_name(a: $typ, b: $typ) -> $typ {
            a / b
        }

        #[export]
        fn $eq_bench_name(a: $typ, b: $typ) -> bool {
            a == b
        }

        #[export]
        fn $cmp_bench_name(a: $typ, b: $typ) -> bool {
            a > b
        }

        #[export]
        fn $is_zero_bench_name(a: $typ) -> bool {
            $BigInt::is_zero(&a)
        }

        #[export]
        fn $assert_is_not_equal_bench_name(a: $typ, b: $typ) {
            crate::bigint::assert_is_not_equal(a, b)
        }

        #[export]
        fn $validate_in_range_bench_name(a: $typ) {
            $BigInt::validate_in_range(&a)
        }

        #[export]
        fn $from_field_bench_name(a: Field) -> $typ {
            $typ::from(a)
        }

        #[export]
        fn $to_field_bench_name(a: $typ) -> Field {
            crate::bigint::to_field(a)
        }

        #[export]
        fn $from_be_bytes_bench_name(a: [u8; ($BITS + 7) / 8]) -> [u128; $N] {
            crate::fns::serialization::from_be_bytes::<$N, $BITS>(&a)
        }

        #[export]
        fn $to_be_bytes_bench_name(a: $typ) -> [u8; ($BITS + 7) / 8] {
            crate::fns::serialization::to_be_bytes::<$N, $BITS>(&$BigInt::get_limbs(&a))
        }

        #[export]
        fn $from_le_bytes_bench_name(a: [u8; ($BITS + 7) / 8]) -> [u128; $N] {
            crate::fns::serialization::from_le_bytes::<$N, $BITS>(&a)
        }

        #[export]
        fn $to_le_bytes_bench_name(a: $typ) -> [u8; ($BITS + 7) / 8] {
            crate::fns::serialization::to_le_bytes::<$N, $BITS>(&$BigInt::get_limbs(&a))
        }

        #[export]
        fn $derive_from_seed_13_elements_bench_name(a: [u8; 13]) -> $typ {
            $BigInt::from_limbs(crate::fns::constrained_ops::derive_from_seed::<$N, $BITS, 13>(a))
        }

        // `evaluate_quadratic_expression` bounds `NUM_PRODUCTS * LHS_N * RHS_N` so that
        // the product limbs cannot exceed 2^246 (see `assert_product_limbs_fit`).
        // The tightest configuration benchmarked here is U2048 (`N = 18`), which admits at
        // most 3 sub-products in total, so these benchmarks use single-term linear
        // combinations and at most 3 products.
        #[export]
        fn $evaluate_quadratic_expression_1_element_bench_name(
            lhs: [[$typ; 1]; 1],
            lhs_flags: [[bool; 1]; 1],
            rhs: [[$typ; 1]; 1],
            rhs_flags: [[bool; 1]; 1],
            add: [$typ; 3],
            add_flags: [bool; 3],
        ) {
            crate::bigint::evaluate_quadratic_expression(lhs, lhs_flags, rhs, rhs_flags, add, add_flags)
        }

        #[export]
        fn $evaluate_quadratic_expression_3_elements_bench_name(
            lhs: [[$typ; 1]; 3],
            lhs_flags: [[bool; 1]; 3],
            rhs: [[$typ; 1]; 3],
            rhs_flags: [[bool; 1]; 3],
            add: [$typ; 3],
            add_flags: [bool; 3],
        ) {
            crate::bigint::evaluate_quadratic_expression(lhs, lhs_flags, rhs, rhs_flags, add, add_flags)
        }

        #[export]
        fn $pow_bench_name(a: $typ, b: $typ) -> $typ {
            // Safety: Benchmarking
            unsafe {
                $BigInt::__pow(&a, &b)
            }
        }
    }
}

// the types we will be benchmarking
// type U256
// type U512
// type U2048

#[make_bench(quote { crate::types::U256::U256 })]
mod U256_Bench {}

#[make_bench(quote { crate::types::U512::U512 })]
mod U512_Bench {}

#[make_bench(quote { crate::types::U2048::U2048 })]
mod U2048_Bench {}
