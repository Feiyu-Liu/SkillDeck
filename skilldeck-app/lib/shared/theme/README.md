# Design system

The app follows a layered token model:

- `app_colors.dart` owns global palette and semantic colors.
- `app_typography.dart` owns font families and reusable text roles.
- `app_metrics.dart` owns spacing, control sizes, insets, and radii.
- `app_corners.dart` exposes reusable border-radius shapes.
- `app_shadows.dart` owns the small set of elevation recipes.
- `app_theme.dart` is the public barrel and configures `CupertinoThemeData`.

Neutral primitives stay private to `AppColors`. Feature widgets consume
semantic roles such as `surfaceMuted`, `controlInactive`, `textSecondary`, and
`borderStrong` rather than numbered gray values.

Feature-specific visual meaning stays with the feature. For example, Skills
source and agent accent colors live in
`features/skills/presentation/skills_design_tokens.dart`.

Widgets should import `app_theme.dart`, use semantic names, and reuse shared
Cupertino controls before introducing a feature-local control.
