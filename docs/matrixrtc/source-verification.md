# MatrixRTC source verification

Status: VERIFIED
Observed: 2026-07-31
Credential mode: none

Each source was downloaded over HTTPS from `raw.githubusercontent.com/matrix-org/matrix-spec-proposals/<head>/<source_path>` and hashed independently with SHA-256. No branch name, mutable tag, authenticated request, credential, or cached repository copy was used for this verification.

| MSC | Exact head | Source path | SHA-256 | Result |
|---:|---|---|---|---|
| 4143 | `3236b007aaceee73e579e33990dd3ec5e07841e4` | `proposals/4143-matrix-rtc.md` | `78f14c6467a28600094c6837bab55706c0f75c4f535e671503e9fb4a11e04103` | MATCH |
| 4140 | `15770e6988f307499519b0cb294b95ed494171b6` | `proposals/4140-delayed-events-futures.md` | `6becf1e8e177e9cd28fea0f668b097be703775459d5141266970169dfaf7c8ab` | MATCH |
| 4195 | `afdcf273e507152699ffb0cbfa3f364550f2b112` | `proposals/4195-matrixrtc-livekit.md` | `007d7b33c29dbb2108f3df96dc9e6bd766f3e84399f18f205b44bda7a26f979c` | MATCH |
| 4196 | `5add2f0c96974c4996a6e5e0907018117cbb5934` | `proposals/4196-matrixrtc-m-call.md` | `29b0307635ac3524786cd1352fd8bbaaaa488160974561a371cf735841ec0e23` | MATCH |
| 4075 | `39cc54743a4f2187fdee1a69909b4a84eb7af014` | `proposals/4075-rtc-notification-event.md` | `b28513416ed3cedd81fb3d0f4b521a893a2ddf18929f58817469d7f5eadd325a` | MATCH |
| 4310 | `67687dc381f56c626edf6e00a2bd2c5e2d04e56b` | `proposals/4310-MatrixRTC-call-decline.md` | `a75e97e72de589c6b23b1d95ad542f202935f8e170a42dcbc96734689743e375` | MATCH |
| 4519 | `db488faa1c3f234847dada8d17893d60626e869d` | `proposals/4519-rtc-transports-registry.md` | `22aef4423a8b42561aff9e1e1333a0cfc10500c5275a3ea29359f66b275d9ae4` | MATCH |
| 4354 | `74fc75e1dc1301230cc3fcb7435205bf4f567ef8` | `proposals/4354-sticky-events.md` | `1a89c37ee7b0add4e55ebef2cce0d6ccb14ecb88e18a4dfdce498737b465ee02` | MATCH |
| 4518 | `a066bdbdf625b7efe98fdf84bf4a8c64fe5f6eb0` | `proposals/4518-registries.md` | `d070a21fe3d793a3f8f2088b9a00937a4b6e43118eccd502fcac09a0650c3a7b` | MATCH |

The manifest profile fingerprint is separately recomputed from canonical compact sorted-key JSON of the nested `profile` object. Proposal source hashes are inputs to that fingerprint; source verification does not imply proposal acceptance, SDK implementation, deployment support, or interoperability.

The exact pinned MSC4195 source includes the authenticated federation API `POST /_matrix/federation/v1/rtc/livekit/get_token`; the authoritative manifest and human contract record that route alongside the client token and delegated-leave APIs.
