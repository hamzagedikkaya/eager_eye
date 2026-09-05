<p align="center">
  <img src="images/icon.png" alt="EagerEye" width="140">
</p>

<h1 align="center">EagerEye</h1>

<p align="center">
  <strong>Rails uygulamandaki N+1 sorgularını yakala — uygulamayı çalıştırmadan.</strong><br>
  <sub>Ruby AST tabanlı statik analiz. Hızlı. Sıfır runtime maliyeti. CI'a hazır.</sub>
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>Türkçe</strong>
</p>

<p align="center">
  <a href="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml"><img src="https://github.com/hamzagedikkaya/eager_eye/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/eager_eye"><img src="https://img.shields.io/gem/v/eager_eye?color=red&label=gem" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/eager_eye"><img src="https://img.shields.io/gem/dt/eager_eye?color=blue&label=indirme" alt="İndirmeler"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D" alt="Ruby"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/github/license/hamzagedikkaya/eager_eye" alt="Lisans"></a>
  <a href="https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye"><img src="https://img.shields.io/badge/VS%20Code-Eklenti-007ACC?logo=visualstudiocode&logoColor=white" alt="VS Code Eklentisi"></a>
</p>

> 💡 **Editör içinde uyarı görmeyi mi tercih edersin?** [VS Code eklentisini](https://marketplace.visualstudio.com/items?itemName=hamzagedikkaya.eager-eye) kur — aynı motor, kaydettiğinde çalışır, sorunları doğrudan ilgili satırın yanında gösterir. CLI ile aynı hızda, sadece daha akıcı bir geri bildirim döngüsü.

---

## Neden EagerEye?

**Bullet** N+1'leri test'lerin onlara denk geldiğinde bulur. **EagerEye** ise statik olarak bulur — kod hiç çalışmadan.

- 🎯 **Test'lerin kaçırdıklarını yakala** — Test suite'in girmediği kod yollarındaki N+1'ler de işaretlenir.
- ⚡ **Her PR'da CI'da çalıştır** — DB yok, fixture yok, Rails boot yok. Sadece `eager_eye app/`.
- 🔬 **11 detector tipi** — basit loop erişiminin ötesinde: serializer nesting, callback query'leri, decorator/delegation tuzakları, batch validation, scope chain'leri, plucked-array yanlış kullanımı ve dahası.
- 🤝 **Bullet ile iyi anlaşır** — statik + runtime farklı kör noktaları kapatır. İkisini birden kullan.

## Kurulum

```ruby
# Gemfile
gem "eager_eye", group: :development
```

```bash
bundle install
```

Veya bağımsız:

```bash
gem install eager_eye
```

## Hızlı Başlangıç

```bash
# Varsayılan app/ dizinini tara
eager_eye

# Veya belirli yolları tara
eager_eye app/controllers app/serializers

# Config dosyası oluştur (opsiyonel)
rails g eager_eye:install

# Rake ile çalıştır (console veya JSON)
rake eager_eye:analyze
rake eager_eye:json
```

> **İpucu:** tek bir dosya veya `app/controllers` yerine `models/` dizinini içeren bir yolu
> (örn. `app/`) tara. Model metadata'sı (ilişkiler, `delegate`, `scope`, uniqueness
> validation'ları) `<ilk yol>/models/**` altından toplanır; 8, 10 ve 11 numaralı detector'lar
> ile preload-farkında ilişki takibi buna bağlıdır.

Örnek çıktı:

```text
app/controllers/posts_controller.rb
  Line 15: [LoopAssociation] Olası N+1 sorgu: `post.author` iterasyon içinde çağrılıyor
           Öneri: Iterasyondan önce koleksiyona `includes(:author)` ekle

  Line 23: [MissingCounterCache] `comments` üzerinde `.count` çağrısı N+1'e yol açabilir
           Öneri: belongs_to ilişkisine `counter_cache: true` ekle

Total: 2 issues (2 warnings, 0 errors)
```

## Neyi tespit eder

| # | Detector | Neyi yakalar |
|---|---|---|
| 1 | **LoopAssociation** | `each`/`map`/`find_each` vb. içinde preload edilmemiş ilişki çağrıları |
| 2 | **SerializerNesting** | Blueprinter / ActiveModel::Serializer / Alba block'larında nested ilişki erişimi |
| 3 | **MissingCounterCache** | Loop içinde counter cache'le çözülebilecek `.count` / `.size` çağrıları |
| 4 | **CustomMethodQuery** | Iterasyon içinde ilişki zincirinde `.where`, `.find_by`, `.exists?` vb. |
| 5 | **CountInIteration** | `.size` (preload kullanır) yeterken loop'ta `.count` (her zaman query) kullanımı |
| 6 | **CallbackQuery** | ActiveRecord callback'leri içinde iterasyon kaynaklı sorgular (`after_save`, `after_create`, ...) |
| 7 | **PluckToArray** | `.pluck(:id)` sonucunun subquery yerine `where(id: ...)`'a verilmesi; `.all.pluck` kritik olarak işaretlenir |
| 8 | **DelegationNPlusOne** | Loop içinde `delegate :method, to: :association` çağrıları, hedef preload edilmemişse |
| 9 | **DecoratorNPlusOne** | Draper / SimpleDelegator / Presenter / ViewObject erişimi, `.decorate` öncesi preload yoksa |
| 10 | **ScopeChainNPlusOne** | Loop içinde ilişki üzerine isimli scope'lar (`.recent`, `.active`) — görünmez query tetikleyicileri |
| 11 | **ValidationNPlusOne** | `validates :x, uniqueness: true` olan modellerde loop içinde `Model.create`/`save` |

EagerEye preload'ları sayfalama wrapper'ları (`pagy`, `paginate`, `kaminari`), per-method scope, çok satırlı builder zincirleri ve helper-method parametreleri arasında da takip eder — yani önceden ayarladığın eager-loading'lere saygı gösterir.

<details>
<summary><b>Her detector için detaylı örnekler →</b></summary>

### 1. LoopAssociation

```ruby
# Kötü
posts.each { |post| post.author.name }   # her post için bir query

# İyi — zincirli
posts.includes(:author).each { |post| post.author.name }

# İyi — ayrı satır (preload atama üzerinden takip ediliyor)
@posts = Post.includes(:author)
@posts.each { |post| post.author.name }

# İyi — tek kayıt (N+1 mümkün değil)
@user = User.find(params[:id])
@user.posts.each { |post| post.comments }
```

`.includes`, `.preload`, `.eager_load`, scope'lu `has_many` (`-> { includes(:author) }`) ve `@pagy, items = pagy(...)` gibi sayfalama wrapper'larını tanır.

### 2. SerializerNesting

```ruby
# Kötü
class PostSerializer < Blueprinter::Base
  field :author_name { |post| post.author.name }   # her serialize edilen post için query
end

# İyi — controller'da preload
@posts = Post.includes(:author)
render json: PostSerializer.render(@posts)
```

Blueprinter, ActiveModel::Serializers ve Alba'yı destekler.

Render-site farkında: EagerEye serializer'ın nerede render edildiğini tarar
(`PostBlueprint.render(...)`, AMS `serializer:` / `each_serializer:`) ve ilişki o view'ın
her render noktasında preload edilmişse ya da serializer'a yalnızca tek kayıt geçiliyorsa
sessiz kalır. Hiç render edildiğini görmediği bir view yine raporlanır.

### 3. MissingCounterCache

```ruby
# Kötü — her post için COUNT sorgusu
posts.each { |post| post.comments.count }

# İyi — counter cache (Comment: belongs_to :post, counter_cache: true)
posts.each { |post| post.comments_count }   # kolon okuma, query yok
```

Sadece iterasyon içinde flag'lenir — tek seferlik çağrılar N+1 oluşturmaz.

### 4. CustomMethodQuery

```ruby
# Kötü — loop içinde where
@users.each { |user| user.teams.where(name: "Lakers").exists? }

# İyi — preload + Ruby'de filtreleme
@users.includes(:teams).each { |user| user.teams.any? { |t| t.name == "Lakers" } }
```

Tespit edilen: `where`, `find_by`, `exists?`, `find`, `first`, `last`, `take`, `pluck`, `count`, `sum`, `average`, `minimum`, `maximum`. Per-model scope'lu — başka bir model'de `def foo` query metodu var diye `obj.foo`'yu flag'lemez.

### 5. CountInIteration

```ruby
# Kötü — .count includes olsa bile her zaman query atar
@users = User.includes(:posts)
@users.each { |user| user.posts.count }   # her user için SELECT COUNT(*)

# İyi — .size preload'u kullanır
@users.each { |user| user.posts.size }
```

| Metod | Yüklenmiş | Yüklenmemiş |
|---|---|---|
| `.count` | COUNT sorgusu | COUNT sorgusu |
| `.size` | array#size | COUNT sorgusu |
| `.length` | array#length | hepsini yükler sonra sayar |

### 6. CallbackQuery

```ruby
# Kötü — callback içinde N+1
class Order < ApplicationRecord
  after_create :notify_subscribers

  def notify_subscribers
    customer.followers.each { |f| f.notifications.create!(...) }   # N insert + N query
  end
end

# İyi — background job'a devret
after_commit :schedule_notifications, on: :create
def schedule_notifications
  NotifySubscribersJob.perform_later(id)
end
```

### 7. PluckToArray

```ruby
# Uyarı — iki sorgu + bellek maliyeti
user_ids = User.active.pluck(:id)
Post.where(user_id: user_ids)

# Hata — tüm tabloyu yükler
user_ids = User.all.pluck(:id)
Post.where(user_id: user_ids)

# İyi — tek subquery
Post.where(user_id: User.active.select(:id))
```

`.where(...).all.pluck(:id)` doğru şekilde scope'lu olarak tanınır, table scan olarak değil.

### 8. DelegationNPlusOne

```ruby
class Order < ApplicationRecord
  belongs_to :user
  delegate :full_name, :email, to: :user
end

# Kötü — attribute erişimi gibi görünür ama her order için user yükler
orders.each { |o| o.full_name }

# İyi
orders.includes(:user).each { |o| o.full_name }
```

Cross-file: model dosyalarını `delegate ... to: :assoc` deklarasyonları için tarar.

### 9. DecoratorNPlusOne

```ruby
class PostDecorator < Draper::Decorator
  def comment_summary
    object.comments.map(&:body).join(", ")   # her decorate edilen post için query
  end
end

# Kötü
@posts = Post.all.decorate

# İyi
@posts = Post.includes(:comments).all.decorate
```

Draper / SimpleDelegator / Presenter / ViewObject sınıfları içinde `object`, `__getobj__`, `source`, `model` referanslarını tanır.

### 10. ScopeChainNPlusOne

```ruby
class Comment < ApplicationRecord
  scope :recent, -> { where("created_at > ?", 1.week.ago) }
end

# Kötü — her iterasyonda scope çağrısı
posts.each { |post| post.comments.recent }

# İyi — preload + filtreleme
posts.includes(:comments).each { |post| post.comments.select { |c| c.created_at > 1.week.ago } }
```

Cross-file: model dosyalarını `scope :name, -> { ... }` deklarasyonları için tarar.

### 11. ValidationNPlusOne

```ruby
class User < ApplicationRecord
  validates :email, uniqueness: true
end

# Kötü — her kayıt için SELECT + INSERT
params[:users].each { |p| User.create!(p) }

# İyi — tek bulk INSERT, DB unique index ile uniqueness'i sağlar
User.insert_all(params[:users])
```

</details>

## Inline suppression

False positive'leri veya bilinçli desenleri RuboCop tarzı yorumlarla bastır:

```ruby
# Tek satır
user.posts.count  # eager_eye:disable CountInIteration

# Sonraki satır
# eager_eye:disable-next-line LoopAssociation
@users.each { |u| u.profile }

# Block
# eager_eye:disable LoopAssociation, SerializerNesting
@users.each { |u| u.posts.each { |p| p.author } }
# eager_eye:enable LoopAssociation, SerializerNesting

# Tüm dosya (ilk 5 satırda olmalı)
# eager_eye:disable-file CustomMethodQuery

# Sebep ile
user.posts.count  # eager_eye:disable CountInIteration -- counter_cache kullanılıyor

# Hepsini kapat
# eager_eye:disable all
```

Detector isimleri hem CamelCase (`LoopAssociation`) hem snake_case (`loop_association`) olarak kabul edilir.

## Auto-fix (deneysel)

```bash
eager_eye --suggest-fixes   # diff'i göster
eager_eye --fix             # interaktif uygula
eager_eye --fix --force     # onay sormadan hepsini uygula
```

| Sorun | Otomatik düzeltme |
|---|---|
| `.where(id: ...)` içinde `.pluck(:id)` | → `.select(:id)` |
| Iterasyon içinde `.count` | → `.size` |
| Loop öncesi eksik `includes` | → `.includes(:assoc)` ekler |

> ⚠ `--fix` sonrası diff'i mutlaka gözden geçir ve testlerini tekrar çalıştır.

## CI entegrasyonu

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
          [ "$issues" -gt 0 ] && echo "::warning::$issues olası N+1 sorunu bulundu" || true
```

PR annotation'lı tam örnek için bkz. [examples/github_action.yml](examples/github_action.yml).

### Baseline modu (brownfield projeler)

Çoğu mevcut Rails uygulamasında zaten yüzlerce N+1 sorunu var — her birinde
CI'yi düşürmek anlamlı değil. Bugünkü raporu baseline olarak yakalayıp CI'nin
**sadece regresyonlarda** (PR'ın eklediği yeni issue'larda) fail etmesini
sağlayabilirsiniz:

```bash
# Tek seferlik: mevcut durumu baseline olarak yakala
eager_eye app/ --format json > .eager_eye_baseline.json

# CI'da: yalnızca YENİ issue'lar sayılır
eager_eye app/ --baseline .eager_eye_baseline.json
```

Baseline dosyası standart `--format json` raporudur. Mevcut issue'ları
düzelttikçe baseline'ı yenileyin. Eşleşme anahtarı: `(detector, file_path,
line_number, message, severity, suggestion)` — bilinen bir issue'da bu
alanlardan biri değişirse baseline yenilenene kadar "yeni" olarak görünür.

## RSpec entegrasyonu

```ruby
# spec/rails_helper.rb
require "eager_eye/rspec"

# spec/eager_eye_spec.rb
RSpec.describe "EagerEye Analizi" do
  it "controller'larda N+1 yok" do
    expect("app/controllers").to pass_eager_eye
  end

  it "serializer'lar temiz" do
    expect("app/serializers").to pass_eager_eye(only: [:serializer_nesting])
  end

  # Migration sırasında bir miktar tolere et
  it "legacy kod kabul edilebilir" do
    expect("app/services/legacy").to pass_eager_eye(max_issues: 10)
  end
end
```

Matcher seçenekleri: `only:` (Array<Symbol>), `exclude:` (Array<String> glob'lar), `max_issues:` (Integer, varsayılan 0).

## Yapılandırma

`rails g eager_eye:install` bir `.eager_eye.yml` oluşturur; bu dosyayı `rake eager_eye:*`
görevleri `Rails.root`'tan yükler. `eager_eye` CLI'ı bu dosyayı okumaz — karşılığı olan
flag'leri (`--exclude`, `--only`, `--min-severity`, `--no-fail`) kullan.

```yaml
# .eager_eye.yml  (rake eager_eye:analyze / eager_eye:json tarafından okunur)
excluded_paths:
  - app/legacy/**
  - lib/tasks/**

enabled_detectors:        # varsayılan: hepsi
  - loop_association
  - serializer_nesting
  - custom_method_query
  # ...

app_path: app
fail_on_issues: true
```

Severity eşiği ve detector başına severity programatik olarak (veya CLI'da
`--min-severity` ile) ayarlanır:

```ruby
EagerEye.configure do |config|
  config.excluded_paths = ["app/legacy/**"]
  config.enabled_detectors = [:loop_association, :serializer_nesting]
  config.min_severity = :warning
  config.fail_on_issues = true
end
```

## CLI referansı

```text
Kullanım: eager_eye [yollar] [seçenekler]

  -f, --format FORMAT       console | json (varsayılan: console)
  -e, --exclude PATTERN     hariç tutulacak glob (tekrarlanabilir)
  -o, --only DETECTORS      virgülle ayrılmış detector listesi
  -s, --min-severity LEVEL  info | warning | error
      --no-fail             her zaman 0 ile çık
      --no-color            düz çıktı
      --baseline FILE       önceki bir JSON raporuyla karşılaştır;
                            sadece YENİ issue'lar raporlanır (ve sayılır)
      --suggest-fixes       fix diff'lerini uygulamadan göster
      --fix                 interaktif olarak auto-fix uygula
      --fix --force         tüm auto-fix'leri uygula
  -v, --version
  -h, --help
```

## Limitasyonlar

EagerEye statik analiz yapar. Bunun trade-off'ları var:

- **Runtime context yok** — `find_each` block'unun runtime'da gerçekten ne yaptığını göremez.
- **Heuristic ilişki tespiti** — model parse setinde olmadığında yaygın isim desenlerine (`author`, `user`, ...) düşer; küçük edge case'lerde fazla flag'leyebilir.
- **Cross-file akış** — preload'ları aynı sınıftaki metodlar arasında takip eder (controller → kendi private helper'ları), ama cross-file akış (controller → harici service object → iterasyon) henüz takip edilmiyor.
- **Model keşfi yola bağlı** — ilişkiler, `delegate`, `scope` ve uniqueness validation'ları `<taranan ilk yol>/models/**` altından okunur. Tek bir dosya veya `app/controllers` taranırsa bu adım atlanır; `DelegationNPlusOne`, `ScopeChainNPlusOne` ve `ValidationNPlusOne` çalışmaz, ilişki tespiti isim heuristic'lerine düşer. `app/` tara.
- **Şema, veritabanı değil** — kolon isimlerini öğrenip kolonları ilişkiyle karıştırmamak için `db/schema.rb`'yi okur (taranan yoldan yukarı doğru arar); veritabanına bağlanmaz, SQL parse etmez. `schema.rb` bulunamazsa koruma sessizce devre dışı kalır; dosya var ama parse edilemiyorsa bir uyarı basılır.
- **Parse edilemeyen dosyalar atlanır** — `parser` gem'inin lex edemediği bir dosya (geçersiz UTF-8 escape, bilinmeyen `# encoding:` yorumu, syntax hatası) tek bir `EagerEye: Skipped unparseable file ...` uyarısıyla analizden düşer. Liste programatik olarak `Analyzer#skipped_files` ile alınabilir.

Tam kapsama için [Bullet](https://github.com/flyerhzm/bullet) ile birlikte kullan: statik (EagerEye) test'lerin girmediği yolları, runtime (Bullet) statik analizin göremediklerini yakalar.

## Geliştirme

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
bin/console
```

## Katkı

Bug raporları ve PR'lar için: <https://github.com/hamzagedikkaya/eager_eye>.

1. Fork'la
2. `git checkout -b feature/yeni-ozellik`
3. Spec ekle (bu repo ~%95 coverage'da)
4. `git commit -am 'yeni özellik ekle'`
5. Pull Request aç

## Lisans

MIT — bkz. [LICENSE.txt](LICENSE.txt).

## Davranış Kuralları

EagerEye'ın codebase'inde, issue tracker'larında ve tartışmalarında etkileşime giren herkesin [davranış kurallarına](CODE_OF_CONDUCT.md) uyması beklenir.
