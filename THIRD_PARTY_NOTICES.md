# Third-party notices

First-party code is GPL-3.0-or-later. Third-party material retains the terms
identified below. This is an inventory, not a legal opinion or a claim that
every release artifact has been inspected.

## Source distribution

### Vendored libgit2 and incorporated material

Paths below are relative to `packages/skills_workspace/native/third_party/libgit2/`.
Unless a separate version is stated, material is pinned by libgit2 v1.9.7,
commit `49e408b3208bc3093757a1c2db938d3590f3f412`; see
`packages/skills_workspace/native/libgit2.lock.json` for the archive SHA-256.
`COPYING` contains the full terms and copyright notices listed below.

| Component and path | License | Copyright holder | Text |
| --- | --- | --- | --- |
| libgit2, repository root | GPL-2.0-only with libgit2 linking exception | libgit2 contributors | `COPYING`, `AUTHORS` |
| xdiff, `deps/xdiff/` | LGPL-2.1-or-later; some files retain libgit2 terms | Davide Libenzi, Johannes E. Schindelin, Google Inc., libgit2 contributors | individual source headers; `COPYING` (LGPL text) |
| zlib, `deps/zlib/` | Zlib | Jean-loup Gailly and Mark Adler | `deps/zlib/LICENSE`, `COPYING` |
| PCRE2, `deps/pcre2/` | BSD-3-Clause, with binary exemption; JIT BSD-2-Clause | University of Cambridge, Philip Hazel, Zoltan Herczeg, other contributors | `COPYING` |
| llhttp, `deps/llhttp/` | MIT | Fedor Indutny | `deps/llhttp/LICENSE-MIT`, `COPYING` |
| SHA1 collision detection, `src/util/hash/sha1dc/` | MIT | Marc Stevens, Dan Shumow | `COPYING` |
| wildmatch, `src/util/wildmatch.c` | LicenseRef-wildmatch | Rich Salz | `COPYING` |
| ntlmclient, `deps/ntlmclient/` | MIT | Edward Thomson | `COPYING` |
| WinHTTP compatibility definitions, `deps/winhttp/` | LGPL-2.1-or-later | Francois Gouget | `COPYING`, `deps/winhttp/COPYING.LGPL` |
| Clar test framework | ISC | Vicent Marti | `COPYING` |
| OpenSSL header portions | OpenSSL and SSLeay | Eric Young, OpenSSL Project | `COPYING` |
| xoroshiro256** | CC0-1.0 | David Blackman and Sebastiano Vigna | `COPYING` |
| RFC 6234 SHA-256, `src/util/hash/rfc6234/` | BSD-3-Clause | IETF Trust and authors | `COPYING` |
| Android basename implementation | BSD-3-Clause | Android Open Source Project | `COPYING` |
| Team Explorer Everywhere portions | MIT | Microsoft Corporation | `COPYING` |
| LLVM portions | NCSA | University of Illinois at Urbana-Champaign | `COPYING` |
| Unicode portions | Unicode license; exact SPDX identifier unverified | Unicode, Inc. | `COPYING` |
| sheredom/utf8.h portions | Unlicense | contributors | `COPYING` |
| RFC 1320 MD4 portions | LicenseRef-RSA-MD4 | RSA Data Security, Inc. | `COPYING` |

The `COPYING` file and individual source headers remain authoritative. The
vendored tree also contains examples, tests and fixtures; their individual
provenance and license coverage are **unverified**.
`deps/chromium-zlib/` contains a CMake recipe that can fetch Chromium zlib
at `2c183c9f93a328bfb3121284da13cf89a0f7e64a`; that optional source is not
vendored and is not selected by the locked build.

### SQLite native asset

`sqlite3` Dart package 3.5.2 defaults to the ordinary SQLite precompiled asset
from release `sqlite3-3.5.2`; its cached hook source
`lib/src/hook/asset_hashes.dart` specifies the following expected SHA-256s.
SQLite is public domain (SQLite authors; no copyright claimed); see
<https://sqlite.org/copyright.html> and `skilldeck-app/assets/licenses/sqlite.txt`.
These are expected download hashes, not hashes measured on release bundles.
The SQLite core version and actual released bytes are **unverified**.

| Target | Hook asset | Expected SHA-256 |
| --- | --- | --- |
| macOS arm64 | `libsqlite3.arm64.macos.dylib` | `6d80ba56cff1fa44f62bebc3e6b6b71513cc628862a9745c223c7bea8bf813f3` |
| macOS x86_64 | `libsqlite3.x64.macos.dylib` | `4ee3335ce95e17c36e4002bfeede2a3b2f77d9ac8434d0b7ed421d3e2205b216` |
| Windows x64 | `sqlite3.x64.windows.dll` | `2bf39f2aadafdc59a90b260f582a8fccebc5b89eb94175fdbaa9148c1e1f084d` |

### Bundled application assets

| Path | Component, version/pin | License and holder | Text |
| --- | --- | --- | --- |
| `skilldeck-app/assets/fonts/NotoSansSC-Variable.ttf` | Noto Sans SC; embedded font version 2.004 | OFL-1.1; Adobe | `skilldeck-app/assets/licenses/noto-sans-sc.txt` |
| `skilldeck-app/assets/agent_icons/` | Lobe icons static SVG and PNG 1.94.0 (npm packages `@lobehub/icons-static-svg` and `@lobehub/icons-static-png`) | MIT; LobeHub | `skilldeck-app/assets/licenses/lobe-icons.txt` |
| `skilldeck-app/assets/fonts/Inter-Variable.ttf` | Inter 4.001, git-66647c0bb | OFL-1.1; The Inter Project Authors | `skilldeck-app/assets/licenses/ofl-1.1.txt`; font name table |
| `skilldeck-app/assets/fonts/JetBrainsMono-Variable.ttf` | JetBrains Mono 2.211 | OFL-1.1; The JetBrains Mono Project Authors | `skilldeck-app/assets/licenses/ofl-1.1.txt`; font name table |
| `skilldeck-app/assets/fonts/SpaceGrotesk-Variable.ttf` | Space Grotesk 2.000 | OFL-1.1; The Space Grotesk Project Authors | `skilldeck-app/assets/licenses/ofl-1.1.txt`; font name table |

Lobe icons 1.94.0 npm package integrity pins:

- `@lobehub/icons-static-svg`: `sha512-Inx1TYkjLH6YeHOIHeVW9+OM/xxRnk8TmcQVKquFUDBmE3X9sUuRGt7kALrrDBNNAbrWz7Qq6fAiFj9E9Mmw9Q==`
- `@lobehub/icons-static-png`: `sha512-UX+BolfzVoCaY5UJd+IvjmrxPfes1jbiHAsi3QadePnpjQlDLV6asLe4TTShws4MExsVhI7rAjR9Ah1j9f2sTQ==`

### Additional Agent icons (2026-11-10)

The `grok.svg`, `minimax.svg`, `minimax-color.svg`, `deepseek.svg`,
`deepseek-color.svg`, and `workbuddy.svg` files in
`skilldeck-app/assets/agent_icons/` are unmodified Lobe Icons static SVGs from
<https://github.com/lobehub/lobe-icons/tree/ea434b96e75813517b377825e01c0df61dee8836/packages/static-svg/icons>.
The matching `workbuddy-color.png` is the unmodified
`packages/static-png/light/workbuddy-color.png` from that same commit. The
raster variant preserves the color SVG's unsupported Gaussian-blur filter in
Flutter, following the existing Antigravity icon convention.
These files are distributed under the same MIT license and LobeHub attribution in
`skilldeck-app/assets/licenses/lobe-icons.txt`. The other icon assets retain
their previously recorded 1.94.0 provenance.

### vercel-labs/skills attribution

Compared against `vercel-labs/skills` commit
`435076e78988e1e6ec40d00b0b1d76bdbbc5419a`.

The built-in Agent catalog was additionally synchronized against commit
`26dc8e4755a11fea22ed788256c3db50001b013d` on 2026-11-10 (eight added IDs, including the two independent
conventions below; Droid/Kilo/Pi canonical-path changes are deferred). The
other files in this table retain the comparison baseline above.

Additional directory-convention references (no source implementation copied):

- DeepSeek Harness: official `deepseek-ai/deepseek-harness` commit
  `fcc0ad462172522aaf5c93a7b2e01f6b9f0b0159`,
  `packages/util/home-paths/src/index.ts` and
  `packages/skill/skill-filesystem/src/index.ts`.
- WorkBuddy domestic edition: `xingkongliang/skills-manager` commit
  `63bdf81ca3da0a27daa82aae431979507a8acb8b`,
  `src-tauri/src/core/tool_adapters.rs`. The default directory convention is
  modeled independently in Dart; runtime loading is not established by this
  source comparison. The overseas `.workbuddy-ai` edition is not registered.

| File (under `packages/skills_workspace/`) | Judgment and evidence |
| --- | --- |
| `lib/src/infrastructure/source/skill_discovery.dart` | Adapted: skip list and ordered Agent directories correspond to `src/skills.ts`, with subsequent differences. |
| `lib/src/application/agents/built_in_agent_definitions.dart` | Adapted: catalog, configuration keys, paths and fallback order correspond to `src/agents.ts`. |
| `lib/src/infrastructure/git_transport/git_source_parser.dart` | Adapted: source forms, fragments and parsing cases correspond to `src/source-parser.ts`, with project-specific validation. |
| `test/infrastructure/git_transport/git_source_parser_test.dart` | Adapted conformance cases compare with `src/source-parser.test.ts`; inputs and assertions exercise corresponding source forms. |
| `test/infrastructure/source/skill_discovery_test.dart` | Adapted discovery cases correspond to `src/skills.ts`; the local fixtures are constructed in the test. |
| `test/fixtures/non_git_without_system_git.dart` | Independent: exercises SkillDeck's missing-Git probe and local acquisition APIs; the reference parser tests do not contain this fixture. |

Other ADR-0050 conformance fixtures and tests have not all been individually
matched to upstream and their provenance is **unverified**.

```text
MIT License

Copyright (c) 2026 Vercel, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Extracted UI dependency

`next_ui` 0.1.0 replaces the private `my_ui` dependency. Its exact immutable
revision is recorded in `skilldeck-app/pubspec.lock`; the public Git pin is
`e91aa0399adadd38898f5658bfb4925e32b637c2`. Its source baseline was `my_ui`
`3dc634e3ed8221b9c5032a2122f47bdbde32f73e`, not the private working tree.
Original contributions are MIT (Feiyu-Liu), with full MIT text in the
package `LICENSE` and attribution in its `NOTICE`. The NeoButton/theme and
CapsuleTag adaptations retain ChunUI's MIT license, Copyright (c) 2026 liseami
(赵纯想), in `third_party/CHUNUI_LICENSE` and the App's
`assets/licenses/next-ui-notice.txt`. The App license registry includes that
notice and full MIT text in addition to Flutter's generated MIT entry.

The new package contains only the used controls and necessary support modules,
not private photos, examples, or Git history. Its public runtime dependencies
remain `progressive_blur` and `smooth_corner`; shader assets are supplied by
`progressive_blur`. The public source is
<https://github.com/Feiyu-Liu/next-ui>, consumed through an immutable HTTPS Git
pin without private credentials. See ADR-0116. This does not relicense any GPL
App code.

### Dart dependency snapshots

The tables below list hosted packages from the committed lock snapshots. The
translation package has no committed root lock; its example lock is shown
instead and does not prove the independent package resolution. Versions are
deduplicated in the master inventory. LICENSE refers to the exact-version
pub archive at https://pub.dev/api/archives/<name>-<version>.tar.gz.
The family is determined from the cached main LICENSE, not a file-by-file
SPDX audit. Unidentified holders are explicitly marked unverified.

#### `packages/skills_workspace/pubspec.lock`

| Hosted package | Version |
| --- | --- |
| `_fe_analyzer_shared` | `103.0.0` |
| `analyzer` | `13.3.0` |
| `archive` | `4.1.0` |
| `args` | `2.7.0` |
| `async` | `2.13.1` |
| `boolean_selector` | `2.1.2` |
| `build` | `4.0.10` |
| `build_config` | `1.3.2` |
| `build_daemon` | `4.1.5` |
| `build_runner` | `2.16.0` |
| `built_collection` | `5.1.1` |
| `built_value` | `8.12.7` |
| `canonical_json` | `1.1.3` |
| `charcode` | `1.4.0` |
| `checked_yaml` | `2.0.4` |
| `cli_config` | `0.2.0` |
| `cli_util` | `0.4.2` |
| `code_assets` | `1.2.1` |
| `collection` | `1.19.1` |
| `convert` | `3.1.2` |
| `coverage` | `1.15.1` |
| `crypto` | `3.0.7` |
| `dart_style` | `3.1.13` |
| `drift` | `2.34.3` |
| `drift_dev` | `2.34.5` |
| `ffi` | `2.2.0` |
| `ffi_leak_tracker` | `0.1.2` |
| `ffigen` | `21.0.0` |
| `file` | `7.0.1` |
| `fixnum` | `1.1.1` |
| `flutter_lints` | `6.0.0` |
| `frontend_server_client` | `4.0.0` |
| `glob` | `2.1.3` |
| `graphs` | `2.3.2` |
| `hooks` | `2.0.2` |
| `http` | `1.6.0` |
| `http_multi_server` | `3.2.2` |
| `http_parser` | `4.1.2` |
| `io` | `1.0.5` |
| `json_annotation` | `4.12.0` |
| `lints` | `6.1.0` |
| `logging` | `1.3.0` |
| `matcher` | `0.12.20` |
| `meta` | `1.19.0` |
| `mime` | `2.0.0` |
| `native_toolchain_c` | `0.19.1` |
| `node_preamble` | `2.0.2` |
| `package_config` | `2.2.0` |
| `path` | `1.9.1` |
| `pool` | `1.5.2` |
| `posix` | `6.5.2` |
| `pub_semver` | `2.2.0` |
| `pubspec_parse` | `1.5.0` |
| `quiver` | `3.2.2` |
| `recase` | `4.1.0` |
| `record_use` | `0.6.0` |
| `shelf` | `1.4.2` |
| `shelf_packages_handler` | `3.0.2` |
| `shelf_static` | `1.1.3` |
| `shelf_web_socket` | `3.0.0` |
| `source_gen` | `4.2.4` |
| `source_map_stack_trace` | `2.1.2` |
| `source_maps` | `0.10.14` |
| `source_span` | `1.10.2` |
| `sqlite3` | `3.5.2` |
| `sqlparser` | `0.45.0` |
| `stack_trace` | `1.12.1` |
| `stream_channel` | `2.1.4` |
| `stream_transform` | `2.1.1` |
| `string_scanner` | `1.4.1` |
| `term_glyph` | `1.2.2` |
| `test` | `1.31.2` |
| `test_api` | `0.7.13` |
| `test_core` | `0.6.19` |
| `typed_data` | `1.4.0` |
| `unorm_dart` | `0.3.2` |
| `uuid` | `4.6.0` |
| `vm_service` | `15.3.0` |
| `watcher` | `1.2.1` |
| `web` | `1.1.1` |
| `web_socket` | `1.0.1` |
| `web_socket_channel` | `3.0.3` |
| `webkit_inspection_protocol` | `1.2.1` |
| `win32` | `6.4.0` |
| `yaml` | `3.1.3` |
| `yaml_edit` | `2.2.4` |

#### `packages/skills_translation/example/pubspec.lock`

| Hosted package | Version |
| --- | --- |
| `async` | `2.13.1` |
| `boolean_selector` | `2.1.2` |
| `characters` | `1.4.1` |
| `clock` | `1.1.3` |
| `collection` | `1.19.1` |
| `cross_file` | `0.3.5+5` |
| `crypto` | `3.0.7` |
| `cupertino_icons` | `1.0.9` |
| `dio` | `5.9.2` |
| `dio_web_adapter` | `2.2.2` |
| `fake_async` | `1.3.3` |
| `ffi` | `2.2.0` |
| `file_selector` | `1.0.3` |
| `file_selector_android` | `0.5.2+11` |
| `file_selector_ios` | `0.5.3+6` |
| `file_selector_linux` | `0.9.4+1` |
| `file_selector_macos` | `0.9.5+1` |
| `file_selector_platform_interface` | `2.7.0` |
| `file_selector_web` | `0.9.5` |
| `file_selector_windows` | `0.9.3+6` |
| `flutter_lints` | `5.0.0` |
| `highlight` | `0.7.0` |
| `http` | `1.6.0` |
| `http_parser` | `4.1.2` |
| `leak_tracker` | `11.0.2` |
| `leak_tracker_flutter_testing` | `3.0.10` |
| `leak_tracker_testing` | `3.0.2` |
| `lints` | `5.1.1` |
| `logging` | `1.3.0` |
| `matcher` | `0.12.20` |
| `material_color_utilities` | `0.13.0` |
| `meta` | `1.19.0` |
| `mime` | `2.1.0` |
| `path` | `1.9.1` |
| `plugin_platform_interface` | `2.1.8` |
| `source_span` | `1.10.2` |
| `stack_trace` | `1.12.2` |
| `stream_channel` | `2.1.4` |
| `string_scanner` | `1.4.1` |
| `term_glyph` | `1.2.2` |
| `test_api` | `0.7.12` |
| `typed_data` | `1.4.0` |
| `vector_math` | `2.4.3` |
| `vm_service` | `15.3.0` |
| `web` | `1.1.1` |
| `yaml` | `3.1.4` |

#### `packages/skilldeck_cli/pubspec.lock`

| Hosted package | Version |
| --- | --- |
| `_fe_analyzer_shared` | `109.0.0` |
| `analyzer` | `14.5.0` |
| `args` | `2.7.0` |
| `async` | `2.13.1` |
| `boolean_selector` | `2.1.2` |
| `cli_config` | `0.2.0` |
| `cli_util` | `0.6.0` |
| `collection` | `1.19.1` |
| `convert` | `3.1.2` |
| `coverage` | `1.16.0` |
| `crypto` | `3.0.7` |
| `ffi` | `2.2.0` |
| `file` | `7.0.1` |
| `frontend_server_client` | `4.1.0` |
| `glob` | `2.2.0` |
| `http_multi_server` | `3.2.2` |
| `http_parser` | `4.1.2` |
| `io` | `1.1.0` |
| `lints` | `6.1.0` |
| `logging` | `1.3.0` |
| `matcher` | `0.12.20` |
| `meta` | `1.19.0` |
| `mime` | `2.1.0` |
| `node_preamble` | `2.0.2` |
| `package_config` | `3.0.0` |
| `path` | `1.9.1` |
| `pool` | `1.5.3` |
| `pub_semver` | `2.2.1` |
| `shelf` | `1.4.3` |
| `shelf_packages_handler` | `3.0.2` |
| `shelf_static` | `1.2.0` |
| `shelf_web_socket` | `3.0.0` |
| `source_map_stack_trace` | `2.1.2` |
| `source_maps` | `0.10.14` |
| `source_span` | `1.10.2` |
| `stack_trace` | `1.12.2` |
| `stream_channel` | `2.1.4` |
| `string_scanner` | `1.4.1` |
| `term_glyph` | `1.2.2` |
| `test` | `1.33.0` |
| `test_api` | `0.7.15` |
| `test_core` | `0.6.21` |
| `typed_data` | `1.4.0` |
| `vm_service` | `15.4.0` |
| `watcher` | `1.2.1` |
| `web` | `1.1.1` |
| `web_socket` | `1.0.1` |
| `web_socket_channel` | `3.0.3` |
| `webkit_inspection_protocol` | `1.2.1` |
| `yaml` | `3.1.4` |

#### `skilldeck-app/pubspec.lock`

| Hosted package | Version |
| --- | --- |
| `archive` | `4.1.0` |
| `args` | `2.7.0` |
| `async` | `2.13.1` |
| `boolean_selector` | `2.1.2` |
| `canonical_json` | `1.1.3` |
| `characters` | `1.4.1` |
| `checked_yaml` | `2.0.4` |
| `cli_util` | `0.4.2` |
| `clock` | `1.1.3` |
| `cnativeapi` | `0.3.0` |
| `code_assets` | `1.2.1` |
| `collection` | `1.19.1` |
| `convert` | `3.1.2` |
| `cross_file` | `0.3.5+5` |
| `crypto` | `3.0.7` |
| `cupertino_icons` | `1.0.9` |
| `device_info_plus` | `13.2.0` |
| `device_info_plus_platform_interface` | `8.1.0` |
| `dio` | `5.9.2` |
| `dio_web_adapter` | `2.2.2` |
| `drift` | `2.34.3` |
| `equatable` | `2.1.0` |
| `fake_async` | `1.3.3` |
| `ffi` | `2.2.0` |
| `ffi_leak_tracker` | `0.1.2` |
| `file` | `7.0.1` |
| `file_selector` | `1.1.0` |
| `file_selector_android` | `0.5.2+11` |
| `file_selector_ios` | `0.5.3+6` |
| `file_selector_linux` | `0.9.4+1` |
| `file_selector_macos` | `0.9.5+1` |
| `file_selector_platform_interface` | `2.7.0` |
| `file_selector_web` | `0.9.5` |
| `file_selector_windows` | `0.9.3+6` |
| `fixnum` | `1.1.1` |
| `flutter_launcher_icons` | `0.14.4` |
| `flutter_lints` | `6.0.0` |
| `flutter_riverpod` | `3.4.3` |
| `flutter_secure_storage` | `11.0.0` |
| `flutter_secure_storage_darwin` | `0.4.3` |
| `flutter_secure_storage_linux` | `3.0.3` |
| `flutter_secure_storage_platform_interface` | `2.1.1` |
| `flutter_secure_storage_web` | `2.1.1` |
| `flutter_secure_storage_windows` | `4.2.2` |
| `flutter_shaders` | `0.1.3` |
| `flutter_svg` | `2.3.0` |
| `glob` | `2.2.0` |
| `go_router` | `17.5.0` |
| `highlight` | `0.7.0` |
| `hooks` | `2.0.2` |
| `http` | `1.6.0` |
| `http_parser` | `4.1.2` |
| `image` | `4.10.1` |
| `intl` | `0.20.3` |
| `jni` | `1.0.3` |
| `jni_flutter` | `1.0.3` |
| `jni_util` | `1.0.0` |
| `json_annotation` | `4.12.0` |
| `leak_tracker` | `11.0.2` |
| `leak_tracker_flutter_testing` | `3.0.10` |
| `leak_tracker_testing` | `3.0.2` |
| `lints` | `6.1.0` |
| `listen` | `1.0.1` |
| `logging` | `1.3.0` |
| `lucide_icons_flutter` | `3.1.20` |
| `matcher` | `0.12.20` |
| `material_color_utilities` | `0.13.0` |
| `matomo_tracker` | `6.1.1` |
| `meta` | `1.19.0` |
| `mime` | `2.1.0` |
| `native_toolchain_c` | `0.19.1` |
| `nativeapi` | `0.3.0` |
| `objective_c` | `9.5.0` |
| `package_config` | `3.0.0` |
| `package_info_plus` | `10.2.1` |
| `package_info_plus_platform_interface` | `4.1.0` |
| `path` | `1.9.1` |
| `path_parsing` | `1.1.0` |
| `path_provider` | `2.1.6` |
| `path_provider_android` | `2.3.1` |
| `path_provider_foundation` | `2.6.0` |
| `path_provider_linux` | `2.2.2` |
| `path_provider_platform_interface` | `2.1.3` |
| `path_provider_windows` | `2.3.0` |
| `pausable_timer` | `3.1.0+3` |
| `petitparser` | `7.0.2` |
| `platform` | `3.2.0` |
| `plugin_platform_interface` | `2.1.8` |
| `posix` | `6.5.2` |
| `process` | `5.0.6` |
| `progressive_blur` | `0.0.2` |
| `pub_semver` | `2.2.1` |
| `record_use` | `0.6.0` |
| `riverpod` | `3.4.3` |
| `screen_retriever` | `0.2.2` |
| `screen_retriever_linux` | `0.2.2` |
| `screen_retriever_macos` | `0.2.2` |
| `screen_retriever_platform_interface` | `0.2.2` |
| `screen_retriever_windows` | `0.2.2` |
| `scroll_animator` | `0.3.0` |
| `shared_preferences` | `2.5.5` |
| `shared_preferences_android` | `2.4.28` |
| `shared_preferences_foundation` | `2.5.7` |
| `shared_preferences_linux` | `2.4.1` |
| `shared_preferences_platform_interface` | `2.4.2` |
| `shared_preferences_web` | `2.4.3` |
| `shared_preferences_windows` | `2.4.1` |
| `shimmer_animation` | `2.2.2+1` |
| `smooth_corner` | `1.1.1` |
| `source_span` | `1.10.2` |
| `sqlite3` | `3.5.2` |
| `stack_trace` | `1.12.2` |
| `state_notifier` | `1.0.0` |
| `stream_channel` | `2.1.4` |
| `string_scanner` | `1.4.1` |
| `sync_http` | `0.3.1` |
| `term_glyph` | `1.2.2` |
| `test_api` | `0.7.12` |
| `toastification` | `3.2.0` |
| `tray_manager` | `0.7.0` |
| `typed_data` | `1.4.0` |
| `unorm_dart` | `0.3.2` |
| `url_launcher` | `6.3.2` |
| `url_launcher_android` | `6.3.33` |
| `url_launcher_ios` | `6.4.2` |
| `url_launcher_linux` | `3.2.3` |
| `url_launcher_macos` | `3.2.6` |
| `url_launcher_platform_interface` | `2.3.2` |
| `url_launcher_web` | `2.4.3` |
| `url_launcher_windows` | `3.1.6` |
| `uuid` | `4.6.0` |
| `vector_graphics` | `1.2.3` |
| `vector_graphics_codec` | `1.1.13` |
| `vector_graphics_compiler` | `1.3.0` |
| `vector_math` | `2.4.3` |
| `vm_service` | `15.3.0` |
| `web` | `1.1.1` |
| `webdriver` | `3.2.0` |
| `win32` | `6.4.0` |
| `win32_registry` | `3.0.3` |
| `window_manager` | `0.5.2` |
| `xdg_directories` | `1.1.0` |
| `xml` | `7.0.1` |
| `yaml` | `3.1.4` |

#### Deduplicated hosted package license inventory

| Package | Version | Main LICENSE family | Copyright in main LICENSE | License text |
| --- | --- | --- | --- | --- |
| `_fe_analyzer_shared` | `103.0.0` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/_fe_analyzer_shared-103.0.0.tar.gz) in exact-version archive |
| `_fe_analyzer_shared` | `109.0.0` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/_fe_analyzer_shared-109.0.0.tar.gz) in exact-version archive |
| `analyzer` | `13.3.0` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/analyzer-13.3.0.tar.gz) in exact-version archive |
| `analyzer` | `14.5.0` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/analyzer-14.5.0.tar.gz) in exact-version archive |
| `archive` | `4.1.0` | MIT family | Copyright (c) 2013-2021 Brendan Duncan. | [LICENSE](https://pub.dev/api/archives/archive-4.1.0.tar.gz) in exact-version archive |
| `args` | `2.7.0` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/args-2.7.0.tar.gz) in exact-version archive |
| `async` | `2.13.1` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/async-2.13.1.tar.gz) in exact-version archive |
| `boolean_selector` | `2.1.2` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/boolean_selector-2.1.2.tar.gz) in exact-version archive |
| `build` | `4.0.10` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/build-4.0.10.tar.gz) in exact-version archive |
| `build_config` | `1.3.2` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/build_config-1.3.2.tar.gz) in exact-version archive |
| `build_daemon` | `4.1.5` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/build_daemon-4.1.5.tar.gz) in exact-version archive |
| `build_runner` | `2.16.0` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/build_runner-2.16.0.tar.gz) in exact-version archive |
| `built_collection` | `5.1.1` | BSD family | Copyright 2015, Google Inc. All rights reserved. | [LICENSE](https://pub.dev/api/archives/built_collection-5.1.1.tar.gz) in exact-version archive |
| `built_value` | `8.12.7` | BSD family | Copyright 2015, Google Inc. All rights reserved. | [LICENSE](https://pub.dev/api/archives/built_value-8.12.7.tar.gz) in exact-version archive |
| `canonical_json` | `1.1.3` | Apache-2.0 | Google LLC (source headers) | [LICENSE](https://pub.dev/api/archives/canonical_json-1.1.3.tar.gz) in exact-version archive |
| `characters` | `1.4.1` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/characters-1.4.1.tar.gz) in exact-version archive |
| `charcode` | `1.4.0` | BSD family | Copyright 2014, the Dart project authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/charcode-1.4.0.tar.gz) in exact-version archive |
| `checked_yaml` | `2.0.4` | BSD family | Copyright 2019, the Dart project authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/checked_yaml-2.0.4.tar.gz) in exact-version archive |
| `cli_config` | `0.2.0` | BSD family | Copyright 2023, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/cli_config-0.2.0.tar.gz) in exact-version archive |
| `cli_util` | `0.4.2` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/cli_util-0.4.2.tar.gz) in exact-version archive |
| `cli_util` | `0.6.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/cli_util-0.6.0.tar.gz) in exact-version archive |
| `clock` | `1.1.3` | Apache-2.0 | Google Inc. (source headers) | [LICENSE](https://pub.dev/api/archives/clock-1.1.3.tar.gz) in exact-version archive |
| `cnativeapi` | `0.3.0` | MIT family | Copyright (c) 2025 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/cnativeapi-0.3.0.tar.gz) in exact-version archive |
| `code_assets` | `1.2.1` | BSD family | Copyright 2025, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/code_assets-1.2.1.tar.gz) in exact-version archive |
| `collection` | `1.19.1` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/collection-1.19.1.tar.gz) in exact-version archive |
| `convert` | `3.1.2` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/convert-3.1.2.tar.gz) in exact-version archive |
| `coverage` | `1.15.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/coverage-1.15.1.tar.gz) in exact-version archive |
| `coverage` | `1.16.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/coverage-1.16.0.tar.gz) in exact-version archive |
| `cross_file` | `0.3.5+5` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/cross_file-0.3.5+5.tar.gz) in exact-version archive |
| `crypto` | `3.0.7` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/crypto-3.0.7.tar.gz) in exact-version archive |
| `cupertino_icons` | `1.0.9` | MIT family | Copyright (c) 2016 Vladimir Kharlampidi | [LICENSE](https://pub.dev/api/archives/cupertino_icons-1.0.9.tar.gz) in exact-version archive |
| `dart_style` | `3.1.13` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/dart_style-3.1.13.tar.gz) in exact-version archive |
| `device_info_plus` | `13.2.0` | BSD family | Copyright 2017 The Chromium Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/device_info_plus-13.2.0.tar.gz) in exact-version archive |
| `device_info_plus_platform_interface` | `8.1.0` | BSD family | Copyright 2017 The Chromium Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/device_info_plus_platform_interface-8.1.0.tar.gz) in exact-version archive |
| `dio` | `5.9.2` | MIT family | Copyright (c) 2018 Wen Du (wendux) | [LICENSE](https://pub.dev/api/archives/dio-5.9.2.tar.gz) in exact-version archive |
| `dio_web_adapter` | `2.2.2` | MIT family | Copyright (c) 2018 Wen Du (wendux) | [LICENSE](https://pub.dev/api/archives/dio_web_adapter-2.2.2.tar.gz) in exact-version archive |
| `drift` | `2.34.3` | MIT family | Copyright (c) 2021 Simon Binder | [LICENSE](https://pub.dev/api/archives/drift-2.34.3.tar.gz) in exact-version archive |
| `drift_dev` | `2.34.5` | MIT family | Copyright (c) 2021 Simon Binder | [LICENSE](https://pub.dev/api/archives/drift_dev-2.34.5.tar.gz) in exact-version archive |
| `equatable` | `2.1.0` | MIT family | Copyright (c) 2026 Felix Angelov | [LICENSE](https://pub.dev/api/archives/equatable-2.1.0.tar.gz) in exact-version archive |
| `fake_async` | `1.3.3` | Apache-2.0 | Google Inc. (source headers) | [LICENSE](https://pub.dev/api/archives/fake_async-1.3.3.tar.gz) in exact-version archive |
| `ffi` | `2.2.0` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/ffi-2.2.0.tar.gz) in exact-version archive |
| `ffi_leak_tracker` | `0.1.2` | BSD family | Copyright (c) 2026, Halil Durmus | [LICENSE](https://pub.dev/api/archives/ffi_leak_tracker-0.1.2.tar.gz) in exact-version archive |
| `ffigen` | `21.0.0` | BSD family | Copyright 2020, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/ffigen-21.0.0.tar.gz) in exact-version archive |
| `file` | `7.0.1` | BSD family | Copyright 2017, the Dart project authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/file-7.0.1.tar.gz) in exact-version archive |
| `file_selector` | `1.0.3` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/file_selector-1.0.3.tar.gz) in exact-version archive |
| `file_selector` | `1.1.0` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector-1.1.0.tar.gz) in exact-version archive |
| `file_selector_android` | `0.5.2+11` | Apache-2.0 | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_android-0.5.2+11.tar.gz) in exact-version archive |
| `file_selector_ios` | `0.5.3+6` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_ios-0.5.3+6.tar.gz) in exact-version archive |
| `file_selector_linux` | `0.9.4+1` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_linux-0.9.4+1.tar.gz) in exact-version archive |
| `file_selector_macos` | `0.9.5+1` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_macos-0.9.5+1.tar.gz) in exact-version archive |
| `file_selector_platform_interface` | `2.7.0` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_platform_interface-2.7.0.tar.gz) in exact-version archive |
| `file_selector_web` | `0.9.5` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_web-0.9.5.tar.gz) in exact-version archive |
| `file_selector_windows` | `0.9.3+6` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/file_selector_windows-0.9.3+6.tar.gz) in exact-version archive |
| `fixnum` | `1.1.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/fixnum-1.1.1.tar.gz) in exact-version archive |
| `flutter_launcher_icons` | `0.14.4` | MIT family | Copyright (c) 2019 Mark O'Sullivan | [LICENSE](https://pub.dev/api/archives/flutter_launcher_icons-0.14.4.tar.gz) in exact-version archive |
| `flutter_lints` | `5.0.0` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/flutter_lints-5.0.0.tar.gz) in exact-version archive |
| `flutter_lints` | `6.0.0` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/flutter_lints-6.0.0.tar.gz) in exact-version archive |
| `flutter_riverpod` | `3.4.3` | MIT family | Copyright (c) 2020 Remi Rousselet | [LICENSE](https://pub.dev/api/archives/flutter_riverpod-3.4.3.tar.gz) in exact-version archive |
| `flutter_secure_storage` | `11.0.0` | BSD family | Copyright 2017 German Saprykin | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage-11.0.0.tar.gz) in exact-version archive |
| `flutter_secure_storage_darwin` | `0.4.3` | BSD family | Copyright 2025 Julian Steenbakker | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage_darwin-0.4.3.tar.gz) in exact-version archive |
| `flutter_secure_storage_linux` | `3.0.3` | BSD family | Copyright 2017 German Saprykin | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage_linux-3.0.3.tar.gz) in exact-version archive |
| `flutter_secure_storage_platform_interface` | `2.1.1` | BSD family | Copyright 2017 German Saprykin | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage_platform_interface-2.1.1.tar.gz) in exact-version archive |
| `flutter_secure_storage_web` | `2.1.1` | BSD family | Copyright 2017 German Saprykin | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage_web-2.1.1.tar.gz) in exact-version archive |
| `flutter_secure_storage_windows` | `4.2.2` | BSD family | Copyright 2017 German Saprykin | [LICENSE](https://pub.dev/api/archives/flutter_secure_storage_windows-4.2.2.tar.gz) in exact-version archive |
| `flutter_shaders` | `0.1.3` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/flutter_shaders-0.1.3.tar.gz) in exact-version archive |
| `flutter_svg` | `2.3.0` | MIT family | Copyright (c) 2018 Dan Field | [LICENSE](https://pub.dev/api/archives/flutter_svg-2.3.0.tar.gz) in exact-version archive |
| `frontend_server_client` | `4.0.0` | BSD family | Copyright 2020, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/frontend_server_client-4.0.0.tar.gz) in exact-version archive |
| `frontend_server_client` | `4.1.0` | BSD family | Copyright 2012, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/frontend_server_client-4.1.0.tar.gz) in exact-version archive |
| `glob` | `2.1.3` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/glob-2.1.3.tar.gz) in exact-version archive |
| `glob` | `2.2.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/glob-2.2.0.tar.gz) in exact-version archive |
| `go_router` | `17.5.0` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/go_router-17.5.0.tar.gz) in exact-version archive |
| `graphs` | `2.3.2` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/graphs-2.3.2.tar.gz) in exact-version archive |
| `highlight` | `0.7.0` | MIT family | Copyright (c) 2019 Rongjian Zhang | [LICENSE](https://pub.dev/api/archives/highlight-0.7.0.tar.gz) in exact-version archive |
| `hooks` | `2.0.2` | BSD family | Copyright 2025, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/hooks-2.0.2.tar.gz) in exact-version archive |
| `http` | `1.6.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/http-1.6.0.tar.gz) in exact-version archive |
| `http_multi_server` | `3.2.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/http_multi_server-3.2.2.tar.gz) in exact-version archive |
| `http_parser` | `4.1.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/http_parser-4.1.2.tar.gz) in exact-version archive |
| `image` | `4.10.1` | MIT family | Copyright (c) 2013-2022 Brendan Duncan. | [LICENSE](https://pub.dev/api/archives/image-4.10.1.tar.gz) in exact-version archive |
| `intl` | `0.20.3` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/intl-0.20.3.tar.gz) in exact-version archive |
| `io` | `1.0.5` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/io-1.0.5.tar.gz) in exact-version archive |
| `io` | `1.1.0` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/io-1.1.0.tar.gz) in exact-version archive |
| `jni` | `1.0.3` | BSD family | Copyright 2022, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/jni-1.0.3.tar.gz) in exact-version archive |
| `jni_flutter` | `1.0.3` | BSD family | Copyright 2026, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/jni_flutter-1.0.3.tar.gz) in exact-version archive |
| `jni_util` | `1.0.0` | BSD family | Copyright 2026, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/jni_util-1.0.0.tar.gz) in exact-version archive |
| `json_annotation` | `4.12.0` | BSD family | Copyright 2017, the Dart project authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/json_annotation-4.12.0.tar.gz) in exact-version archive |
| `leak_tracker` | `11.0.2` | BSD family | Copyright 2022, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/leak_tracker-11.0.2.tar.gz) in exact-version archive |
| `leak_tracker_flutter_testing` | `3.0.10` | BSD family | Copyright 2022, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/leak_tracker_flutter_testing-3.0.10.tar.gz) in exact-version archive |
| `leak_tracker_testing` | `3.0.2` | BSD family | Copyright 2022, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/leak_tracker_testing-3.0.2.tar.gz) in exact-version archive |
| `lints` | `5.1.1` | BSD family | Copyright 2021, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/lints-5.1.1.tar.gz) in exact-version archive |
| `lints` | `6.1.0` | BSD family | Copyright 2021, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/lints-6.1.0.tar.gz) in exact-version archive |
| `listen` | `1.0.1` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/listen-1.0.1.tar.gz) in exact-version archive |
| `logging` | `1.3.0` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/logging-1.3.0.tar.gz) in exact-version archive |
| `lucide_icons_flutter` | `3.1.20` | MIT family | Copyright (c) 2024 vqhapp | [LICENSE](https://pub.dev/api/archives/lucide_icons_flutter-3.1.20.tar.gz) in exact-version archive |
| `matcher` | `0.12.20` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/matcher-0.12.20.tar.gz) in exact-version archive |
| `material_color_utilities` | `0.13.0` | Apache-2.0 | Copyright 2021 Google LLC | [LICENSE](https://pub.dev/api/archives/material_color_utilities-0.13.0.tar.gz) in exact-version archive |
| `matomo_tracker` | `6.1.1` | MIT family | Copyright (c) 2020 Jêrôme Poichet | [LICENSE](https://pub.dev/api/archives/matomo_tracker-6.1.1.tar.gz) in exact-version archive |
| `meta` | `1.19.0` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/meta-1.19.0.tar.gz) in exact-version archive |
| `mime` | `2.0.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/mime-2.0.0.tar.gz) in exact-version archive |
| `mime` | `2.1.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/mime-2.1.0.tar.gz) in exact-version archive |
| `native_toolchain_c` | `0.19.1` | BSD family | Copyright 2023, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/native_toolchain_c-0.19.1.tar.gz) in exact-version archive |
| `nativeapi` | `0.3.0` | MIT family | Copyright (c) 2025 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/nativeapi-0.3.0.tar.gz) in exact-version archive |
| `node_preamble` | `2.0.2` | MIT family | Copyright (c) 2015 Michael Bullington | [LICENSE](https://pub.dev/api/archives/node_preamble-2.0.2.tar.gz) in exact-version archive |
| `objective_c` | `9.5.0` | BSD family | Copyright 2024, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/objective_c-9.5.0.tar.gz) in exact-version archive |
| `package_config` | `2.2.0` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/package_config-2.2.0.tar.gz) in exact-version archive |
| `package_config` | `3.0.0` | BSD family | Copyright 2019, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/package_config-3.0.0.tar.gz) in exact-version archive |
| `package_info_plus` | `10.2.1` | BSD family | Copyright 2017 The Chromium Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/package_info_plus-10.2.1.tar.gz) in exact-version archive |
| `package_info_plus_platform_interface` | `4.1.0` | BSD family | Copyright 2017 The Chromium Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/package_info_plus_platform_interface-4.1.0.tar.gz) in exact-version archive |
| `path` | `1.9.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/path-1.9.1.tar.gz) in exact-version archive |
| `path_parsing` | `1.1.0` | MIT family | Copyright (c) 2018 Dan Field | [LICENSE](https://pub.dev/api/archives/path_parsing-1.1.0.tar.gz) in exact-version archive |
| `path_provider` | `2.1.6` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/path_provider-2.1.6.tar.gz) in exact-version archive |
| `path_provider_android` | `2.3.1` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/path_provider_android-2.3.1.tar.gz) in exact-version archive |
| `path_provider_foundation` | `2.6.0` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/path_provider_foundation-2.6.0.tar.gz) in exact-version archive |
| `path_provider_linux` | `2.2.2` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/path_provider_linux-2.2.2.tar.gz) in exact-version archive |
| `path_provider_platform_interface` | `2.1.3` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/path_provider_platform_interface-2.1.3.tar.gz) in exact-version archive |
| `path_provider_windows` | `2.3.0` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/path_provider_windows-2.3.0.tar.gz) in exact-version archive |
| `pausable_timer` | `3.1.0+3` | BSD family | Copyright (c) 2020, Google LLC. | [LICENSE](https://pub.dev/api/archives/pausable_timer-3.1.0+3.tar.gz) in exact-version archive |
| `petitparser` | `7.0.2` | MIT family | Copyright (c) 2006-2024 Lukas Renggli. | [LICENSE](https://pub.dev/api/archives/petitparser-7.0.2.tar.gz) in exact-version archive |
| `platform` | `3.2.0` | BSD family | Copyright 2017, the Dart project authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/platform-3.2.0.tar.gz) in exact-version archive |
| `plugin_platform_interface` | `2.1.8` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/plugin_platform_interface-2.1.8.tar.gz) in exact-version archive |
| `pool` | `1.5.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/pool-1.5.2.tar.gz) in exact-version archive |
| `pool` | `1.5.3` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/pool-1.5.3.tar.gz) in exact-version archive |
| `posix` | `6.5.2` | MIT family | Copyright (c) 2020 Brett Sutton | [LICENSE](https://pub.dev/api/archives/posix-6.5.2.tar.gz) in exact-version archive |
| `process` | `5.0.6` | BSD family | Copyright 2013, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/process-5.0.6.tar.gz) in exact-version archive |
| `progressive_blur` | `0.0.2` | MIT family | Copyright 2025 Erzhan Kabdykairov | [LICENSE](https://pub.dev/api/archives/progressive_blur-0.0.2.tar.gz) in exact-version archive |
| `pub_semver` | `2.2.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/pub_semver-2.2.0.tar.gz) in exact-version archive |
| `pub_semver` | `2.2.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/pub_semver-2.2.1.tar.gz) in exact-version archive |
| `pubspec_parse` | `1.5.0` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/pubspec_parse-1.5.0.tar.gz) in exact-version archive |
| `quiver` | `3.2.2` | Apache-2.0 | Google Inc. (NOTICE) | [LICENSE](https://pub.dev/api/archives/quiver-3.2.2.tar.gz) and NOTICE in exact-version archive |
| `recase` | `4.1.0` | BSD family | Copyright 2017 Keith Elliott | [LICENSE](https://pub.dev/api/archives/recase-4.1.0.tar.gz) in exact-version archive |
| `record_use` | `0.6.0` | BSD family | Copyright 2024, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/record_use-0.6.0.tar.gz) in exact-version archive |
| `riverpod` | `3.4.3` | MIT family | Copyright (c) 2020 Remi Rousselet | [LICENSE](https://pub.dev/api/archives/riverpod-3.4.3.tar.gz) in exact-version archive |
| `screen_retriever` | `0.2.2` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/screen_retriever-0.2.2.tar.gz) in exact-version archive |
| `screen_retriever_linux` | `0.2.2` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/screen_retriever_linux-0.2.2.tar.gz) in exact-version archive |
| `screen_retriever_macos` | `0.2.2` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/screen_retriever_macos-0.2.2.tar.gz) in exact-version archive |
| `screen_retriever_platform_interface` | `0.2.2` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/screen_retriever_platform_interface-0.2.2.tar.gz) in exact-version archive |
| `screen_retriever_windows` | `0.2.2` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/screen_retriever_windows-0.2.2.tar.gz) in exact-version archive |
| `scroll_animator` | `0.3.0` | BSD family | Copyright 2024 Kamil Szczęk | [LICENSE](https://pub.dev/api/archives/scroll_animator-0.3.0.tar.gz) in exact-version archive |
| `shared_preferences` | `2.5.5` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/shared_preferences-2.5.5.tar.gz) in exact-version archive |
| `shared_preferences_android` | `2.4.28` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/shared_preferences_android-2.4.28.tar.gz) in exact-version archive |
| `shared_preferences_foundation` | `2.5.7` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/shared_preferences_foundation-2.5.7.tar.gz) in exact-version archive |
| `shared_preferences_linux` | `2.4.1` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/shared_preferences_linux-2.4.1.tar.gz) in exact-version archive |
| `shared_preferences_platform_interface` | `2.4.2` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/shared_preferences_platform_interface-2.4.2.tar.gz) in exact-version archive |
| `shared_preferences_web` | `2.4.3` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/shared_preferences_web-2.4.3.tar.gz) in exact-version archive |
| `shared_preferences_windows` | `2.4.1` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/shared_preferences_windows-2.4.1.tar.gz) in exact-version archive |
| `shelf` | `1.4.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf-1.4.2.tar.gz) in exact-version archive |
| `shelf` | `1.4.3` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf-1.4.3.tar.gz) in exact-version archive |
| `shelf_packages_handler` | `3.0.2` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf_packages_handler-3.0.2.tar.gz) in exact-version archive |
| `shelf_static` | `1.1.3` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf_static-1.1.3.tar.gz) in exact-version archive |
| `shelf_static` | `1.2.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf_static-1.2.0.tar.gz) in exact-version archive |
| `shelf_web_socket` | `3.0.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/shelf_web_socket-3.0.0.tar.gz) in exact-version archive |
| `shimmer_animation` | `2.2.2+1` | MIT family | Copyright (c) 2020 Madhav Baveja | [LICENSE](https://pub.dev/api/archives/shimmer_animation-2.2.2+1.tar.gz) in exact-version archive |
| `smooth_corner` | `1.1.1` | BSD family | Copyright (c) 2021, Hosea Tao | [LICENSE](https://pub.dev/api/archives/smooth_corner-1.1.1.tar.gz) in exact-version archive |
| `source_gen` | `4.2.4` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/source_gen-4.2.4.tar.gz) in exact-version archive |
| `source_map_stack_trace` | `2.1.2` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/source_map_stack_trace-2.1.2.tar.gz) in exact-version archive |
| `source_maps` | `0.10.14` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/source_maps-0.10.14.tar.gz) in exact-version archive |
| `source_span` | `1.10.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/source_span-1.10.2.tar.gz) in exact-version archive |
| `sqlite3` | `3.5.2` | MIT family | Copyright (c) 2020 Simon Binder | [LICENSE](https://pub.dev/api/archives/sqlite3-3.5.2.tar.gz) in exact-version archive |
| `sqlparser` | `0.45.0` | MIT family | Copyright (c) 2019 Simon Binder | [LICENSE](https://pub.dev/api/archives/sqlparser-0.45.0.tar.gz) in exact-version archive |
| `stack_trace` | `1.12.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/stack_trace-1.12.1.tar.gz) in exact-version archive |
| `stack_trace` | `1.12.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/stack_trace-1.12.2.tar.gz) in exact-version archive |
| `state_notifier` | `1.0.0` | MIT family | Copyright (c) 2020 Remi Rousselet | [LICENSE](https://pub.dev/api/archives/state_notifier-1.0.0.tar.gz) in exact-version archive |
| `stream_channel` | `2.1.4` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/stream_channel-2.1.4.tar.gz) in exact-version archive |
| `stream_transform` | `2.1.1` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/stream_transform-2.1.1.tar.gz) in exact-version archive |
| `string_scanner` | `1.4.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/string_scanner-1.4.1.tar.gz) in exact-version archive |
| `sync_http` | `0.3.1` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/sync_http-0.3.1.tar.gz) in exact-version archive |
| `term_glyph` | `1.2.2` | BSD family | Copyright 2017, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/term_glyph-1.2.2.tar.gz) in exact-version archive |
| `test` | `1.31.2` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test-1.31.2.tar.gz) in exact-version archive |
| `test` | `1.33.0` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test-1.33.0.tar.gz) in exact-version archive |
| `test_api` | `0.7.12` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test_api-0.7.12.tar.gz) in exact-version archive |
| `test_api` | `0.7.13` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test_api-0.7.13.tar.gz) in exact-version archive |
| `test_api` | `0.7.15` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test_api-0.7.15.tar.gz) in exact-version archive |
| `test_core` | `0.6.19` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test_core-0.6.19.tar.gz) in exact-version archive |
| `test_core` | `0.6.21` | BSD family | Copyright 2018, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/test_core-0.6.21.tar.gz) in exact-version archive |
| `toastification` | `3.2.0` | BSD family | Copyright (c) 2023, Payam Zahedi | [LICENSE](https://pub.dev/api/archives/toastification-3.2.0.tar.gz) in exact-version archive |
| `tray_manager` | `0.7.0` | MIT family | Copyright (c) 2022-2024 LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/tray_manager-0.7.0.tar.gz) in exact-version archive |
| `typed_data` | `1.4.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/typed_data-1.4.0.tar.gz) in exact-version archive |
| `unorm_dart` | `0.3.2` | MIT family | Copyright (c) 2018 Yasuhiro Shimizu <the.phantom.bane@gmail.com> | [LICENSE](https://pub.dev/api/archives/unorm_dart-0.3.2.tar.gz) in exact-version archive |
| `url_launcher` | `6.3.2` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/url_launcher-6.3.2.tar.gz) in exact-version archive |
| `url_launcher_android` | `6.3.33` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_android-6.3.33.tar.gz) in exact-version archive |
| `url_launcher_ios` | `6.4.2` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_ios-6.4.2.tar.gz) in exact-version archive |
| `url_launcher_linux` | `3.2.3` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_linux-3.2.3.tar.gz) in exact-version archive |
| `url_launcher_macos` | `3.2.6` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_macos-3.2.6.tar.gz) in exact-version archive |
| `url_launcher_platform_interface` | `2.3.2` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/url_launcher_platform_interface-2.3.2.tar.gz) in exact-version archive |
| `url_launcher_web` | `2.4.3` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_web-2.4.3.tar.gz) in exact-version archive |
| `url_launcher_windows` | `3.1.6` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/url_launcher_windows-3.1.6.tar.gz) in exact-version archive |
| `uuid` | `4.6.0` | MIT family | Copyright (c) 2021 Yulian Kuncheff | [LICENSE](https://pub.dev/api/archives/uuid-4.6.0.tar.gz) in exact-version archive |
| `vector_graphics` | `1.2.3` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/vector_graphics-1.2.3.tar.gz) in exact-version archive |
| `vector_graphics_codec` | `1.1.13` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/vector_graphics_codec-1.1.13.tar.gz) in exact-version archive |
| `vector_graphics_compiler` | `1.3.0` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/vector_graphics_compiler-1.3.0.tar.gz) in exact-version archive |
| `vector_math` | `2.4.3` | BSD family | Copyright 2013 The Flutter Authors | [LICENSE](https://pub.dev/api/archives/vector_math-2.4.3.tar.gz) in exact-version archive |
| `vm_service` | `15.3.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/vm_service-15.3.0.tar.gz) in exact-version archive |
| `vm_service` | `15.4.0` | BSD family | Copyright 2015, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/vm_service-15.4.0.tar.gz) in exact-version archive |
| `watcher` | `1.2.1` | BSD family | Copyright 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/watcher-1.2.1.tar.gz) in exact-version archive |
| `web` | `1.1.1` | BSD family | Copyright 2023, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/web-1.1.1.tar.gz) in exact-version archive |
| `web_socket` | `1.0.1` | BSD family | Copyright 2024, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/web_socket-1.0.1.tar.gz) in exact-version archive |
| `web_socket_channel` | `3.0.3` | BSD family | Copyright 2016, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/web_socket_channel-3.0.3.tar.gz) in exact-version archive |
| `webdriver` | `3.2.0` | Apache-2.0 | Copyright 2013 Google LLC | [LICENSE](https://pub.dev/api/archives/webdriver-3.2.0.tar.gz) in exact-version archive |
| `webkit_inspection_protocol` | `1.2.1` | BSD family | Copyright 2013, Google Inc. | [LICENSE](https://pub.dev/api/archives/webkit_inspection_protocol-1.2.1.tar.gz) in exact-version archive |
| `win32` | `6.4.0` | BSD family | Copyright (c) 2024, Halil Durmus | [LICENSE](https://pub.dev/api/archives/win32-6.4.0.tar.gz) in exact-version archive |
| `win32_registry` | `3.0.3` | BSD family | Copyright (c) 2023, Halil Durmus | [LICENSE](https://pub.dev/api/archives/win32_registry-3.0.3.tar.gz) in exact-version archive |
| `window_manager` | `0.5.2` | MIT family | Copyright (c) 2022-present LiJianying <lijy91@foxmail.com> | [LICENSE](https://pub.dev/api/archives/window_manager-0.5.2.tar.gz) in exact-version archive |
| `xdg_directories` | `1.1.0` | BSD family | Copyright 2013 The Flutter Authors. All rights reserved. | [LICENSE](https://pub.dev/api/archives/xdg_directories-1.1.0.tar.gz) in exact-version archive |
| `xml` | `7.0.1` | MIT family | Copyright (c) 2006-2026 Lukas Renggli. | [LICENSE](https://pub.dev/api/archives/xml-7.0.1.tar.gz) in exact-version archive |
| `yaml` | `3.1.3` | MIT family | Copyright (c) 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/yaml-3.1.3.tar.gz) in exact-version archive |
| `yaml` | `3.1.4` | MIT family | Copyright (c) 2014, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/yaml-3.1.4.tar.gz) in exact-version archive |
| `yaml_edit` | `2.2.4` | BSD family | Copyright 2020, the Dart project authors. | [LICENSE](https://pub.dev/api/archives/yaml_edit-2.2.4.tar.gz) in exact-version archive |

[`archive 4.1.0/LICENSE-other.md`](https://pub.dev/api/archives/archive-4.1.0.tar.gz)
contains additional zlib.js, JZlib, bzip2 and PointyCastle notices;
[`quiver 3.2.2/NOTICE`](https://pub.dev/api/archives/quiver-3.2.2.tar.gz)
contains its additional Apache notice.
They are present in the corresponding exact-version pub archives. Main-license
classification does not establish the licenses of every embedded source file.

## Per-binary distribution

The following follows the locked CMake options and selectors, not a link-map
or inspection of signed artifacts. Final object retention and bundle contents
are **unverified** for all three targets.

| Release target | Package-owned native asset | SQLite | System TLS |
| --- | --- | --- | --- |
| macOS arm64 | libgit2 plus xdiff, zlib, PCRE2, llhttp, SHA1 collision detection, built-in RFC 6234 SHA-256 and libgit2's incorporated code, including wildmatch | default arm64 SQLite asset above | SecureTransport, Security and CoreFoundation |
| macOS x86_64 | Same selected native components | default x64 SQLite asset above | SecureTransport, Security and CoreFoundation |
| Windows x64 (MSVC) | Same selected native components | default Windows x64 SQLite asset above | Windows WinHTTP and system crypto APIs |

The xdiff objects are unconditional in `cmake/SelectXdiff.cmake`. The lock
enables bundled zlib, builtin PCRE2 and llhttp, collision-detection SHA1 and
builtin SHA256. `USE_NTLMCLIENT=OFF`; Wine WinHTTP compatibility definitions
are only selected by the MinGW branch of `SelectHTTPSBackend.cmake`, not MSVC.
System TLS is not a bundled third-party TLS library. Actual SQLite selection,
linker dead-stripping and the binary presence of individual incorporated
fragments require release-artifact verification.

## Compliance determinations

Made in-house on 2026-11-04 at the maintainer's decision; no outside counsel
was consulted.

- **xdiff (LGPL-2.1-or-later), statically linked into the package-owned
  native library.** Kept under LGPL-2.1 as received and complied with under
  its section 6. Each copy of the App states that xdiff is used and shows the
  LGPL text, in the licenses dialog under Settings > About and in this file;
  every release publishes a source archive of the exact release commit next
  to the binaries in the same release location (section 6(d)), in addition
  to the public GPL-3.0-or-later repository; and the App's own license
  permits modification and reverse engineering for debugging, as the section
  requires. The archive is part of the release process from the first public
  release.
- **libgit2 project patches (GPLv2 section 2(a)).** Each modified file
  carries a header stating that the SkillDeck project changed it, the date,
  and the change; `packages/skills_workspace/native/libgit2.lock.json` and the
  package's `THIRD_PARTY_NOTICES.md` describe the patches. This is the notice
  the section asks for.
