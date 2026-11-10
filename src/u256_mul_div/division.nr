use crate::{BigInt, U256};

global RADIX: u128 = 0x10000000000000000;
global MASK: u128 = RADIX - 1;
global MAX_ESTIMATE_CORRECTIONS: u32 = 2;

// The caller validates bigint's 120/120/16-bit limb representation before conversion.
unconstrained fn digits(value: U256) -> [u128; 4] {
    let limbs = value.get_limbs();
    [
        limbs[0] & MASK,
        (limbs[0] >> 64) | ((limbs[1] & 255) << 56),
        (limbs[1] >> 8) & MASK,
        (limbs[1] >> 72) | (limbs[2] << 48),
    ]
}

unconstrained fn from_digits(value: [u128; 4]) -> U256 {
    U256::from_limbs([
        value[0] | ((value[1] & 0xffffffffffffff) << 64),
        (value[1] >> 56) | (value[2] << 8) | ((value[3] & 0xffffffffffff) << 72),
        value[3] >> 48,
    ])
}

unconstrained fn less<let N: u32>(a: [u128; N], b: [u128; N]) -> bool {
    let mut result = false;
    for offset in 0..N {
        let i = N - 1 - offset;
        if a[i] != b[i] {
            result = a[i] < b[i];
            break;
        }
    }
    result
}

unconstrained fn product(a: [u128; 4], b: [u128; 4]) -> [u128; 8] {
    let mut result = [0; 8];
    let mut carry: Field = 0;
    for column in 0..8 {
        let mut sum = carry;
        for i in 0..4 {
            if column >= i {
                let j = column - i;
                if j < 4 {
                    sum += (a[i] as Field) * (b[j] as Field);
                }
            }
        }
        // At most four 64x64 products plus carry: sum < 2^130, below BN254 p.
        let low = sum as u64;
        result[column] = low as u128;
        carry = (sum - low as Field) / (RADIX as Field);
    }
    result
}

unconstrained fn scale_digits<let N: u32>(mut value: [u128; N], factor: u128) -> [u128; N] {
    let mut carry: u128 = 0;
    for i in 0..N {
        let combined = value[i] * factor + carry;
        value[i] = combined & MASK;
        carry = combined >> 64;
    }
    assert(carry == 0, "mul_div: internal scaling overflow");
    value
}

unconstrained fn digit_product(value: [u128; 4], digit: u128) -> [u128; 5] {
    let mut result = [0; 5];
    let mut carry: u128 = 0;
    for i in 0..4 {
        let combined = value[i] * digit + carry;
        result[i] = combined & MASK;
        carry = combined >> 64;
    }
    result[4] = carry;
    result
}

unconstrained fn subtract_digits(mut a: [u128; 5], b: [u128; 5]) -> [u128; 5] {
    let mut borrow: u128 = 0;
    for i in 0..5 {
        let adjusted = RADIX + a[i] - b[i] - borrow;
        a[i] = adjusted & MASK;
        borrow = (adjusted < RADIX) as u128;
    }
    assert(borrow == 0, "mul_div: internal subtraction underflow");
    a
}

pub(crate) unconstrained fn div_rem(a: U256, b: U256, d: U256) -> (U256, U256) {
    let divisor = digits(d);
    let mut length: u32 = 0;
    for i in 0..4 {
        if divisor[i] != 0 {
            length = i + 1;
        }
    }
    assert(length != 0, "mul_div: zero denominator");
    let numerator = product(digits(a), digits(b));
    let high = [numerator[4], numerator[5], numerator[6], numerator[7]];
    assert(less(high, divisor), "mul_div: quotient overflow");
    let mut quotient = [0; 4];
    let remainder = if length == 1 {
        let mut r = high[0];
        for offset in 0..4 {
            let i = 3 - offset;
            let part = (r << 64) | numerator[i];
            quotient[i] = part / divisor[0];
            r = part % divisor[0];
        }
        [r, 0, 0, 0]
    } else {
        let normalization_factor = RADIX / (divisor[length - 1] + 1);
        let normalized = if normalization_factor == 1 {
            divisor
        } else {
            scale_digits(divisor, normalization_factor)
        };
        let scaled = if normalization_factor == 1 {
            numerator
        } else {
            scale_digits(numerator, normalization_factor)
        };
        let padded_divisor = [normalized[0], normalized[1], normalized[2], normalized[3], 0];
        let mut r = [scaled[4], scaled[5], scaled[6], scaled[7]];
        for offset in 0..4 {
            let i = 3 - offset;
            let window = [scaled[i], r[0], r[1], r[2], r[3]];
            let top = normalized[length - 1];
            let mut estimate = if window[length] == top {
                MASK
            } else {
                ((window[length] << 64) | window[length - 1]) / top
            };
            let mut candidate = digit_product(normalized, estimate);
            for _ in 0..MAX_ESTIMATE_CORRECTIONS {
                if less(window, candidate) {
                    estimate -= 1;
                    candidate = subtract_digits(candidate, padded_divisor);
                } else {
                    break;
                }
            }
            let difference = subtract_digits(window, candidate);
            r = [difference[0], difference[1], difference[2], difference[3]];
            quotient[i] = estimate;
        }
        if normalization_factor != 1 {
            let mut carry: u128 = 0;
            for offset in 0..4 {
                let i = 3 - offset;
                let part = (carry << 64) | r[i];
                r[i] = part / normalization_factor;
                carry = part % normalization_factor;
            }
            assert(carry == 0, "mul_div: internal remainder unscaling");
        }
        r
    };
    (from_digits(quotient), from_digits(remainder))
}
