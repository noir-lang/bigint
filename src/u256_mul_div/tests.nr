//! Fixed boundary and regression cases with expected values computed by an
//! independent big-integer reference. Every case runs the constrained path in a
//! normal `nargo test` run and the unconstrained path under `--force-brillig`.

use crate::{BigInt, U256};
use mul_div::MulDiv;

/// (a, b, d, floor quotient, remainder, ceiling quotient) for inputs every operation accepts.
global U128_CASES: [(u128, u128, u128, u128, u128, u128); 29] = [
    (0x0, 0xffffffffffffffffffffffffffffffff, 0x1, 0x0, 0x0, 0x0),
    (0xffffffffffffffffffffffffffffffff, 0x0, 0xffffffffffffffffffffffffffffffff, 0x0, 0x0, 0x0),
    (0x0, 0x0, 0xffffffffffffffffffffffffffffffff, 0x0, 0x0, 0x0),
    (0x1, 0x1, 0x2, 0x0, 0x1, 0x1),
    (0x7, 0x9, 0x4, 0xf, 0x3, 0x10),
    (
        0xffffffffffffffffffffffffffffffff, 0x1, 0x1, 0xffffffffffffffffffffffffffffffff, 0x0,
        0xffffffffffffffffffffffffffffffff,
    ),
    (
        0xffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffff, 0x0,
        0xffffffffffffffffffffffffffffffff,
    ),
    (
        0x10000000000000000, 0x10000000000000000, 0x2, 0x80000000000000000000000000000000, 0x0,
        0x80000000000000000000000000000000,
    ),
    (
        0x10000000000000000, 0x10000000000000000, 0x10000000000000000, 0x10000000000000000, 0x0,
        0x10000000000000000,
    ),
    (
        0x10000000000000001, 0x10000000000000001, 0x10000000000000000, 0x10000000000000002, 0x1,
        0x10000000000000003,
    ),
    (
        0xffffffffffffffffffffffffffffffff, 0x2, 0x2, 0xffffffffffffffffffffffffffffffff, 0x0,
        0xffffffffffffffffffffffffffffffff,
    ),
    (
        0xffffffffffffffffffffffffffffffff, 0x2, 0x3, 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, 0x0,
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,
    ),
    (
        0x10000000000000000, 0x10000000000000000, 0xffffffffffffffff, 0x10000000000000001, 0x1,
        0x10000000000000002,
    ),
    (
        0x10000000000000000, 0x10000000000000000, 0x10000000000000001, 0xffffffffffffffff, 0x1,
        0x10000000000000000,
    ),
    (0x0, 0x0, 0x10000000000000000, 0x0, 0x0, 0x0),
    (0x0, 0x0, 0x80000000000000000000000000000000, 0x0, 0x0, 0x0),
    (0x1, 0x10000000000000000, 0x10000000000000001, 0x0, 0x10000000000000000, 0x1),
    (
        0x1, 0x80000000000000000000000000000000, 0x80000000000000000000000000000001, 0x0,
        0x80000000000000000000000000000000, 0x1,
    ),
    (
        0x2, 0x80000000000000000000000000000000, 0x10000000000000001, 0xffffffffffffffff, 0x1,
        0x10000000000000000,
    ),
    (
        0x10000000000000000, 0x80000000000000000000000000000000, 0x80000000000000000000000000000001,
        0xffffffffffffffff, 0x7fffffffffffffff0000000000000001, 0x10000000000000000,
    ),
    (
        0x10000000000000001, 0x7fffffffffffffffffffffffffffffff, 0x10000000000000001,
        0x7fffffffffffffffffffffffffffffff, 0x0, 0x7fffffffffffffffffffffffffffffff,
    ),
    (
        0x7fffffffffffffffffffffffffffffff, 0xfffffffffffffffffffffffffffffffe,
        0xfffffffffffffffffffffffffffffffe, 0x7fffffffffffffffffffffffffffffff, 0x0,
        0x7fffffffffffffffffffffffffffffff,
    ),
    (
        0x85ada4e2860eea3066d0346e82d1de75, 0x50e80f8b427d44383903fd359bd01212,
        0x2aacac371128211961d70dbf5216b4e1, 0xfd70bb913d2a4eacf74a8f3bc52162d9,
        0x2a11dba52b48e7d24b4c2ed3cdf76981, 0xfd70bb913d2a4eacf74a8f3bc52162da,
    ),
    (
        0x72182d4fb83855ae5f0b2012f27ef5b4, 0xab187af5a319b26b25e65390427c989a,
        0x8dccb709b8385057d612e038a27924d9, 0x89aa9ddace670913d018830d2d5cc696,
        0x7fe3da4a72fe946bf47b859764fb4122, 0x89aa9ddace670913d018830d2d5cc697,
    ),
    (
        0xcb0c34190991ad734e7abffa98b8c2e5, 0x489f30add8cb0e02e7a30b2c10003ed0,
        0x433b878d4f89e7efff6cca149879d5c1, 0xdb52e3c03955a64ef41f86dd552bc73b,
        0x89affea5128287f9e085bd04fa98595, 0xdb52e3c03955a64ef41f86dd552bc73c,
    ),
    (
        0x14da46af749ca05e057d8859e83e57f9, 0x347e7a7f96430fbd6a9a404594d93ffe,
        0xa8e6dbd537d1d9cbed100c19972d250b, 0x67b1dda5dfc0addf5355849ea5f0922,
        0x9a3bf448d467dff0590c0fb6d4314198, 0x67b1dda5dfc0addf5355849ea5f0923,
    ),
    (
        0x8e26ac5f826e8d729860820838491a74, 0xf7f56f4ef367ebea68329d373e3afdde,
        0x9cb6c22482959c59f18c0ed8d8bcfdec, 0xe0eab74a9df233fafeeb30093a107b9b,
        0x15ddd4e86c25cae047ca7293c5a372b4, 0xe0eab74a9df233fafeeb30093a107b9c,
    ),
    (
        0x9d69af2fd6672cc8af25e8ba05bff13f, 0x4c80d0b47cfc97b50b376f0187ac5f8f,
        0x5896e3f632642519e411e7281e6c4cb4, 0x87efe1ae75b6c0e2e69e1bbd0908d86f,
        0x5785fae0156490d3942dec6f74c50125, 0x87efe1ae75b6c0e2e69e1bbd0908d870,
    ),
    (
        0xf6a7a1f962146a1864022ca1f7701521, 0x763274664e162b8196f4fcdc8dfbd610,
        0x82b14d7d0874c474f373f15671dc1b91, 0xdf127a975395c1c8ef7e3c71f6ee906d,
        0x3804f6b62e5e69ce633943e0cbfe9b53, 0xdf127a975395c1c8ef7e3c71f6ee906e,
    ),
];

/// Inputs below 2^128 widened to U256 give the same result as the u128 reference.
fn check_widened_u128_case(case: (u128, u128, u128, u128, u128, u128)) {
    let (a, b, d, q, r, ceil) = case;
    let (a, b, d) = (U256::from(a), U256::from(b), U256::from(d));
    assert_eq(a.mul_div_rem(b, d), (U256::from(q), U256::from(r)));
    assert_eq(a.mul_div_floor(b, d), U256::from(q));
    assert_eq(a.mul_div_ceil(b, d), U256::from(ceil));
}

#[test]
fn widened_u128_boundaries() {
    for case in U128_CASES {
        check_widened_u128_case(case);
    }
}

/// Builds a U256 from its high and low 128-bit halves.
fn u256(hi: u128, lo: u128) -> U256 {
    let lo_bytes: [u8; 16] = (lo as Field).to_le_bytes();
    let hi_bytes: [u8; 16] = (hi as Field).to_le_bytes();
    let mut bytes = [0; 32];
    for i in 0..16 {
        bytes[i] = lo_bytes[i];
        bytes[i + 16] = hi_bytes[i];
    }
    U256::from_le_bytes(bytes)
}

fn u256_cases() -> [(U256, U256, U256, U256, U256, U256); 31] {
    [
        (
            u256(0x0, 0x0),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x1), u256(0x0, 0x0), u256(0x0, 0x0), u256(0x0, 0x0),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x0),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x0), u256(0x0, 0x0), u256(0x0, 0x0),
        ),
        (
            u256(0x0, 0x7), u256(0x0, 0x9), u256(0x0, 0x4), u256(0x0, 0xf), u256(0x0, 0x3),
            u256(0x0, 0x10),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x1), u256(0x0, 0x1),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x0),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x0),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ),
        ),
        (
            u256(0x1, 0x0), u256(0x1, 0x0), u256(0x0, 0x2),
            u256(0x80000000000000000000000000000000, 0x0), u256(0x0, 0x0),
            u256(0x80000000000000000000000000000000, 0x0),
        ),
        (
            u256(0x1, 0x1), u256(0x1, 0x1), u256(0x1, 0x0), u256(0x1, 0x2), u256(0x0, 0x1),
            u256(0x1, 0x3),
        ),
        (
            u256(
                0x1e3144ffada2a50acf4a2b0b058686bc,
                0x34d76e8aed092b088f29ba71c1eac84d,
            ), u256(0x0, 0x28c1bfad94b415d8beae318c726a74cb),
            u256(0x0, 0x39050bb7c9189269fe5d583ce4dbc394),
            u256(
                0x1594c3fdb1871b3217f0872a1262228a,
                0xe0af710fed82aa1c2dd9e3cc07e696b1,
            ), u256(0x0, 0x2927758f42faf29605e41daa9e4ec7bb),
            u256(
                0x1594c3fdb1871b3217f0872a1262228a,
                0xe0af710fed82aa1c2dd9e3cc07e696b2,
            ),
        ),
        (
            u256(
                0xe5aaf55eff50a6e7005bae9cb055707,
                0xc50e39598269a358f6342676b711524d,
            ), u256(0x0, 0x71ce7b2bd4433dfe8ca1641934f909d),
            u256(0x0, 0x3ac2ad12b2d6c8afce3f812c5256d4e6),
            u256(
                0x1bcd165612e95a6d278336b24c94aa2,
                0x904b7f51fa2d1db009dffc1735d19054,
            ), u256(0x0, 0x177207211d5c95db9d26457256a88dc1),
            u256(
                0x1bcd165612e95a6d278336b24c94aa2,
                0x904b7f51fa2d1db009dffc1735d19055,
            ),
        ),
        (
            u256(
                0x825c552cc8e364bd2af71054aa51fb67,
                0x2b8ee95365d89917fa0d292aa529cbe1,
            ), u256(0x0, 0xcf3fa687b2c9c73cb111c39c564832c6),
            u256(0x0, 0xe8a97d3c80be23018a67904c4addc2f7),
            u256(
                0x741f1ba4b46b7b9e7efaf3c42297ec78,
                0xe8dd6dd86a6aacd8e64c1b947ded3c12,
            ), u256(0x0, 0xe20a51b8448e0ce42705e7637e7908a8),
            u256(
                0x741f1ba4b46b7b9e7efaf3c42297ec78,
                0xe8dd6dd86a6aacd8e64c1b947ded3c13,
            ),
        ),
        (
            u256(
                0x6e1b2a01d5a21f23a693289dfa56735c,
                0x9ef1f5ef8134a13456faec9b42232cbc,
            ), u256(0x0, 0xbd4941885461a5806f3382d15dd00119),
            u256(0x0, 0xc6e3a3ed6c39644c8340310d667eb939),
            u256(
                0x68ca308f5d3af6a5748bdd778405bd47,
                0x4aa613a067832421522de1c9f2744d67,
            ), u256(0x0, 0x8092e9605de96fbfb9a2b03f12d56f6d),
            u256(
                0x68ca308f5d3af6a5748bdd778405bd47,
                0x4aa613a067832421522de1c9f2744d68,
            ),
        ),
        (
            u256(
                0xbdf9af5e729c6d5087bf83570dab96ad,
                0xde1ee6d4f8b12a7e60010cd17756c9cf,
            ), u256(0x0, 0x91fa1d0263f577e1e8d8af088e8fde1b),
            u256(0x0, 0xa58e50056e27a472fa78a206b82611eb),
            u256(
                0xa78230470e00cdf4c4c6b77b0b6419b8,
                0x81e77327fb93b346ed15f70b18b1a41f,
            ), u256(0x0, 0x9ce5afa6edb3bd8b5f3c49964a381360),
            u256(
                0xa78230470e00cdf4c4c6b77b0b6419b8,
                0x81e77327fb93b346ed15f70b18b1a420,
            ),
        ),
        (
            u256(
                0x49a253fe070fe91f4b27bb46c51d411e,
                0x47d2ff54bd5369b980d6aa0453c8c4f,
            ), u256(0x0, 0x552d05232d3183d4971374d7cf7f8d04),
            u256(0x0, 0x55aa6d3ee8c8cb04e34e9bd3af66e9b2),
            u256(
                0x493688dcc44982500e32bd35c9bd3a42,
                0xe5d59974e4213ebbf97908032b99a21f,
            ), u256(0x0, 0xc366b1e06dd7b2e07f9a2fffbafc3ae),
            u256(
                0x493688dcc44982500e32bd35c9bd3a42,
                0xe5d59974e4213ebbf97908032b99a220,
            ),
        ),
        (
            u256(
                0xa2c1bb6cbb8a498f89b22516e21c84d7,
                0x55f24f5ff533150616cb25da908b6418,
            ), u256(0x804293630920c008, 0xca1e3fd323a6f54e6b7e65ecc8ad9368),
            u256(0xe65b7a6719b5c97f, 0x61e53c06e11b9c9cb5c8f1e5a363bbbd),
            u256(
                0x5a9ef458cf1cd7b63a3c7c036d4031ad,
                0x771358d298c5e8c1ef405c4606024370,
            ), u256(0x4d8675015402228d, 0x8269b56809a00a1c7ddc6739ac13d810),
            u256(
                0x5a9ef458cf1cd7b63a3c7c036d4031ad,
                0x771358d298c5e8c1ef405c4606024371,
            ),
        ),
        (
            u256(
                0x6a864651b28565b8226cdf9d0a678e3b,
                0x3f7353e1d3bea17b1ae121c8f5ef2d7a,
            ), u256(0x52a9611017474023, 0xad73e51d83d586901390909185a73bb3),
            u256(0x5e56b1bb12d8377e, 0xfb585c5771d3b70755d8857fdfbe6e87),
            u256(
                0x5d56d34c18356a4752129e76a571e34d,
                0x3a73d1f9d05114a2bc91ed13efc3a7d,
            ), u256(0x3464dd673a3f93c9, 0xd67bd471592af629cd4b6f613e635c63),
            u256(
                0x5d56d34c18356a4752129e76a571e34d,
                0x3a73d1f9d05114a2bc91ed13efc3a7e,
            ),
        ),
        (
            u256(
                0x99030a1eeb26886bfdf0ea5419f5e6d8,
                0x58f0e265265a77fc3d965063f9cba456,
            ), u256(0x5ba3de7244f934aa, 0x7d02ca7689014d92ca888329928fa233),
            u256(0x6214f71d64c04b08, 0xdc76ac0ac68871d16c1c9fd183699659),
            u256(
                0x8ef66148318377fa584eabe6935f4e0c,
                0xb9018c58b0ec1094b28b13c11d92d488,
            ), u256(0x6113126d9c95cfe, 0x560fb110fad295883e8103c3653e95da),
            u256(
                0x8ef66148318377fa584eabe6935f4e0c,
                0xb9018c58b0ec1094b28b13c11d92d489,
            ),
        ),
        (
            u256(
                0xd004c9f3278a2e330a76c1f88d0ff370,
                0x6723f1289bffde2b538a802b9fda1db9,
            ), u256(0x19a5a4451b97b966, 0x595a3f2cc1dfa21ed1a965b61ff1ba36),
            u256(0x862a49cfc7db467b, 0xa790ad108915fa4123350dbed2df7f00),
            u256(
                0x27c3cfa9ef2e0425820c2160c8be97fb,
                0x2d779b1f0faf91a21f9f33d806022666,
            ), u256(0x3589df4ad7870e66, 0x75109b0375fe54a2bd32e7bf63dd1506),
            u256(
                0x27c3cfa9ef2e0425820c2160c8be97fb,
                0x2d779b1f0faf91a21f9f33d806022667,
            ),
        ),
        (
            u256(
                0x7bacde01f2437a024c069fc0dcaa7374,
                0x9138a5bf096b724784d3f209eec6868e,
            ), u256(0x6d21bd04e19a46b8, 0x79c868c32abd9c0a5373b33b03a3b6ee),
            u256(0x9e1e5e3c0898a584, 0xda46d2375ec8fd7e36215cfba6e470b7),
            u256(
                0x555bfe422add677aec061cb1fc93d91c,
                0xf52d411ab3ee9bf646cba2f92957d06e,
            ), u256(0x1f1767c589b8c20a, 0x3e30b98b4f8479aa2518944887b5ed62),
            u256(
                0x555bfe422add677aec061cb1fc93d91c,
                0xf52d411ab3ee9bf646cba2f92957d06f,
            ),
        ),
        (
            u256(
                0xe8f176f6936afe3beb98c88a93e13627,
                0x12c2b62deb15360fd6668fc402fed2a0,
            ), u256(0x14fa7fc1fd26aab, 0xeafc894f617378fc377b21627a1767bc),
            u256(0x43c93e2cbed3bfcb, 0xfcc928c6d8c15d0fa8615b28b344d645),
            u256(
                0x48176cb40c7a76963cc97d5fd71d1ac,
                0xeb145c495e02c20fe8af9c678b5c2034,
            ), u256(0x2ca9801e855704ed, 0x21bb19249a128c9e4d34be2769b0e77c),
            u256(
                0x48176cb40c7a76963cc97d5fd71d1ac,
                0xeb145c495e02c20fe8af9c678b5c2035,
            ),
        ),
        (
            u256(
                0x5ec1c7aa9cf8df147c8b4316fd76b623,
                0xac4bfa28a91851b2b8d4dceeed0c5916,
            ), u256(
                0x1b06343c328392acbd1a58952fba8ccb,
                0xbcb2a3ebddcce311e5be4037cee88b33,
            ), u256(
                0x28596fa8c63fa13e6e2cb8008b664932,
                0xf8d2738b24f3f7bb2d8e93d9324b6753,
            ), u256(
                0x3f76cc7f2e4bb61509d7349ecc3458e0,
                0x475aba302ab735855e0fddd798e186df,
            ), u256(
                0x7be942e403f62d28b0a5f55bb5714a2,
                0xc9de2a034e5e12429c29430efe0d3e15,
            ), u256(
                0x3f76cc7f2e4bb61509d7349ecc3458e0,
                0x475aba302ab735855e0fddd798e186e0,
            ),
        ),
        (
            u256(
                0x634e46832eb2a563b014c0783c01e30e,
                0x98c3af21adbe704cee10ad5f78ab22db,
            ), u256(
                0x3b50dd5980edb46c78d24046d84a2303,
                0x664f2330934943dab8583fdf0692cc96,
            ), u256(
                0x6b8325f1321eda67bd67ac74798c041e,
                0x8cb5f17b081017434771e0dae252ee4e,
            ), u256(
                0x36c9c9721be45e90c91808936b838378,
                0xa734e52c4565ea02dfa31a83db317d71,
            ), u256(
                0x251ea9d870534dfca2583af123d829df,
                0x48b7c1e7583e41dd2b447d825b0da9e4,
            ), u256(
                0x36c9c9721be45e90c91808936b838378,
                0xa734e52c4565ea02dfa31a83db317d72,
            ),
        ),
        (
            u256(
                0x51907982ebd6a2c7351a6b83d1aa990b,
                0x8e4d7131bd1c0799a3071a55c6ec62ac,
            ), u256(
                0xbcfafb0c159c74c10da688d2f14de633,
                0x5a6bf2a04d1df1aca74dca3f4b9f8921,
            ), u256(
                0xfe027bc1c8f11b15f20cba8f8a61d174,
                0x4d03e447cd43b1d0da6e045b44047ac5,
            ), u256(
                0x3caed74a44ea3f11500ecf37eaf16a54,
                0x609f801cacf1033ffb0253427ef01031,
            ), u256(
                0xb457c7fab0930a27263bd287189f59ab,
                0xb11acf039099c7e5df76126e76e2f477,
            ), u256(
                0x3caed74a44ea3f11500ecf37eaf16a54,
                0x609f801cacf1033ffb0253427ef01032,
            ),
        ),
        (
            u256(
                0x1578f89ecbebe607e879f2c3a94fc001,
                0xf9ec9e83c22f7c1eeb975b4cda5f7e9f,
            ), u256(
                0x876fd29b9b415d3adc5f63ca80bb5d83,
                0x4e568da7d9b8e007088de3df8109c226,
            ), u256(
                0xfc66ab63f1b8ceb70bfea931fabeab5c,
                0xa94263c0ca37450161ff8f8ac3ef848a,
            ), u256(
                0xb85a3d315d98dcec32cc1d022edd3df,
                0xf2c9d8f32645ea4eecfd42fed6b8bc97,
            ), u256(
                0xe83200d5d0c8463d05b725319a992afa,
                0x7fe99017d3b3fb56348d2bf343ebc434,
            ), u256(
                0xb85a3d315d98dcec32cc1d022edd3df,
                0xf2c9d8f32645ea4eecfd42fed6b8bc98,
            ),
        ),
        (
            u256(
                0x762c1d073ea4b1422a34cd23e177067d,
                0x998b7097396b2e951ff96828edef7a58,
            ), u256(
                0x3989e020cc1337351c0b4c079288d5be,
                0x68d8af8e03d4a489424fabe34bd09a41,
            ), u256(
                0x83d77c9ea7812132ff1b6fc9b6cd652e,
                0x916aed1dde0de485904e8c71915ced27,
            ), u256(
                0x3392ac717308c94a6088a5c3b69496d2,
                0xbef47742dfb75762d25d625a94e8bf2c,
            ), u256(
                0x133b0f49a83f83759286407aa194bdf7,
                0x76e06694c6994137ff4f2ef8e0a624a4,
            ), u256(
                0x3392ac717308c94a6088a5c3b69496d2,
                0xbef47742dfb75762d25d625a94e8bf2d,
            ),
        ),
        (
            u256(
                0xd8886c0857a640c2674b86bc7fdd0ea6,
                0xc7c4042cce32c5f5afb49bb1fac9f453,
            ), u256(
                0x3599bd9de6d9e11235d84b30c4321b2d,
                0x1e6d7601997819aead8ab5008888ae6d,
            ), u256(
                0x62f432a5fe83a2b7737608f2d4a10b9f,
                0xcc5680032e721ae9284cd6be32a0ccf2,
            ), u256(
                0x754a2ffb8b25cee6f8ced723a647a77b,
                0xe9736c059e42f85a31eebf385a01e90d,
            ), u256(
                0x5934b2ee347a15f99a418e28be0afdf4,
                0x4680b1bf43247e7d40855f82280c70d,
            ), u256(
                0x754a2ffb8b25cee6f8ced723a647a77b,
                0xe9736c059e42f85a31eebf385a01e90e,
            ),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0xffffffffffffffff), u256(0x0, 0x10000000000000000),
            u256(
                0xfffffffffffffffeffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x1), u256(0xffffffffffffffff0000000000000000, 0x0),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x10000000000000000), u256(0x0, 0x10000000000000001),
            u256(
                0xffffffffffffffff0000000000000000,
                0xffffffffffffffff0000000000000000,
            ), u256(0x0, 0x0),
            u256(
                0xffffffffffffffff0000000000000000,
                0xffffffffffffffff0000000000000000,
            ),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0xffffffffffffffffffffffffffffffff), u256(0x1, 0x0),
            u256(
                0xfffffffffffffffffffffffffffffffe,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x1), u256(0xffffffffffffffffffffffffffffffff, 0x0),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x1, 0x0), u256(0x1, 0x1), u256(0xffffffffffffffffffffffffffffffff, 0x0),
            u256(0x0, 0x0), u256(0xffffffffffffffffffffffffffffffff, 0x0),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0xffffffffffffffff, 0xffffffffffffffffffffffffffffffff),
            u256(0x10000000000000000, 0x0),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffeffffffffffffffff,
            ), u256(0x0, 0x1),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffff0000000000000000,
            ),
        ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x10000000000000000, 0x0), u256(0x10000000000000000, 0x1),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffeffffffffffffffff,
            ), u256(0x0, 0x10000000000000001),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffff0000000000000000,
            ),
        ),
    ]
}

#[test]
fn u256_boundaries() {
    for case in u256_cases() {
        let (a, b, d, q, r, ceil) = case;
        assert_eq(a.mul_div_rem(b, d), (q, r));
        assert_eq(a.mul_div_floor(b, d), q);
        assert_eq(a.mul_div_ceil(b, d), ceil);
    }
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_0_0_rem_rejects() {
    let _ = u256(0x0, 0x0).mul_div_rem(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_0_0_floor_rejects() {
    let _ = u256(0x0, 0x0).mul_div_floor(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_0_0_ceil_rejects() {
    let _ = u256(0x0, 0x0).mul_div_ceil(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_max_0_rem_rejects() {
    let _ = u256(0x0, 0x0).mul_div_rem(
        u256(
            0xffffffffffffffffffffffffffffffff,
            0xffffffffffffffffffffffffffffffff,
        ),
        u256(0x0, 0x0),
    );
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_max_0_floor_rejects() {
    let _ = u256(0x0, 0x0).mul_div_floor(
        u256(
            0xffffffffffffffffffffffffffffffff,
            0xffffffffffffffffffffffffffffffff,
        ),
        u256(0x0, 0x0),
    );
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_0_max_0_ceil_rejects() {
    let _ = u256(0x0, 0x0).mul_div_ceil(
        u256(
            0xffffffffffffffffffffffffffffffff,
            0xffffffffffffffffffffffffffffffff,
        ),
        u256(0x0, 0x0),
    );
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_max_0_0_rem_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_rem(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_max_0_0_floor_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_floor(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_max_0_0_ceil_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_ceil(u256(0x0, 0x0), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_1_1_0_rem_rejects() {
    let _ = u256(0x0, 0x1).mul_div_rem(u256(0x0, 0x1), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_1_1_0_floor_rejects() {
    let _ = u256(0x0, 0x1).mul_div_floor(u256(0x0, 0x1), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: zero denominator")]
fn u256_1_1_0_ceil_rejects() {
    let _ = u256(0x0, 0x1).mul_div_ceil(u256(0x0, 0x1), u256(0x0, 0x0));
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_max_max_minus_1_rem_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_rem(
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffffffffffffffffffe,
            ),
        );
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_max_max_minus_1_floor_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_floor(
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffffffffffffffffffe,
            ),
        );
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_max_max_minus_1_ceil_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_ceil(
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffffffffffffffffffe,
            ),
        );
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_2_1_rem_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_rem(u256(0x0, 0x2), u256(0x0, 0x1));
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_2_1_floor_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_floor(u256(0x0, 0x2), u256(0x0, 0x1));
}

#[test(should_fail_with = "mul_div: quotient overflow")]
fn u256_max_2_1_ceil_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff,
    )
        .mul_div_ceil(u256(0x0, 0x2), u256(0x0, 0x1));
}

#[test]
fn u256_max_minus_1_max_minus_1_max_minus_2_floor_fits() {
    assert_eq(
        u256(
            0xffffffffffffffffffffffffffffffff,
            0xfffffffffffffffffffffffffffffffe,
        )
            .mul_div_rem(
                u256(
                    0xffffffffffffffffffffffffffffffff,
                    0xfffffffffffffffffffffffffffffffe,
                ),
                u256(
                    0xffffffffffffffffffffffffffffffff,
                    0xfffffffffffffffffffffffffffffffd,
                ),
            ),
        (
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffff,
            ), u256(0x0, 0x1),
        ),
    );
}

#[test(should_fail_with = "mul_div: ceiling overflow")]
fn u256_max_minus_1_max_minus_1_max_minus_2_ceil_rejects() {
    let _ = u256(
        0xffffffffffffffffffffffffffffffff,
        0xfffffffffffffffffffffffffffffffe,
    )
        .mul_div_ceil(
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffffffffffffffffffe,
            ),
            u256(
                0xffffffffffffffffffffffffffffffff,
                0xfffffffffffffffffffffffffffffffd,
            ),
        );
}

// 2^120 in limb 0: one past the largest 120-bit limb, so not canonical.
fn noncanonical() -> U256 {
    U256::from_limbs_unsafe([1 << 120, 0, 0])
}

// The failure message depends on the execution mode: `call to assert_max_bit_size`
// when constrained, `BigInt is not in range` under `--force-brillig`. The
// unconstrained test below pins the latter.
#[test(should_fail)]
fn rejects_noncanonical_input() {
    let bad = noncanonical();
    let _ = bad.mul_div_rem(U256::one(), U256::one());
}

#[test(should_fail_with = "BigInt is not in range")]
unconstrained fn rejects_noncanonical_input_unconstrained() {
    let bad = noncanonical();
    let _ = bad.mul_div_rem(U256::one(), U256::one());
}

// In unconstrained code the verifier is skipped, so each input's own range check is
// the only guard. These pin the checks on `rhs` and `denominator`.
#[test(should_fail_with = "BigInt is not in range")]
unconstrained fn rejects_noncanonical_rhs_unconstrained() {
    let bad = noncanonical();
    let _ = U256::one().mul_div_rem(bad, U256::one());
}

#[test(should_fail_with = "BigInt is not in range")]
unconstrained fn rejects_noncanonical_denominator_unconstrained() {
    let bad = noncanonical();
    let _ = U256::one().mul_div_rem(U256::one(), bad);
}
