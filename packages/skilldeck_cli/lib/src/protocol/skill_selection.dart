/// Selection intent only. Resolution belongs to the running App.
final class SkillSelection {
  SkillSelection({
    List<String> refs = const [],
    List<String> tags = const [],
    this.untagged = false,
    this.favorite = false,
    this.sourcePrefix,
    this.activeFor,
    this.projectPath,
    this.hasUpdate = false,
    this.all = false,
  }) : refs = List.unmodifiable(refs),
       tags = List.unmodifiable(tags);

  final List<String> refs;
  final List<String> tags;
  final bool untagged;
  final bool favorite;
  final String? sourcePrefix;
  final String? activeFor;
  final String? projectPath;
  final bool hasUpdate;
  final bool all;

  bool get hasFilters =>
      tags.isNotEmpty ||
      untagged ||
      favorite ||
      sourcePrefix != null ||
      activeFor != null ||
      projectPath != null ||
      hasUpdate;
  bool get isEmpty => refs.isEmpty && !hasFilters && !all;

  factory SkillSelection.fromJson(Map<String, Object?> json) => SkillSelection(
    refs: (json['refs'] as List<Object?>? ?? const []).cast<String>(),
    tags: (json['tags'] as List<Object?>? ?? const []).cast<String>(),
    untagged: json['untagged'] as bool? ?? false,
    favorite: json['favorite'] as bool? ?? false,
    sourcePrefix: json['sourcePrefix'] as String?,
    activeFor: json['activeFor'] as String?,
    projectPath: json['projectPath'] as String?,
    hasUpdate: json['hasUpdate'] as bool? ?? false,
    all: json['all'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'refs': refs,
    'tags': tags,
    'untagged': untagged,
    'favorite': favorite,
    if (sourcePrefix != null) 'sourcePrefix': sourcePrefix,
    if (activeFor != null) 'activeFor': activeFor,
    if (projectPath != null) 'projectPath': projectPath,
    'hasUpdate': hasUpdate,
    'all': all,
  };
}
