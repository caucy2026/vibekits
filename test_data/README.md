# Native inference test assets

These files are committed only for deterministic Windows native-inference tests. They are not copied into the Vibekits Release bundle or offered as built-in user models.

| File | Upstream | License / purpose | SHA-256 |
|---|---|---|---|
| `models/silero_vad.onnx` | [sherpa-onnx `asr-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx) | Silero VAD, MIT; sherpa-compatible regression model | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` |
| `models/silero_vad_v6.onnx` | [Silero VAD pinned commit `76e3dc4`](https://github.com/snakers4/silero-vad/blob/76e3dc408eb2a5c655c34e230d2d5459b4439daa/src/silero_vad/data/silero_vad.onnx) | Silero VAD v6, MIT; current-model regression | `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3` |
| `audio/lei-jun-test.wav` | [sherpa-onnx `asr-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/lei-jun-test.wav) | Official upstream VAD/ASR test input; non-empty real-audio regression | `ad12c2ee3b2d60ad5214d22e8a3e9002f1bad9c61f60c4b404ee206d60a66ded` |

The application’s curated download catalog independently pins model URL, expected byte size, license label, and SHA-256. A failed download or digest mismatch is never imported into the model store.
