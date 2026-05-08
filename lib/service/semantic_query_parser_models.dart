/// 语义查询解析模型，描述解析结果、路由状态和候选条件。

part of 'semantic_query_parser_service.dart';

class _CoarseSeed {
  const _CoarseSeed({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.aliases,
    required this.prototypePrompt,
    required this.shortPrompts,
  });

  final String id;
  final String labelZh;
  final String labelEn;
  final List<String> aliases;
  final String prototypePrompt;
  final List<String> shortPrompts;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label_zh': labelZh,
      'label_en': labelEn,
      'aliases': aliases,
      'prototype_prompt': prototypePrompt,
      'short_prompts': shortPrompts,
    };
  }
}
