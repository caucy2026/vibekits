# Native inference test assets

These files are committed only for deterministic Windows native-inference tests. They are not copied into the Vibekits Release bundle or offered as built-in user models.

| File | Upstream | License / purpose | SHA-256 |
|---|---|---|---|
| `models/silero_vad.onnx` | [sherpa-onnx `asr-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx) | Silero VAD, MIT; sherpa-compatible regression model | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` |
| `models/silero_vad_v6.onnx` | [Silero VAD pinned commit `76e3dc4`](https://github.com/snakers4/silero-vad/blob/76e3dc408eb2a5c655c34e230d2d5459b4439daa/src/silero_vad/data/silero_vad.onnx) | Silero VAD v6, MIT; current-model regression | `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3` |
| `audio/lei-jun-test.wav` | [sherpa-onnx `asr-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/lei-jun-test.wav) | Official upstream VAD/ASR test input; non-empty real-audio regression | `ad12c2ee3b2d60ad5214d22e8a3e9002f1bad9c61f60c4b404ee206d60a66ded` |
| `models/ppocrv6_tiny/det.onnx` | [PaddlePaddle PP-OCRv6 tiny detection ONNX](https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx) | Apache-2.0; real OCR detection regression | `193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8` |
| `models/ppocrv6_tiny/rec.onnx` | [PaddlePaddle PP-OCRv6 tiny recognition ONNX](https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx) | Apache-2.0; multilingual OCR regression | `9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6` |
| `models/ppocrv6_tiny/rec.yml` | [PaddlePaddle PP-OCRv6 tiny recognition config](https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx/blob/main/inference.yml) | Apache-2.0; pinned multilingual character dictionary | `66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1` |
| `images/general_ocr_002.png` | [PaddleOCR official test image](https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/general_ocr_002.png) | Official upstream boarding-pass OCR regression | `4425af33dd163cf73bdff502bd35ee527e9bdd5725501db1da78bfdae9f538f4` |
| `archives/rarlng.rar` | [RARLAB official WinRAR language package](https://www.rarlab.com/rar/rarlng.rar) | Public official RAR5 package; real list/selective-extract regression | `f737051e98e60cc0921351241ec92b5732c623468f0698fcaf50eb6fb5c57e2d` |

The application’s curated download catalog independently pins model URL, expected byte size, license label, and SHA-256. A failed download or digest mismatch is never imported into the model store.
