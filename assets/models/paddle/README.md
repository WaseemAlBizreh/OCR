# PaddleOCR ONNX models

Converted by us from the official PaddlePaddle weights (Apache-2.0):

| File | Source | Notes |
|---|---|---|
| `idlens_det_v1.onnx` | `PaddlePaddle/PP-OCRv5_mobile_det` (Hugging Face) | DB text detector. Input `x` NCHW float, dynamic H/W. Normalise with ImageNet mean/std on BGR; DB thresh 0.3, box_thresh 0.6, unclip 1.5. |
| `idlens_arabic_rec_v1.onnx` | `PaddlePaddle/arabic_PP-OCRv5_mobile_rec` (Hugging Face) | CTC recognizer. Input `x` = [N,3,48,W]; output [N,T,749] = blank + 747 dict chars + space. Normalise `(px/255 - 0.5)/0.5`. |
| `idlens_arabic_dict_v1.txt` | `character_dict` from the recognizer's `inference.yml` | 747 lines; append a space entry after loading. |

Conversion: `paddle2onnx 2.1.0` (Python 3.11), `--opset_version 14`, from `inference.json` + `inference.pdiparams`.

SHA-256:
```
d5de5df358366210d16419b9636a2fc1efa5d7a20688f38a7869ec7b1a4f4f7d  idlens_det_v1.onnx
55841e0f5adc377112e11718855b81039468d8f8580248262be61fc8887d11a2  idlens_arabic_rec_v1.onnx
7f92f7dbb9b75a4787a83bfb4f6d14a8ab515525130c9d40a9036f61cf6999e9  idlens_arabic_dict_v1.txt
```

Not yet validated on real Sudanese cards.

The files carry a version suffix on purpose: `flutter_onnxruntime` copies each
model to the app's temp folder under its file name and reuses it on later
runs, so a changed model must get a new name or old installs keep the old file.
