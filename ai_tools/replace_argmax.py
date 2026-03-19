"""
Replace the ArgMax node in text_model.onnx with an equivalent subgraph
using only ops that ORT 1.4.1 mobile build definitely supports:
  Cast / ReduceMax / Equal / Mul / Unsqueeze / Constant

For CLIP text input [batch, 77] int64:
  argmax(axis=1)  ≡  ReduceMax( mask * range )
  where mask = Equal(input_f, ReduceMax(input_f, axis=1, keepdims=1))
"""
import numpy as np
import onnx
from onnx import helper, TensorProto, numpy_helper

model_path  = "assets/mobileclip2/s2/text_model.onnx"
output_path = "assets/mobileclip2/s2/text_model_noargmax.onnx"

model = onnx.load(model_path)
graph = model.graph

# ── locate ArgMax ─────────────────────────────────────────────────────────────
argmax_node = next((n for n in graph.node if n.op_type == "ArgMax"), None)
if argmax_node is None:
    print("No ArgMax found – nothing to do.")
    exit(0)

# Read axis (default 0 per spec, but CLIP uses -1 / last dim = 1 for [B,77])
raw_axis = 0
for attr in argmax_node.attribute:
    if attr.name == "axis":
        raw_axis = attr.i
        break
# Materialise negative axis for a rank-2 tensor
axis = raw_axis if raw_axis >= 0 else 2 + raw_axis   # → 1

src  = argmax_node.input[0]   # e.g. "input_ids"  shape [B, 77] int64
dst  = argmax_node.output[0]  # shape [B] int64
print(f"ArgMax: input={src!r}  output={dst!r}  axis={axis}")

SEQ_LEN = 77  # CLIP context length

# ── build replacement nodes ───────────────────────────────────────────────────
range_arr = np.arange(SEQ_LEN, dtype=np.float32)

replacement = [
    # Constant range [0,1,...,76]
    helper.make_node(
        "Constant", inputs=[], outputs=["_am_range"],
        value=numpy_helper.from_array(range_arr, name="_am_range_val"),
    ),
    # [77] → [1, 77]  (opset-12 form: axes as attribute)
    helper.make_node("Unsqueeze", inputs=["_am_range"], outputs=["_am_range2d"], axes=[0]),
    # int64 → float32
    helper.make_node("Cast", inputs=[src], outputs=["_am_in_f"], to=TensorProto.FLOAT),
    # max value per row  [B,1]
    helper.make_node(
        "ReduceMax", inputs=["_am_in_f"], outputs=["_am_maxval"],
        axes=[axis], keepdims=1,
    ),
    # boolean mask: True where value == max  [B,77]
    helper.make_node("Equal", inputs=["_am_in_f", "_am_maxval"], outputs=["_am_mask_b"]),
    # bool → float  [B,77]
    helper.make_node("Cast", inputs=["_am_mask_b"], outputs=["_am_mask_f"], to=TensorProto.FLOAT),
    # weight by index  [B,77] * [1,77] = [B,77]
    helper.make_node("Mul", inputs=["_am_mask_f", "_am_range2d"], outputs=["_am_weighted"]),
    # pick max index as float  [B]
    helper.make_node(
        "ReduceMax", inputs=["_am_weighted"], outputs=["_am_idx_f"],
        axes=[axis], keepdims=0,
    ),
    # float → int64  [B]
    helper.make_node("Cast", inputs=["_am_idx_f"], outputs=[dst], to=TensorProto.INT64),
]

# ── splice into graph ─────────────────────────────────────────────────────────
graph.node.remove(argmax_node)
graph.node.extend(replacement)

# Bump opset if needed (should stay 12)
onnx.save(model, output_path)
print(f"Saved: {output_path}")

# Quick sanity check
m2 = onnx.load(output_path)
remaining = [n.op_type for n in m2.graph.node if n.op_type == "ArgMax"]
print(f"ArgMax nodes remaining: {len(remaining)}  (should be 0)")
ops_added = {n.op_type for n in m2.graph.node} - {n.op_type for n in model.graph.node}
print(f"New op types introduced: {ops_added}")
