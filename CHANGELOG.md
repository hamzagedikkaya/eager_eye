# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.2] - 2026-07-09


### Fixed

- **Unparseable files are reported once, by name — not as raw parser dumps.**
  A file the parser gem cannot lex (e.g. a model holding a binary string
  literal whose escapes are invalid UTF-8) used to trigger the default
  diagnostic consumer, which dumped a three-line error block to stderr on
  *every* analysis pass — three times per scan — labelled `(string):63` with
  no hint of which file was affected, while the file itself was silently
  dropped from analysis. All parsing now goes through the new
  `EagerEye::SourceParser` (quiet diagnostics, buffers named after the real
  file), and the analyzer emits a single clear line per file instead:
  `EagerEye: Skipped unparseable file app/models/coupon.rb: literal contains
  escape sequences incompatible with UTF-8`. Skipped files and their reasons
  are also exposed programmatically via `Analyzer#skipped_files` (reset on
  every `#run`). Unknown magic encoding comments (`# encoding: utf8` — a
  `Parser::UnknownEncodingInMagicComment`, which is an ArgumentError rather
  than a SyntaxError and previously crashed the whole run) are handled the
  same way, and an unparseable `db/schema.rb` now warns explicitly that
  schema-aware column checks are disabled instead of degrading precision in
  silence.
- **No more `parser/current` version-deviation warning.** EagerEye now
  requires the grammar matching the running Ruby's *minor* version
  (`parser/ruby33` on any 3.3.x) instead of `parser/current`, which insists
  on an exact patch match and warned on every load ("parser/current is
  loading parser/ruby33, which recognizes 3.3.4-compliant syntax, but you
  are running 3.3.1"). Grammar only changes between minor versions, so
  behaviour is identical; Rubies without a bundled grammar file fall back to
  `parser/current` as before.

## [1.3.1] - 2026-06-12

### Changed — precision (fewer false positives)

Validated against two large production apps (~1,080 hand-checked findings). These
changes cut false positives by ~53% (339 → 158) with near-zero recall loss
(5 findings), and lift the trustworthy detectors toward 100% precision.

- **Schema-aware column guard.** New `SchemaParser` reads `db/schema.rb` (found by
  walking up from the scanned path) to learn every table's real columns. When a
  receiver's model can't be inferred, a method whose name the schema knows as a
  column (`comsn_rate`, `vat_rate`, `service_fee_rate`) is no longer mistaken for
  an association/query method. `loop_association` and `custom_method_query` no
  longer flag column reads on unresolved receivers.
- **Per-iteration association dedup.** `loop_association` reports a memoized
  `belongs_to`/`has_one` read once per iteration instead of on every line — a
  repeated read hits Rails' instance cache, not the database. Associations used
  as a query-chain base (`x.assoc.find_by`, `x.assoc.where`) still report each
  occurrence, since those re-query.
- **Serializer render-site awareness.** New `SerializerUsageParser` scans render
  sites (`XxxBlueprint.render*`, AMS `(each_)serializer:`) and records, per
  serializer + Blueprinter view, which associations are eager-loaded and whether
  only single records are passed. `serializer_nesting` stays silent when an
  association is preloaded at every render site of that view, or the serializer
  is only ever handed single records. It never concludes "safe" for a view it
  can't see rendered, so genuine N+1s are preserved.
- **`custom_method_query` refinements.** Skips Enumerable aggregates with a block
  argument (`relation.sum(&:amount)`), per-batch queries inside
  `in_batches`/`find_in_batches`, and relation query methods called directly on a
  single iteration element (a SELECT alias such as `record.ids`, not a query).
- **`validation_n_plus_one`** ignores saves that skip validations
  (`save(validate: false)` / `create(..., validate: false)`).

### Added

- **`--baseline FILE` flag** — compare the current scan against a previously
  captured JSON report and surface only issues that are NOT in the baseline.
  Designed for the brownfield CI workflow: accept existing N+1s as the
  baseline, fail builds only on regressions (new issues introduced by a PR).
  Baseline files are produced by the existing `--format json` output (the
  flag accepts either the full report-shaped object or a bare array of
  issues). Malformed/missing baselines exit with a clear error message.
- **`EagerEye::Issue.from_h(hash)`** — public factory that rebuilds an
  `Issue` from its serialized form (e.g. a parsed JSON entry). Coerces
  `detector`/`severity` strings back to symbols and defaults severity to
  `:warning` when absent. Round-trips through `to_h` and `to_json`.
- **`EagerEye::Baseline`** — the helper behind `--baseline`. Loads issues
  from a JSON path (`Baseline.load_issues(path)`) and filters a current
  issue list against them (`Baseline.filter(issues, path)`). Useful
  programmatically for projects that wrap EagerEye in their own runner.

## [1.2.15] - 2026-05-01

### Fixed

- **Per-method scope for variable preload tracking** — `LoopAssociation` and
  `CustomMethodQuery` now process each `:def`/`:defs` body as an independent
  scope. Previously a later assignment in another method (e.g.
  `invoices = Invoice.includes(:invoice_items).where(...)` inside one action)
  could overwrite the preload set for the same variable name in an earlier
  action, producing false N+1 warnings on associations that were actually
  preloaded. Each scope now inherits a snapshot from the enclosing scope but
  its own writes do not leak back out.
- **Caller-method preload tracking** — `LoopAssociation` and
  `CustomMethodQuery` now propagate preload/model context across method calls
  within the same class. When `def index` does
  `items = Foo.includes(:bar); prepare_data(items)` and `def prepare_data(items)`
  iterates the parameter, the `:bar` association is now correctly recognized
  as preloaded. Previously every helper method that received a relation by
  parameter produced false positives because the parameter had no preload
  context.
- Sibling defs in the same scope are processed in two passes: first to capture
  each `self`-call's argument context, then to seed the callee's parameters
  before analyzing its body. Multiple call sites are merged permissively (any
  caller preloading suppresses the warning) to avoid false positives at the
  expense of potentially missing helpers that have BOTH preloaded and
  unpreloaded callers.

## [1.2.14] - 2026-05-01

### Fixed (false-positive reduction pass)

- **Pagy / multi-assignment preload tracking** — `LoopAssociation` and `CustomMethodQuery` now follow preloads through `@pagy, items = pagy(query)` patterns and through wrapper calls like `pagy(...)`, `paginate(...)`, etc. Previously the `.includes(...)` on the wrapped query was lost across the multi-assign, generating false N+1 warnings on every preloaded association.
- **Preloads through conditional / variable chains** — `extract_included_associations_deep` now walks ternary branches and inlined begin-blocks, and resolves `:lvar`/`:ivar` receivers via the variable preload map. `base = cond ? Q.includes(...).where(...) : Q.none` no longer drops preloads.
- **Per-model association scoping** — `LoopAssociation` now infers the model class of the iteration variable and, when known, only flags methods that are actually associations on that model. This eliminates false positives where column accessors collide with hardcoded names (e.g. `log.tag`, `log.image`) or with associations defined on unrelated models.
- **Per-model `method_queries` lookup** — `LoopAssociation` and `CustomMethodQuery` no longer flag `obj.foo` just because *some other* model defines a `def foo` containing a query. The match is scoped to the receiver's model when known, and association names on that model are excluded from the query-method check.
- **`update_all` / `delete_all` / `destroy_all` chains** — `LoopAssociation` no longer flags association access whose only purpose is a non-loading terminal write (e.g. `avm.merchant_branches.update_all(...)`), since these don't trigger a SELECT for the association.
- **`PluckToArray` `.where(...).all.pluck(:id)` mis-classification** — only an *unscoped* `.all.pluck(:id)` is escalated to error severity ("loads entire table"); chains scoped by `where`/`joins`/`limit`/etc. are no longer misreported as table-scans.

### Changed

- `AssociationParser` now exposes `associations_by_model` (a per-model `Set` of association names). Models with no declared associations are still registered, so detectors can distinguish "no associations" from "model unknown".
- Detector signatures: `LoopAssociation#detect` and `CustomMethodQuery#detect` accept an `associations_by_model` argument (defaults to `{}`).

## [1.2.13] - 2026-03-23

### Fixed

- Fixed gem packaging issue where `CountToSize` and `AddIncludes` auto-fixer files were missing from the published gem

## [1.2.12] - 2026-03-20

### Added

- **`.jbuilder` File Support** - Analyzer now scans `.jbuilder` files for N+1 queries
  - `json.array!` blocks are recognized as iteration patterns across all detectors
  - Existing detectors (LoopAssociation, CountInIteration, etc.) work seamlessly on jbuilder views
- **`CountToSize` Auto-fix** - Automatically replaces `.count` with `.size` inside iteration blocks
- **`AddIncludes` Auto-fix** - Suggests and applies `.includes(:association)` before iteration calls

## [1.2.11] - 2026-03-17

### Added

- **`each_with_object` / `reduce` / `inject` Support** - `LoopAssociation` and `CustomMethodQuery` detectors now recognize these iteration methods
  - `each_with_object` and `each_with_index` blocks are detected (item is first param)
  - `reduce` and `inject` blocks are detected with correct variable extraction (item is second param: `|memo, item|`)
  - `extract_iteration_variable` helper added to `Base` for reuse across detectors

## [1.2.10] - 2026-03-16

### Added

- **Cross-File Analysis** - Model methods containing queries are now detected when called from other files
  - New `MethodQueryParser` scans model files for methods that execute queries (`.where`, `.find_by`, `.count`, `.pluck`, etc.)
  - `LoopAssociation` detects cross-file query methods called inside loops (e.g. `user.active_orders` in a controller)
  - `CustomMethodQuery` detects model query methods called inside iterations
  - `SerializerNesting` detects model query methods called in serializer attribute blocks
  - `DecoratorNPlusOne` detects model query methods called in decorator methods
  - Two-pass architecture: first pass collects method signatures, second pass detects cross-file N+1 patterns

## [1.2.9] - 2026-03-13

### Changed

- **Dynamic Association Detection** - Association names are now automatically parsed from model files
  - `has_many`, `has_one`, `belongs_to`, `has_and_belongs_to_many` declarations are collected
  - Custom associations like `:enrollments`, `:subscriptions`, `:invoices` are now detected
  - Dynamic names supplement (not replace) the hardcoded fallback lists
  - Benefits `LoopAssociation`, `SerializerNesting`, `DecoratorNPlusOne`, and `MissingCounterCache`

## [1.2.8] - 2026-03-10

### Added

- **New Detector: `ValidationNPlusOne`** - Detects batch create/save inside iterations for models with uniqueness validations
  - Catches `User.create!(attrs)` and `User.new(attrs) + save!` patterns inside loops
  - Parses model files for `validates :attr, uniqueness: true` and `validates_uniqueness_of` declarations
  - Each uniqueness validation triggers a SELECT query per record — 2N queries total
  - Suggests using `insert_all` with unique index constraints or batch-validating before saving
- **New Parser: `ValidationParser`** - Collects models with uniqueness validations for cross-file detection

## [1.2.7] - 2026-03-10

### Added

- **New Detector: `ScopeChainNPlusOne`** - Detects scope calls on associations inside iterations
  - Catches `post.comments.recent`, `post.comments.approved.count` patterns
  - Parses model files for `scope :name, -> { ... }` declarations
  - Flags known scope names called on association chains inside loops
  - Each scope call executes a new query per iteration — suggests preloading or joined queries
- **New Parser: `ScopeParser`** - Collects scope definitions from model files for cross-file detection

## [1.2.6] - 2026-02-25

### Changed

- Extract shared class-inspection logic into `ClassInspector` concern to reduce duplication across detectors
- Refactor all detectors to use `ClassInspector` for parent class and naming convention checks
- Simplify `Analyzer` by removing redundant delegation and streamlining detector orchestration
- Clean up `DelegationParser` with leaner parsing logic
- Improve `Base` detector with consolidated helper methods
- Streamline reporter classes (`Base`, `Console`) for clarity and consistency

### Removed

- Remove duplicated class-matching code from `CallbackQuery`, `CountInIteration`, `CustomMethodQuery`, `DecoratorNPlusOne`, `DelegationNPlusOne`, `LoopAssociation`, and `SerializerNesting`

## [1.2.5] - 2026-02-21

### Added

- **New Detector: `DecoratorNPlusOne`** - Detects N+1 queries inside decorator/presenter classes
  - Catches `object.comments.map(...)`, `__getobj__.items.each { ... }`, `model.posts`, `source.tags` patterns
  - Identifies decorator classes by inheritance (`Draper::Decorator`, `SimpleDelegator`, `Delegator`) or name suffix (`Decorator`, `Presenter`, `ViewObject`)
  - Targets all four object reference styles: `object`, `__getobj__`, `source`, `model`
  - Skips ActiveStorage methods (`attached?`, `blob`, `variant`, etc.) to prevent false positives
  - Suggests eager loading in the controller before decorating the collection

## [1.2.4] - 2026-02-21

### Added

- **New Detector: `DelegationNPlusOne`** - Detects hidden N+1 queries caused by `delegate :method, to: :association`
  - `delegate :name, :email, to: :user` calls inside loops load the target association on each iteration
  - EagerEye previously could not catch these because `order.name` looks like a plain attribute, not an association access
  - Parses model files for `delegate` declarations and tracks delegated method → association mappings
  - Detects delegated method calls in `each`, `map`, `select`, `flat_map`, `find_each`, and all other iteration methods
  - Respects `includes`, `preload`, and `eager_load` — suppresses warnings when the target association is preloaded
  - Supports both local (same-file) delegate declarations and cross-file detection via model parsing

## [1.2.3] - 2026-02-15

### Added

- **Batch Iteration Support** - All detectors now recognize `find_each`, `find_in_batches`, and `in_batches`
  - `LoopAssociation`: Detects association calls inside `find_each` blocks
  - `CallbackQuery`: Detects query iterations inside `find_each` in callbacks
  - `MissingCounterCache`: Detects `.count`/`.size`/`.length` inside `find_each` blocks
  - `CountInIteration`: Detects `.count` inside `find_each` blocks
  - `CustomMethodQuery`: Detects `.where`/`.find_by` etc. inside `find_each` blocks
  - Previously, `User.find_each { |u| u.posts }` was not flagged — now correctly detected as N+1

## [1.2.2] - 2026-01-31

### Fixed

- **CustomMethodQuery False Positive** - Skip PostgreSQL array column methods
  - Methods ending with `_ids`, `_tags`, `_types`, `_codes`, `_names`, `_values` now recognized as array attributes
  - `sector_subcategory_ids.first` no longer flagged (Ruby Array#first, not AR query)

- **LoopAssociation False Positive** - Skip common non-association attribute methods
  - Added `origin`, `priority`, `level`, `kind`, `label`, `code`, `reason`, `amount`, `price`, `quantity`, `url`, `path`, `email`, `phone`, `address`, `notes`, `memo`, `data`, `metadata`, `position`, `rank`, `score`, `rating`, `enabled`, `disabled`, `active`, `published`, `draft`, `archived`, `locked`, `visible`, `hidden` to excluded methods
  - Note: `category` and `tag` remain detectable as they're common association names - use inline suppression if they're string attributes in your codebase

- **PluckToArray False Positive** - Skip params-originated values
  - `params[:ids].split(',').map(&:to_i)` no longer flagged
  - `params` method now recognized as non-ActiveRecord source

## [1.2.1] - 2026-01-31

### Fixed

- **PluckToArray False Positives** - Major improvements to reduce false positives:
  - Skip when variable is used in multiple places (e.g., for ordering with `array_position`)
  - Skip non-ActiveRecord sources: Sidekiq, Redis, Resque, DelayedJob
  - Skip `.to_sql` usage patterns (UNION queries can't use subqueries)
  - Skip non-AR `.where` receivers (Sidekiq::Queue, Redis, etc.)
  - Differentiate message between `.pluck()` and `.map(&:id)` patterns
  - Skip block maps like `.map { |u| u[:id] }` (likely Hash/Array access)

## [1.2.0] - 2026-01-18

### Features

- **Safer PluckToSelect Auto-fix** - Improved safety for `.pluck` to `.select` auto-fixer
  - Skips `info` severity issues (small collections like `statuses`, `types`) to preserve caching
  - Uses strict regex to ensure `.pluck` is inside `.where` arguments to prevent code breakage
  - Prevents unsafe replacements like `User.where(active: 1).pluck(:id)` → `select` (which changes return type)

## [1.1.13] - 2026-01-16

### Fixed

- **CustomMethodQuery False Positive** - Skip `.ids` on SQL alias attributes
  - `s_eod.ids` no longer flagged when `ids` is a SQL alias (e.g., `select('array_agg(...) AS ids')`)
  - Deep chains like `item.comments.ids` still correctly detected

## [1.1.12] - 2026-01-15

### Fixed

- **CustomMethodQuery Stack Overflow** - Fix infinite recursion in `collection_is_array?`
  - Added `visited` Set to track already-visited nodes and prevent cyclic traversal
  - Fixes `stack level too deep` error on complex method chains

## [1.1.11] - 2026-01-13

### Fixed

- **CustomMethodQuery False Positive** - Skip `count`, `sum`, `find` on safe collections
  - `id.to_s.count` no longer flagged (scalar count)
  - `array.count` no longer flagged inside iteration
  - Expanded safe transform methods (`to_s`, `to_i`, `to_a`, `chars`, `bytes`)

## [1.1.10] - 2026-01-12

### Fixed

- **CustomMethodQuery False Positive** - Skip `pluck` and `ids` results
  - `Model.pluck(:id).each { |id| ... }` no longer flagged
  - Supports tracking local variable assignments for pluck results

## [1.1.9] - 2026-01-11

### Fixed

- **CustomMethodQuery False Positive** - Skip `ActionController::Parameters` and Hash tuple access
  - `params.each { |p| p.last }` no longer flagged (tuple access)
  - `hash.each { |k, v| [k, v].last }` no longer flagged

## [1.1.8] - 2026-01-10

### Fixed

- **CustomMethodQuery False Positive** - Skip `[]` (bracket access) chains
  - `data["items"].first` no longer flagged as ActiveRecord query
  - Recognizes bracket access returns Array/Hash for subsequent enumerable calls

## [1.1.7] - 2026-01-09

### Fixed

- **CustomMethodQuery False Positive** - Skip `String#split` chains
  - `url.split("?").first` no longer flagged as ActiveRecord query

## [1.1.6] - 2026-01-09

### Fixed

- **CustomMethodQuery False Positive** - Skip `Hash#keys` and `Hash#values` chains
  - `hash.keys.first`, `hash.values.last` no longer flagged as ActiveRecord queries
  - Recognizes `keys` and `values` as Array-returning methods

## [1.1.5] - 2026-01-06

### Changed

- **PluckToArray Severity** - Lower severity to `info` for small collections
  - `tags`, `settings`, `roles`, `permissions`, `options` etc. now `info` level
  - Large collections remain `warning`, `.all.pluck` remains `error`

## [1.1.4] - 2026-01-06

### Fixed

- **SerializerNesting False Positive** - Skip ActiveStorage attachments
  - `user.avatar.attached?`, `user.avatar.variant(...)` no longer flagged
  - Recognizes `attached?`, `attach`, `blob`, `variant`, `purge` methods

## [1.1.3] - 2026-01-04

### Fixed

- **CallbackQuery False Positive** - Skip iterations over constants, arrays, and ranges
  - `CONDITIONS.each { |c| ... }` no longer triggers warning
  - `[:a, :b].each { |x| ... }` and `(1..5).each { |i| ... }` are now ignored

## [1.1.2] - 2026-01-04

### Fixed

- **CallbackQuery False Positive** - Only flag iterations that contain actual AR query methods
  - Non-AR iterations (Redis, Sidekiq, mailers) are no longer flagged
  - `Sidekiq::ScheduledSet.new.select { |job| ... }.each(&:delete)` no longer triggers warning

## [1.1.1] - 2026-01-03

### Fixed

- **SerializerNesting False Positive** - No longer flags `belongs_to` associations
  - `user.author`, `subscription.user` etc. (singular) are now ignored
  - Only `has_many` associations (plural names) are flagged as potential N+1

## [1.1.0] - 2025-12-28

### Added

- **Association Scope Preloading Detection** - LoopAssociation now recognizes associations with built-in preloading
  - Detects `has_many :posts, -> { includes(:comments) }` patterns
  - Recognizes scope-defined preloads to reduce false positives
  - Parses model files to extract association definitions and preload scopes

## [1.0.10] - 2025-12-27

### Changed

- **PluckToArray Severity Levels** - Scoped pluck is warning, `.all.pluck` is error
  - Scoped `.pluck(:id)` → **Warning** (acceptable for small arrays)
  - Unscoped `.all.pluck(:id)` → **Error** (loads entire table)
  - Improved detection and suggestions for critical patterns

## [1.0.9] - 2025-12-26

### Added

- **Inline Suppression Comments** - Suppress specific warnings with RuboCop-style inline comments
  - `# eager_eye:disable-next-line` - Suppress next line
  - `# eager_eye:disable CallbackQuery` - Suppress specific detector inline
  - `# eager_eye:disable-block` / `# eager_eye:enable-block` - Suppress block of code
  - `# eager_eye:disable-file DetectorName` - Suppress entire file
  - Supports both CamelCase and snake_case detector names
  - Can disable all detectors with `all` keyword

## [1.0.8] - 2025-12-25

### Added

- **Severity Levels** - error/warning/info with `--min-severity` filtering
  - Defaults: `loop_association`=error, `missing_counter_cache`=info, others=warning
  - Configurable via `.eager_eye.yml` (`severity_levels`, `min_severity`)

## [1.0.7] - 2025-12-24

### Fixed

- Fixed `invalid byte sequence in US-ASCII` error when parsing files containing non-ASCII characters (Turkish, Chinese, etc.)
  - Now properly encodes source code to UTF-8 with replacement for invalid/undefined characters
  - Fixes crash when analyzing files with special characters in comments or strings

## [1.0.6] - 2025-12-22

### Fixed

- Fixed false positive in `MissingCounterCache` detector for single `.count`/`.size`/`.length` calls
  - Now only detects count calls **inside iterations** where N+1 queries actually occur
  - Single calls like `post.comments.count` are no longer flagged (not N+1)
  - Iteration patterns like `posts.each { |p| p.comments.count }` are correctly detected

## [1.0.5] - 2025-12-21

### Fixed

- Fixed false positive N+1 warnings when iterating over a single record's associations
  - Now correctly skips warnings for patterns like `User.find(id).posts.each { |p| p.comments }`
  - Supports `find`, `find_by`, `find_by!`, `first`, `last`, `take`, `second`, `third`, etc.
  - Works with both inline chains and variable assignments

## [1.0.4] - 2025-12-21

### Fixed

- Fixed false positive N+1 warnings when associations are preloaded via `includes`, `preload`, or `eager_load` on a separate line
  - Now correctly tracks variable assignments with preload methods (e.g., `posts = Post.includes(:author)`)
  - Supports both local variables and instance variables
  - Works with all three preload methods: `includes`, `preload`, `eager_load`

## [1.0.3] - 2025-12-20

### Fixed

- Only flag queries in callbacks where the iteration variable is the receiver (reduces false positives)
- Updated README callback query documentation to accurately reflect current behavior

## [1.0.2] - 2025-12-19

### Fixed

- Only detect queries inside iterations in callback detector

## [1.0.1] - 2025-12-16

### Changed

- Removed `CountToSize` auto-fixer (`.count` → `.size` is not always correct)
- Auto-fix now only supports `PluckToSelect` (`.pluck(:id)` → `.select(:id)`)
- Updated README examples to use pluck_to_select

## [1.0.0] - 2025-12-16

### Stable Release

EagerEye is now production-ready! This release marks the first stable version with:

- 7 battle-tested detectors
- 95%+ test coverage
- Comprehensive documentation
- VS Code extension
- RSpec integration
- Auto-fix support

### Detectors

- **LoopAssociation** - N+1 in iterations
- **SerializerNesting** - N+1 in serializers
- **MissingCounterCache** - Counter cache suggestions
- **CustomMethodQuery** - Query methods in loops (Bullet can't catch!)
- **CountInIteration** - .count vs .size
- **CallbackQuery** - Queries in callbacks
- **PluckToArray** - Pluck to subquery

### Features

- CLI with JSON output
- Configuration file support (.eager_eye.yml)
- Inline suppression comments (RuboCop-style)
- Auto-fix suggestions (experimental)
- RSpec matchers (`pass_eager_eye`)
- VS Code extension
- GitHub Actions integration

### Documentation

- Added SECURITY.md
- Added CONTRIBUTING.md
- Coverage badge added to README

## [0.9.0] - 2025-12-16

### Added

- **VS Code Extension** - Released as a separate package
  - Real-time diagnostics on file save
  - Problem highlighting with squiggly underlines
  - Quick fix actions for common issues
  - Status bar showing issue count
  - Commands: Analyze Current File, Analyze Workspace, Clear Diagnostics
  - Configuration options for enabling/disabling features
  - See: https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye

## [0.8.0] - 2025-12-16

### Added

- **RSpec Integration** - RSpec matchers for testing your codebase
  - `pass_eager_eye` matcher for testing files and directories
  - `only` option to run specific detectors
  - `exclude` option to exclude files by glob pattern
  - `max_issues` option for gradual migration (allows up to N issues)
  - `require "eager_eye/rspec"` for easy integration
  - Helpful failure messages with issue details

## [0.7.0] - 2025-12-15

### Added

- **Auto-fix Suggestions (Experimental)** - Automatic fix capabilities for simple issues
  - `--suggest-fixes` flag to show auto-fix suggestions in diff format
  - `--fix` flag to apply auto-fixes interactively
  - `--fix --force` to apply all fixes without confirmation
  - Fixer for `.count` → `.size` transformation in iterations
  - Fixer for inline `.pluck(:id)` → `.select(:id)` transformation

### Note

Auto-fix is experimental. Not all issues are auto-fixable. Always review changes and run your test suite after applying fixes.

## [0.6.0] - 2025-12-15

### Added

- **Inline Suppression Comments** - RuboCop-style comment directives for suppressing false positives
  - `# eager_eye:disable DetectorName` - Disable for single line (inline) or start block
  - `# eager_eye:disable-next-line DetectorName` - Disable only the next line
  - `# eager_eye:disable-file DetectorName` - Disable for entire file (must be in first 5 lines)
  - `# eager_eye:enable DetectorName` - End a disable block
  - Support for multiple detectors: `# eager_eye:disable LoopAssociation, CountInIteration`
  - Support for reason comments: `# eager_eye:disable DetectorName -- reason here`
  - `all` keyword to disable all detectors at once
  - Both CamelCase (`LoopAssociation`) and snake_case (`loop_association`) detector names accepted

### Changed

- Updated README with inline suppression documentation
- Added `CommentParser` module for parsing suppression directives

## [0.5.0] - 2025-12-15

### Added

- **New Detector: `PluckToArray`** - Detects pluck/map results used in where clauses
  - Catches `.pluck(:id)` and `.ids` results used in `where` clauses
  - Catches `.map(&:id)` and `.collect(&:id)` patterns
  - Suggests using `.select(:id)` subquery pattern for better performance
  - Prevents two queries and memory overhead from holding IDs in arrays

### Changed

- Updated default `enabled_detectors` to include `:pluck_to_array`
- Updated README with new detector documentation and performance comparison

## [0.4.0] - 2025-12-15

### Added

- **New Detector: `CallbackQuery`** - Detects database queries and iterations inside ActiveRecord callbacks
  - Identifies potential bulk operation performance issues
  - Detects query methods (`.count`, `.sum`, `.update!`, etc.) in callbacks
  - Detects iterations (`.each`, `.map`, etc.) in callbacks as errors
  - Severity: `:error` for iterations in callbacks, `:warning` for query methods
  - Suggests moving to background jobs or using conditional callbacks

### Changed

- Updated default `enabled_detectors` to include `:callback_query`
- Updated README with new detector documentation

## [0.3.0] - 2025-12-15

### Added

- **New Detector: `CountInIteration`** - Detects `.count` usage inside iterations
  - `.count` always executes a COUNT query, even on preloaded associations
  - Suggests using `.size` instead (uses loaded collection when available)
  - Suggests `counter_cache: true` for frequently accessed counts
  - Helps prevent unnecessary COUNT queries when associations are already loaded

### Changed

- Updated default `enabled_detectors` to include `:count_in_iteration`
- Updated README with new detector documentation and comparison table

## [0.2.0] - 2025-12-15

### Added

- **New Detector: `CustomMethodQuery`** - Detects query methods called inside iteration blocks
  - Catches `.where`, `.find_by`, `.find_by!`, `.exists?` patterns that Bullet cannot detect
  - Detects `.find`, `.first`, `.last`, `.take` inside loops
  - Detects aggregation methods: `.pluck`, `.ids`, `.count`, `.sum`, `.average`, `.minimum`, `.maximum`
  - Provides suggestions for preloading data before loops

### Changed

- Updated default `enabled_detectors` to include `:custom_method_query`
- Updated README with new detector documentation and comparison table

## [0.1.0] - 2025-12-15

### Added

- **Static Analysis Engine**: AST-based code analysis using the `parser` gem
- **Three N+1 Detectors**:
  - `LoopAssociation`: Detects association calls inside iteration blocks (each, map, select, etc.)
  - `SerializerNesting`: Detects nested association access in serializer blocks (ActiveModel::Serializer, Blueprinter, Alba)
  - `MissingCounterCache`: Detects `.count`, `.size`, `.length` calls on associations
- **CLI Interface**: Full-featured command line tool with options:
  - `--format json|console`: Output format selection
  - `--exclude PATTERN`: Exclude files matching glob patterns
  - `--only DETECTORS`: Run specific detectors only
  - `--no-fail`: Exit with 0 even when issues found
  - `--no-color`: Disable colored output
  - `--version`, `--help`: Standard CLI options
- **Rails Integration**:
  - Railtie with `rake eager_eye:analyze` and `rake eager_eye:json` tasks
  - Install generator: `rails g eager_eye:install`
  - Support for `.eager_eye.yml` configuration file
- **Reporters**:
  - Console reporter with colored, human-readable output
  - JSON reporter for CI integration
- **Configuration System**:
  - `excluded_paths`: Glob patterns to exclude from analysis
  - `enabled_detectors`: Select which detectors to run
  - `app_path`: Base path for analysis (default: "app")
  - `fail_on_issues`: Control exit code behavior
- **GitHub Actions**: CI workflow with Ruby 3.1, 3.2, 3.3 matrix testing
- **Comprehensive Test Suite**: 140 examples with 95.8% code coverage

### Technical Details

- Minimum Ruby version: 3.1.0
- Dependencies: `parser ~> 3.3`, `ast ~> 2.4`
- License: MIT
