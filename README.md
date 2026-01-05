<p align="center">
  <img src="images/icon.png" alt="EagerEye Logo" width="140">
</p>

<h1 align="center">EagerEye</h1>

<p align="center">
  <strong>Static analysis tool for detecting N+1 queries in Rails applications.</strong>
</p>

<p align="center">
  <a href="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml"><img src="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/eager_eye"><img src="https://img.shields.io/badge/gem-v1.1.3-red.svg" alt="Gem Version"></a>
  <a href="https://github.com/hamzagedikkaya/eager_eye"><img src="https://img.shields.io/badge/coverage-95%25-brightgreen.svg" alt="Coverage"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D%203.1-ruby.svg" alt="Ruby"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye"><img src="https://img.shields.io/badge/VS%20Code-Extension-blue.svg" alt="VS Code Extension"></a>
</p>

<p align="center">
  <em>Analyze your Ruby code without running it — find N+1 query issues before they hit production using AST parsing.</em>
</p>

---

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Detected Issues](#detected-issues)
- [Inline Suppression](#inline-suppression)
- [Auto-fix](#auto-fix-experimental)
- [RSpec Integration](#rspec-integration)
- [Configuration](#configuration)
- [CI Integration](#ci-integration)
- [CLI Reference](#cli-reference)
- [Output Formats](#output-formats)
- [Limitations](#limitations)
- [VS Code Extension](#vs-code-extension)
- [Development](#development)
- [Contributing](#contributing)

## Features

✨ **Detects 7 types of N+1 problems:**
- Loop associations (queries in iterations)
- Serializer nesting issues
- Missing counter caches
- Custom method queries
- Count in iteration patterns
- Callback query N+1s
- Pluck to array misuse

🔧 **Developer-friendly:**
- Inline suppression (like RuboCop)
- Auto-fix support (experimental)
- JSON/Console output formats
- RSpec integration

🚀 **CI-ready:**
- No test suite required
- GitHub Actions examples included
- Severity levels and filtering

## Installation

Add to your Gemfile:

```ruby
gem "eager_eye", group: :development
```

Then run:

```bash
bundle install
```

Or install standalone:

```bash
gem install eager_eye
```

## Quick Start

### CLI Usage

```bash
# Analyze default app/ directory
eager_eye

# Analyze specific paths
eager_eye app/controllers app/serializers

# Output as JSON (for CI)
eager_eye --format json

# Don't fail on issues (exit 0)
eager_eye --no-fail

# Run specific detectors only
eager_eye --only loop_association,serializer_nesting

# Exclude paths
eager_eye --exclude "app/legacy/**"
```

### Rails Integration

```bash
# Generate config file
rails g eager_eye:install

# Run via rake
rake eager_eye:analyze

# JSON output
rake eager_eye:json
```

## Detected Issues

### 1. Loop Association (N+1 in iterations)

Detects association calls inside loops that may cause N+1 queries.

```ruby
# Bad - N+1 query on each iteration
posts.each do |post|
  post.author.name      # Query for each post!
  post.comments.count   # Another query for each post!
end

# Good - Eager load associations (chained)
posts.includes(:author, :comments).each do |post|
  post.author.name      # No additional query
  post.comments.count   # No additional query
end

# Good - Eager load on separate line (also detected correctly!)
@posts = Post.includes(:author)
@posts.each do |post|
  post.author.name      # No warning - EagerEye tracks the preload
end

# Also works with preload and eager_load
posts = Post.preload(:comments)
posts.each { |post| post.comments.size }  # No warning

# Single record context - no N+1 possible (also detected correctly!)
@user = User.find(params[:id])
@user.posts.each do |post|
  post.comments  # No warning - single user, no N+1
end

# Scope-defined preloads are recognized (v1.1.0+)
# In Post model:
class Post < ApplicationRecord
  has_many :comments, -> { includes(:author) }
end

# In controller - EagerEye recognizes comments are already preloaded via scope!
posts.each do |post|
  post.comments.map(&:author)  # No warning - preloaded via scope
end
```

### 2. Serializer Nesting (N+1 in serializers)

Detects nested association access in serializer blocks.

```ruby
# Bad - N+1 in serializer
class PostSerializer < ActiveModel::Serializer
  attribute :author_name do
    object.author.name  # Query for each serialized post!
  end
end

# Good - Eager load in controller
class PostsController < ApplicationController
  def index
    @posts = Post.includes(:author)
    render json: @posts, each_serializer: PostSerializer
  end
end
```

Supports multiple serializer libraries:
- ActiveModel::Serializers
- Blueprinter
- Alba

### 3. Missing Counter Cache

Detects `.count`, `.size`, or `.length` calls on associations **inside iterations** that could benefit from counter caches. Single calls outside loops are not flagged since they don't cause N+1 issues.

```ruby
# Bad - COUNT query for each post in iteration
posts.each do |post|
  post.comments.count   # Detected: N+1 query!
  post.likes.size       # Detected: N+1 query!
end

# OK - Single count call (not in iteration, no N+1)
post.comments.count     # Not flagged - single query is fine

# Good - Add counter cache for iteration use cases
# In Comment model:
belongs_to :post, counter_cache: true

# Then this is a simple column read:
posts.each do |post|
  post.comments_count   # No query - just reads the column
end
```

### 4. Custom Method Query (N+1 in query methods)

Detects query methods (`.where`, `.find_by`, `.exists?`, etc.) called on associations inside loops.

```ruby
# Bad - where inside loop
class User < ApplicationRecord
  def supports?(team_name)
    teams.where(name: team_name).exists?
  end
end

@users.each do |user|
  user.supports?("Lakers")  # Query for each user!
end

# Bad - find_by inside loop
@orders.each do |order|
  order.line_items.find_by(featured: true)
end

# Good - Preload and filter in Ruby
@users.includes(:teams).each do |user|
  user.teams.any? { |t| t.name == "Lakers" }
end
```

**Detected methods:** `where`, `find_by`, `find_by!`, `exists?`, `find`, `first`, `last`, `take`, `pluck`, `ids`, `count`, `sum`, `average`, `minimum`, `maximum`

### 5. Count in Iteration

Detects `.count` called on associations inside loops. Unlike `.size`, `.count` always executes a COUNT query even when the association is preloaded.

```ruby
# Bad - COUNT query for each user, even with includes!
@users = User.includes(:posts)
@users.each do |user|
  user.posts.count  # Executes: SELECT COUNT(*) FROM posts WHERE user_id = ?
end

# Good - Use .size (checks if loaded first)
@users.each do |user|
  user.posts.size   # No query - counts the loaded array
end

# Best - Use counter_cache for frequent counts
# In Post model: belongs_to :user, counter_cache: true
user.posts_count  # Just reads the column
```

**Key differences:**

| Method | Loaded Collection | Not Loaded |
|--------|------------------|------------|
| `.count` | COUNT query | COUNT query |
| `.size` | Array#size | COUNT query |
| `.length` | Array#length | Loads all, then counts |

### 6. Callback Query Detection

Detects N+1 patterns inside ActiveRecord callbacks - specifically iterations that execute queries on each loop.

```ruby
# Bad - N+1 in callback (DETECTED)
class Order < ApplicationRecord
  after_create :notify_subscribers

  def notify_subscribers
    customer.followers.each do |follower|  # Error: Iteration in callback
      follower.notifications.create!(...)  # Warning: Query on iteration variable
    end
  end
end

# OK - Single query in callback (NOT flagged - not N+1)
class Article < ApplicationRecord
  after_save :update_stats

  def update_stats
    author.articles.count  # Single query, acceptable
  end
end

# OK - Query not on iteration variable (NOT flagged)
class Post < ApplicationRecord
  after_save :process_items

  def process_items
    items.each do |item|
      OtherModel.where(name: item.name).first  # OtherModel is receiver, not item
    end
  end
end

# Good - Move iterations to background job
after_commit :schedule_notifications, on: :create

def schedule_notifications
  NotifySubscribersJob.perform_later(id)
end
```

### 7. Pluck to Array Misuse

Detects when `.pluck(:id)` or `.map(&:id)` results are used in `where` clauses instead of subqueries.

```ruby
# Bad - Two queries + memory overhead
user_ids = User.active.pluck(:id)
Post.where(user_id: user_ids)  # ⚠️ Warning

# Worse - Loads entire table! 🔴 Error
user_ids = User.all.pluck(:id)
Post.where(user_id: user_ids)

# Good - Single subquery
Post.where(user_id: User.active.select(:id))
```

**Severity:**
- ⚠️ **Warning** - Scoped `.pluck(:id)` (two queries, memory overhead)
- 🔴 **Error** - Unscoped `.all.pluck(:id)` (loads entire table)

## Inline Suppression

Suppress false positives using inline comments (RuboCop-style):

```ruby
# Disable for single line
user.posts.count  # eager_eye:disable CountInIteration

# Disable for next line
# eager_eye:disable-next-line LoopAssociation
@users.each { |u| u.profile }

# Disable block
# eager_eye:disable LoopAssociation, SerializerNesting
@users.each do |user|
  user.posts.each { |p| p.author }
end
# eager_eye:enable LoopAssociation, SerializerNesting

# Disable entire file (must be in first 5 lines)
# eager_eye:disable-file CustomMethodQuery

# With reason
user.posts.count  # eager_eye:disable CountInIteration -- using counter_cache

# Disable all detectors
# eager_eye:disable all
```

### Available Detector Names

Both CamelCase and snake_case formats are accepted:

| Detector | CamelCase | snake_case |
|----------|-----------|------------|
| Loop Association | `LoopAssociation` | `loop_association` |
| Serializer Nesting | `SerializerNesting` | `serializer_nesting` |
| Missing Counter Cache | `MissingCounterCache` | `missing_counter_cache` |
| Custom Method Query | `CustomMethodQuery` | `custom_method_query` |
| Count in Iteration | `CountInIteration` | `count_in_iteration` |
| Callback Query | `CallbackQuery` | `callback_query` |
| Pluck to Array | `PluckToArray` | `pluck_to_array` |
| All Detectors | `all` | `all` |

## Auto-fix (Experimental)

EagerEye can automatically fix some simple issues:

```bash
# Show fix suggestions
eager_eye --suggest-fixes

# Apply fixes interactively
eager_eye --fix

# Apply all fixes without confirmation
eager_eye --fix --force
```

### Currently Supported Auto-fixes

| Issue | Fix |
|-------|-----|
| `.pluck(:id)` inline | → `.select(:id)` |

### Example

```
$ eager_eye --suggest-fixes

app/services/user_service.rb:
  Line 12:
    - Post.where(user_id: User.active.pluck(:id))
    + Post.where(user_id: User.active.select(:id))

$ eager_eye --fix
app/services/user_service.rb:12
  - Post.where(user_id: User.active.pluck(:id))
  + Post.where(user_id: User.active.select(:id))
Apply this fix? [y/n/q] y
  Applied
```

> **Warning:** Auto-fix is experimental. Always review changes and run your test suite after applying fixes.

## RSpec Integration

EagerEye provides RSpec matchers for testing your codebase:

```ruby
# spec/rails_helper.rb
require "eager_eye/rspec"

# spec/eager_eye_spec.rb
RSpec.describe "EagerEye Analysis" do
  it "controllers have no N+1 issues" do
    expect("app/controllers").to pass_eager_eye
  end

  it "serializers are clean" do
    expect("app/serializers").to pass_eager_eye(only: [:serializer_nesting])
  end

  # Allow some issues during migration
  it "legacy code is acceptable" do
    expect("app/services/legacy").to pass_eager_eye(max_issues: 10)
  end

  it "models have no callback issues except legacy" do
    expect("app/models").to pass_eager_eye(
      only: [:callback_query],
      exclude: ["app/models/legacy/**"]
    )
  end
end
```

### Matcher Options

| Option | Type | Description |
|--------|------|-------------|
| `only` | `Array<Symbol>` | Run only specified detectors |
| `exclude` | `Array<String>` | Glob patterns to exclude |
| `max_issues` | `Integer` | Maximum allowed issues (default: 0) |

## Configuration

### Config File (.eager_eye.yml)

```yaml
# Paths to exclude from analysis (glob patterns)
excluded_paths:
  - app/serializers/legacy/**
  - lib/tasks/**

# Detectors to enable (default: all)
enabled_detectors:
  - loop_association
  - serializer_nesting
  - missing_counter_cache
  - custom_method_query
  - count_in_iteration
  - callback_query
  - pluck_to_array

# Severity levels per detector (error, warning, info)
severity_levels:
  loop_association: error        # Definite N+1
  serializer_nesting: warning
  custom_method_query: warning
  count_in_iteration: warning
  callback_query: warning
  pluck_to_array: warning        # Optimization
  missing_counter_cache: info    # Suggestion

# Minimum severity to report (default: info)
min_severity: warning

# Base path to analyze (default: app)
app_path: app

# Exit with error code when issues found (default: true)
fail_on_issues: true
```

### Programmatic Configuration

```ruby
EagerEye.configure do |config|
  config.excluded_paths = ["app/legacy/**"]
  config.enabled_detectors = [:loop_association, :serializer_nesting]
  config.severity_levels = { loop_association: :error, missing_counter_cache: :info }
  config.min_severity = :warning
  config.app_path = "app"
  config.fail_on_issues = true
end
```

## CI Integration

### GitHub Actions

```yaml
name: EagerEye
on: [pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
      - run: gem install eager_eye
      - run: eager_eye app/ --format json > report.json
      - name: Check results
        run: |
          issues=$(cat report.json | ruby -rjson -e 'puts JSON.parse(STDIN.read)["summary"]["total_issues"]')
          if [ "$issues" -gt 0 ]; then
            echo "::warning::Found $issues potential N+1 issues"
          fi
```

See [examples/github_action.yml](examples/github_action.yml) for a complete example with PR annotations.

## CLI Reference

```
Usage: eager_eye [paths] [options]

Options:
    -f, --format FORMAT      Output format: console, json (default: console)
    -e, --exclude PATTERN    Exclude files matching pattern (can be used multiple times)
    -o, --only DETECTORS     Run only specified detectors (comma-separated)
    -s, --min-severity LEVEL Minimum severity to report (info, warning, error)
        --no-fail            Exit with 0 even when issues are found
        --no-color           Disable colored output
    -v, --version            Show version
    -h, --help               Show this help message
```

## Output Formats

### Console (default)

```
EagerEye Analysis Results
=========================

app/controllers/posts_controller.rb
  Line 15: [LoopAssociation] Potential N+1 query: `post.author` called inside iteration
           Suggestion: Consider using `includes(:author)` on the collection before iterating

  Line 23: [MissingCounterCache] `.count` called on `comments` may cause N+1 queries
           Suggestion: Consider adding `counter_cache: true` to the belongs_to association

----------------------------------------
Total: 2 issues (2 warnings, 0 errors)
```

### JSON

```json
{
  "summary": {
    "total_issues": 2,
    "warnings": 2,
    "errors": 0,
    "files_analyzed": 15
  },
  "issues": [
    {
      "detector": "loop_association",
      "file_path": "app/controllers/posts_controller.rb",
      "line_number": 15,
      "message": "Potential N+1 query: `post.author` called inside iteration",
      "severity": "warning",
      "suggestion": "Consider using `includes(:author)` on the collection"
    }
  ]
}
```

## Limitations

EagerEye uses static analysis, which means:

- **No runtime context** - Cannot know if associations are already eager loaded elsewhere
- **Heuristic-based** - Uses naming conventions to identify associations (may have false positives)
- **Ruby code only** - Does not analyze SQL queries or ActiveRecord internals

For best results, use EagerEye alongside runtime tools like Bullet for comprehensive N+1 detection.

## VS Code Extension

EagerEye is also available as a VS Code extension for real-time analysis while coding.

**Features:**
- Real-time analysis on file save
- Problem highlighting with squiggly underlines
- Quick fix actions for common issues
- Status bar showing issue count

**Install:** Search for "EagerEye" in VS Code Extensions or visit the [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye).

## Development

```bash
# Setup
bin/setup

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Interactive console
bin/console
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hamzagedikkaya/eager_eye.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the EagerEye project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/hamzagedikkaya/eager_eye/blob/master/CODE_OF_CONDUCT.md).
