// Widening conversions between the pre-defined `BigInt` types.
//
// For each pair of types, `From<Smaller> for Larger` zero-extends the limbs. The result is
// range-checked via `from_limbs`, so a source value which is not normalised (e.g. a circuit input)
// cannot produce an unnormalised result. This adds no constraints when the source value has
// already been range-checked, e.g. as the output of another operation.

/// Zero-extend `N` limbs to `M >= N` limbs.
pub(crate) fn widen<let N: u32, let M: u32>(limbs: [u128; N]) -> [u128; M] {
    let mut result: [u128; M] = [0; M];
    for i in 0..N {
        result[i] = limbs[i];
    }
    result
}

/// Generates `From<Smaller> for Larger` for every pair of pre-defined `BigInt` types.
comptime fn widening_conversions(_m: Module) -> Quoted {
    // In increasing order of width
    let types: [Quoted; 6] = [
        quote { crate::types::U256::U256 },
        quote { crate::types::U512::U512 },
        quote { crate::types::U1024::U1024 },
        quote { crate::types::U2048::U2048 },
        quote { crate::types::U4096::U4096 },
        quote { crate::types::U8192::U8192 },
    ];
    let mut impls: Quoted = quote {};
    for i in 0..types.len() {
        for j in i + 1..types.len() {
            let from = types[i];
            let to = types[j];
            impls = quote {
                $impls

                impl std::convert::From<$from> for $to {
                    fn from(value: $from) -> Self {
                        <$to as crate::bigint::BigInt>::from_limbs(
                            crate::conversions::widen(<$from as crate::bigint::BigInt>::get_limbs(&value)),
                        )
                    }
                }
            };
        }
    }
    impls
}

#[widening_conversions]
mod widening {}
