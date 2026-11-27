import '../application/library/personal_tag_name.dart';
import '../domain/public_models.dart';

/// The Workspace identity key for matching tag names.
extension PersonalTagName on PersonalTag {
  String get normalizedName => normalizePersonalTagName(name).key;
}
