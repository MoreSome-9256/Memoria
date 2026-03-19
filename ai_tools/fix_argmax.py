import onnx

model_path = "assets/mobileclip2/s2/text_model.onnx"
output_path = "assets/mobileclip2/s2/text_model_fixed.onnx"

model = onnx.load(model_path)
fixed = 0
for node in model.graph.node:
    if node.op_type == 'ArgMax':
        new_attrs = [attr for attr in node.attribute if attr.name == 'axis']
        node.attribute.clear()
        node.attribute.extend(new_attrs)
        print(f"已切除 ArgMax 冗余属性，剩余: {[a.name for a in node.attribute]}")
        fixed += 1

onnx.save(model, output_path)
print(f"修复了 {fixed} 个 ArgMax 节点 -> {output_path}")

# 验证
m2 = onnx.load(output_path)
for node in m2.graph.node:
    if node.op_type == 'ArgMax':
        print(f"修复后 ArgMax attrs: {[f'{a.name}:{a.i}' for a in node.attribute]}")
