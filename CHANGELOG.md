# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
