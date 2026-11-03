# VITS AISHELL3 offline speech resource

Source archive: https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-zh-aishell3.tar.bz2
Model card: https://huggingface.co/csukuangfj/vits-zh-aishell3
Upstream training weights: https://huggingface.co/jackyqs/vits-aishell3-175-chinese
ONNX conversion and lexicon generation: https://github.com/csukuangfj/vits_chinese
Runtime: sherpa-onnx 1.13.8, https://github.com/k2-fsa/sherpa-onnx (Apache-2.0).

The original archive is split losslessly into five pack.* assets (146,922,607
bytes total). manifest.json records every part and runtime file SHA-256.
Preparation validates the archive, extracts only the seven whitelisted runtime
files, and validates those files before they can be loaded by native inference.
The archive also retains upstream int8 and FAR variants; they are not extracted.

Measured runtime format: 8,000 Hz mono, 174 speaker IDs (0–173).
Role assignment is a reader preference; a numeric speaker ID is not a verified
gender label. Unknown dialogue names use stable alternating role assignment.
This is a speech synthesis model, not a local text-generation language model.
