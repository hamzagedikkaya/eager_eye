# EagerEye

[![CI](https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml/badge.svg)](https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml)
[![Gem Version](https://badge.fury.io/rb/eager_eye.svg)](https://badge.fury.io/rb/eager_eye)
[![Coverage](https://img.shields.io/badge/coverage-95%25-brightgreen.svg)](https://github.com/hamzagedikkaya/eager_eye)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-ruby.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![VS Code Extension](https://img.shields.io/badge/VS%20Code-Extension-blue.svg)](https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye)

**Static analysis tool for detecting N+1 queries in Rails applications.**

EagerEye analyzes your Ruby code without running it, using AST (Abstract Syntax Tree) parsing to find potential N+1 query issues before they hit production.

## Why EagerEye?

Unlike runtime tools like Bullet, EagerEye:

- **Runs without executing code** - Works in CI pipelines without a test suite
- **Catches more patterns** - Detects serializer N+1s, missing counter caches, and query methods in loops
- **Proactive detection** - Finds issues at code review time, not after deployment

| Feature | EagerEye | Bullet |
|---------|----------|--------|
| Detection method | Static analysis | Runtime |
| Requires test suite | No | Yes |
| Serializer N+1 detection | Yes | Limited |
| Counter cache suggestions | Yes | No |
| Query methods in loops | Yes | No |
| CI integration | Native | Requires tests |
| False positive rate | Higher | Lower |

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

# Good - Eager load associations
posts.includes(:author, :comments).each do |post|
  post.author.name      # No additional query
  post.comments.count   # No additional query
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

Detects `.count` or `.size` calls on associations that could benefit from counter caches.

```ruby
# Bad - COUNT query every time
post.comments.count
post.comments.size

# Good - Add counter cache
# In Comment model:
belongs_to :post, counter_cache: true

# Then this is a simple column read:
post.comments_count
```

### 4. Custom Method Query (N+1 in query methods)

Detects query methods (`.where`, `.find_by`, `.exists?`, etc.) called on associations inside loops. **These patterns are invisible to Bullet.**

```ruby
# Bad - Bullet CANNOT catch this
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

Detects database queries and iterations inside ActiveRecord callbacks. These become performance disasters during bulk operations.

```ruby
# Bad - Queries in callbacks
class Article < ApplicationRecord
  after_save :recalculate_stats

  def recalculate_stats
    author.articles.published.count  # Runs on EVERY save
    category.update_article_count!   # Another query on EVERY save
  end
end

# Disaster scenario
Article.import(1000.times.map { |i| { title: "Post #{i}" } })
# = 2000+ queries from callbacks!

# Bad - N+1 in callback
class Order < ApplicationRecord
  after_create :notify_subscribers

  def notify_subscribers
    customer.followers.each do |follower|  # N+1!
      NotificationMailer.new_order(follower).deliver_later
    end
  end
end

# Good - Use conditional callbacks
after_save :recalculate_stats, if: :should_recalculate?

# Good - Move to background job
after_commit :schedule_stats_update, on: :create

def schedule_stats_update
  RecalculateStatsJob.perform_later(id)
end
```

### 7. Pluck to Array Misuse

Detects when `.pluck(:id)` or `.map(&:id)` results are used in `where` clauses instead of subqueries.

```ruby
# Bad - Two queries + memory overhead
user_ids = User.active.pluck(:id)  # Query 1: SELECT id FROM users
Post.where(user_id: user_ids)      # Query 2: SELECT * FROM posts WHERE user_id IN (1,2,3...)
# Also holds potentially thousands of IDs in memory

# Bad - Same problem with map
user_ids = users.map(&:id)
Post.where(user_id: user_ids)

# Good - Single subquery, no memory overhead
Post.where(user_id: User.active.select(:id))
# Single query: SELECT * FROM posts WHERE user_id IN (SELECT id FROM users WHERE active = true)
```

**Performance comparison with 10,000 users:**

| Approach | Queries | Memory | Time |
|----------|---------|--------|------|
| `pluck` + `where` | 2 | ~80KB for IDs | ~45ms |
| `select` subquery | 1 | None | ~20ms |

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
| `.count` in iteration | → `.size` |
| `.pluck(:id)` inline | → `.select(:id)` |

### Example

```
$ eager_eye --suggest-fixes

app/controllers/posts_controller.rb:
  Line 15:
    - user.posts.count
    + user.posts.size

$ eager_eye --fix
app/controllers/posts_controller.rb:15
  - user.posts.count
  + user.posts.size
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
