<p align="center">
  <img src="images/icon.png" alt="EagerEye" width="140">
</p>

<h1 align="center">EagerEye</h1>

<p align="center">
  <strong>Catch N+1 queries in your Rails app — without running it.</strong><br>
  <sub>Static analysis powered by Ruby AST. Fast. Zero runtime overhead. CI-ready.</sub>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <a href="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml"><img src="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/eager_eye"><img src="https://img.shields.io/gem/v/eager_eye?color=red&label=gem" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/eager_eye"><img src="https://img.shields.io/gem/dt/eager_eye?color=blue&label=downloads" alt="Downloads"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D" alt="Ruby"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/github/license/hamzagedikkaya/eager_eye" alt="License"></a>
  <a href="https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye"><img src="https://img.shields.io/badge/VS%20Code-Extension-007ACC?logo=visualstudiocode&logoColor=white" alt="VS Code Extension"></a>
</p>

> 💡 **Prefer in-editor warnings?** Install the [VS Code extension](https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye) — same engine, runs on save, surfaces issues right next to the offending line. Same speed as the CLI, just a smoother feedback loop.

---

## Why EagerEye?

**Bullet** finds N+1s when your tests hit them. **EagerEye** finds them statically — before any code runs.

- 🎯 **Catch what tests miss** — N+1s in code paths your test suite doesn't exercise still get flagged.
- ⚡ **Run in CI on every PR** — no DB, no fixtures, no Rails boot. Just `eager_eye app/`.
- 🔬 **11 detector types** — beyond simple loop access: serializer nesting, callback queries, decorator/delegation traps, batch validation, scope chains, plucked-array misuse, and more.
- 🤝 **Plays well with Bullet** — static + runtime cover different blind spots. Use both.

## Install

```ruby
# Gemfile
gem "eager_eye", group: :development
```

```bash
bundle install
```

Or standalone:

```bash
gem install eager_eye
```

## Quick Start

```bash
# Scan the default app/ directory
eager_eye

# Or scan specific paths
eager_eye app/controllers app/serializers

# Generate a config file (optional)
rails g eager_eye:install

# Run via rake
rake eager_eye:analyze
```

Sample output:

```text
app/controllers/posts_controller.rb
  Line 15: [LoopAssociation] Potential N+1 query: `post.author` called inside iteration
           Suggestion: Use `includes(:author)` on the collection before iterating

  Line 23: [MissingCounterCache] `.count` called on `comments` may cause N+1 queries
           Suggestion: Add `counter_cache: true` to the belongs_to association

Total: 2 issues (2 warnings, 0 errors)
```

## What it detects

| # | Detector | What it catches |
|---|---|---|
| 1 | **LoopAssociation** | Association calls inside `each`/`map`/`find_each`/etc. without preloading |
| 2 | **SerializerNesting** | Nested association access in Blueprinter / ActiveModel::Serializer / Alba blocks |
| 3 | **MissingCounterCache** | `.count` / `.size` on associations inside loops where a counter cache would help |
| 4 | **CustomMethodQuery** | `.where`, `.find_by`, `.exists?` etc. on association chains inside iterations |
| 5 | **CountInIteration** | `.count` (always queries) used in loops where `.size` (uses preload) would suffice |
| 6 | **CallbackQuery** | Iteration-driven queries inside ActiveRecord callbacks (`after_save`, `after_create`, ...) |
| 7 | **PluckToArray** | `.pluck(:id)` results passed to `where(id: ...)` instead of using a subquery; flags `.all.pluck` as critical |
| 8 | **DelegationNPlusOne** | `delegate :method, to: :association` calls in loops where the target isn't preloaded |
| 9 | **DecoratorNPlusOne** | Draper / SimpleDelegator / Presenter / ViewObject access without preload before `.decorate` |
| 10 | **ScopeChainNPlusOne** | Named scopes (`.recent`, `.active`) on associations in loops — invisible query triggers |
| 11 | **ValidationNPlusOne** | `Model.create`/`save` inside loops on models with `validates :x, uniqueness: true` |

EagerEye also tracks preloads across pagination wrappers (`pagy`, `paginate`, `kaminari`), per-method scope, multi-line builder chains, and helper-method parameters — so warnings respect the eager-loading you've already set up.

<details>
<summary><b>Detailed examples for each detector →</b></summary>

### 1. LoopAssociation

```ruby
# Bad
posts.each { |post| post.author.name }   # query per post

# Good — chained
posts.includes(:author).each { |post| post.author.name }

# Good — separate line (preload tracked across assignment)
@posts = Post.includes(:author)
@posts.each { |post| post.author.name }

# Good — single record (no N+1 possible)
@user = User.find(params[:id])
@user.posts.each { |post| post.comments }
```

Recognizes `.includes`, `.preload`, `.eager_load`, scoped `has_many` (`-> { includes(:author) }`), and pagination wrappers like `@pagy, items = pagy(...)`.

### 2. SerializerNesting

```ruby
# Bad
class PostSerializer < Blueprinter::Base
  field :author_name { |post| post.author.name }   # query per serialized post
end

# Good — preload in controller
@posts = Post.includes(:author)
render json: PostSerializer.render(@posts)
```

Supports Blueprinter, ActiveModel::Serializers, Alba.

### 3. MissingCounterCache

```ruby
# Bad — COUNT query for each post
posts.each { |post| post.comments.count }

# Good — counter cache (Comment: belongs_to :post, counter_cache: true)
posts.each { |post| post.comments_count }   # column read, no query
```

Only flagged inside iterations — single calls don't cause N+1.

### 4. CustomMethodQuery

```ruby
# Bad — where inside loop
@users.each { |user| user.teams.where(name: "Lakers").exists? }

# Good — preload + filter in Ruby
@users.includes(:teams).each { |user| user.teams.any? { |t| t.name == "Lakers" } }
```

Detected: `where`, `find_by`, `exists?`, `find`, `first`, `last`, `take`, `pluck`, `count`, `sum`, `average`, `minimum`, `maximum`. Per-model scoped — won't flag `obj.foo` just because some other model defines `def foo` with a query.

### 5. CountInIteration

```ruby
# Bad — .count always queries, even with includes
@users = User.includes(:posts)
@users.each { |user| user.posts.count }   # SELECT COUNT(*) per user

# Good — .size uses the preload
@users.each { |user| user.posts.size }
```

| Method | Loaded | Not loaded |
|---|---|---|
| `.count` | COUNT query | COUNT query |
| `.size` | array#size | COUNT query |
| `.length` | array#length | loads all then counts |

### 6. CallbackQuery

```ruby
# Bad — N+1 inside callback
class Order < ApplicationRecord
  after_create :notify_subscribers

  def notify_subscribers
    customer.followers.each { |f| f.notifications.create!(...) }   # N inserts + N queries
  end
end

# Good — defer to background job
after_commit :schedule_notifications, on: :create
def schedule_notifications
  NotifySubscribersJob.perform_later(id)
end
```

### 7. PluckToArray

```ruby
# Warning — two queries + memory overhead
user_ids = User.active.pluck(:id)
Post.where(user_id: user_ids)

# Error — loads entire table
user_ids = User.all.pluck(:id)
Post.where(user_id: user_ids)

# Good — single subquery
Post.where(user_id: User.active.select(:id))
```

`.where(...).all.pluck(:id)` is correctly recognized as scoped, not a table scan.

### 8. DelegationNPlusOne

```ruby
class Order < ApplicationRecord
  belongs_to :user
  delegate :full_name, :email, to: :user
end

# Bad — looks like attribute access, actually loads user per order
orders.each { |o| o.full_name }

# Good
orders.includes(:user).each { |o| o.full_name }
```

Cross-file: scans models for `delegate ... to: :assoc` declarations.

### 9. DecoratorNPlusOne

```ruby
class PostDecorator < Draper::Decorator
  def comment_summary
    object.comments.map(&:body).join(", ")   # query per decorated post
  end
end

# Bad
@posts = Post.all.decorate

# Good
@posts = Post.includes(:comments).all.decorate
```

Recognizes `object`, `__getobj__`, `source`, `model` references inside Draper / SimpleDelegator / Presenter / ViewObject classes.

### 10. ScopeChainNPlusOne

```ruby
class Comment < ApplicationRecord
  scope :recent, -> { where("created_at > ?", 1.week.ago) }
end

# Bad — scope call per iteration
posts.each { |post| post.comments.recent }

# Good — preload + filter
posts.includes(:comments).each { |post| post.comments.select { |c| c.created_at > 1.week.ago } }
```

Cross-file: scans models for `scope :name, -> { ... }` declarations.

### 11. ValidationNPlusOne

```ruby
class User < ApplicationRecord
  validates :email, uniqueness: true
end

# Bad — SELECT + INSERT per record
params[:users].each { |p| User.create!(p) }

# Good — single bulk INSERT, DB enforces uniqueness via index
User.insert_all(params[:users])
```

</details>

## Inline suppression

RuboCop-style comments suppress false positives or accepted patterns:

```ruby
# Single line
user.posts.count  # eager_eye:disable CountInIteration

# Next line
# eager_eye:disable-next-line LoopAssociation
@users.each { |u| u.profile }

# Block
# eager_eye:disable LoopAssociation, SerializerNesting
@users.each { |u| u.posts.each { |p| p.author } }
# eager_eye:enable LoopAssociation, SerializerNesting

# Whole file (must be in first 5 lines)
# eager_eye:disable-file CustomMethodQuery

# With reason
user.posts.count  # eager_eye:disable CountInIteration -- using counter_cache

# Disable everything
# eager_eye:disable all
```

Detector names are accepted as either CamelCase (`LoopAssociation`) or snake_case (`loop_association`).

## Auto-fix (experimental)

```bash
eager_eye --suggest-fixes   # show diff
eager_eye --fix             # interactive
eager_eye --fix --force     # apply all without confirmation
```

| Issue | Auto-fix |
|---|---|
| `.pluck(:id)` used in `.where(id: ...)` | → `.select(:id)` |
| `.count` in iteration | → `.size` |
| Missing `includes` before loop | → inserts `.includes(:assoc)` |

> ⚠ Always review the diff and re-run your test suite after `--fix`.

## CI integration

```yaml
# .github/workflows/eager_eye.yml
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
      - run: |
          issues=$(ruby -rjson -e 'puts JSON.parse(File.read("report.json"))["summary"]["total_issues"]')
          [ "$issues" -gt 0 ] && echo "::warning::Found $issues potential N+1 issues" || true
```

See [examples/github_action.yml](examples/github_action.yml) for a fuller setup with PR annotations.

## RSpec integration

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

  # Allow some during migration
  it "legacy code is acceptable" do
    expect("app/services/legacy").to pass_eager_eye(max_issues: 10)
  end
end
```

Matcher options: `only:` (Array<Symbol>), `exclude:` (Array<String> globs), `max_issues:` (Integer, default 0).

## Configuration

```yaml
# .eager_eye.yml
excluded_paths:
  - app/legacy/**
  - lib/tasks/**

enabled_detectors:        # default: all
  - loop_association
  - serializer_nesting
  - custom_method_query
  # ...

severity_levels:
  loop_association: error
  missing_counter_cache: info
  # ...

min_severity: warning     # info | warning | error
app_path: app
fail_on_issues: true
```

Or programmatically:

```ruby
EagerEye.configure do |config|
  config.excluded_paths = ["app/legacy/**"]
  config.enabled_detectors = [:loop_association, :serializer_nesting]
  config.min_severity = :warning
  config.fail_on_issues = true
end
```

## CLI reference

```text
Usage: eager_eye [paths] [options]

  -f, --format FORMAT       console | json (default: console)
  -e, --exclude PATTERN     glob to exclude (repeatable)
  -o, --only DETECTORS      comma-separated detector list
  -s, --min-severity LEVEL  info | warning | error
      --no-fail             always exit 0
      --no-color            plain output
      --suggest-fixes       print fix diffs without applying
      --fix                 interactively apply auto-fixes
      --fix --force         apply all auto-fixes
  -v, --version
  -h, --help
```

## Limitations

EagerEye is static analysis. That comes with trade-offs:

- **No runtime context** — can't see what `find_each` block actually does at runtime.
- **Heuristic association detection** — falls back to common name patterns (`author`, `user`, ...) when a model isn't in the parsed set; can over-flag in tiny edge cases.
- **Cross-file flow** — propagates preloads across same-class methods (controller → its private helpers), but cross-file flow (controller → external service object → iteration) isn't tracked yet.
- **Ruby code only** — doesn't read SQL or your DB schema.

Use it alongside [Bullet](https://github.com/flyerhzm/bullet) for a complete picture: static (EagerEye) catches code paths tests don't hit, runtime (Bullet) catches what static can't see.

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
bin/console
```

## Contributing

Bug reports and PRs welcome at <https://github.com/hamzagedikkaya/eager_eye>.

1. Fork
2. `git checkout -b feature/my-feature`
3. Add specs (this repo is at ~95% coverage)
4. `git commit -am 'Add my feature'`
5. Open a Pull Request

## License

MIT — see [LICENSE.txt](LICENSE.txt).

## Code of Conduct

Everyone interacting in EagerEye's codebases, issue trackers, and discussions is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
