# frozen_string_literal: true

# Regression coverage for the false-positive fixes: each example encodes a
# real-world pattern that previously produced a false positive on production
# apps and must stay silent, paired with a genuine N+1 that must still fire.
RSpec.describe "false-positive regressions" do
  def parse(source)
    Parser::CurrentRuby.parse(source)
  end

  describe EagerEye::Detectors::LoopAssociation do
    let(:detector) { described_class.new }

    it "does not flag a method the schema knows as a column on an unknown model" do
      source = <<~RUBY
        eods.each { |s_eod| total += s_eod.vat_rate }
      RUBY
      columns = Set.new(%i[vat_rate])
      issues = detector.detect(parse(source), "w.rb", {}, Set.new, {}, {}, columns)
      expect(issues).to be_empty
    end

    it "still flags a real association on an unknown model when it is not a column" do
      source = <<~RUBY
        awards.each { |award| award.prize_point }
      RUBY
      assoc_names = Set.new(%i[prize_point])
      issues = detector.detect(parse(source), "w.rb", {}, assoc_names, {}, {}, Set.new)
      expect(issues.size).to eq(1)
    end

    it "reports a memoized association read only once per iteration (dedup)" do
      source = <<~RUBY
        awards.each do |award|
          award.prize.present?
          award.prize.name
          award.prize
        end
      RUBY
      assoc = { "Award" => Set.new(%i[prize]) }
      issues = detector.detect(parse(source), "w.rb", {}, Set.new(%i[prize]), {}, assoc, Set.new)
      expect(issues.size).to eq(1)
    end

    it "reports each occurrence when the association is a query-chain base (re-queries)" do
      source = <<~RUBY
        missions.each do |mission|
          mission.subscriptions.find_by(user: a)
          mission.subscriptions.find_by(user: b)
        end
      RUBY
      issues = detector.detect(parse(source), "w.rb", {}, Set.new(%i[subscriptions]), {}, {}, Set.new)
      expect(issues.size).to eq(2)
    end
  end

  describe EagerEye::Detectors::CustomMethodQuery do
    let(:detector) { described_class.new }

    it "does not flag a relation query method called directly on the iteration element (SELECT alias)" do
      source = <<~RUBY
        eods.each { |s_eod| ids << s_eod.ids }
      RUBY
      issues = detector.detect(parse(source), "w.rb")
      expect(issues).to be_empty
    end

    it "does not flag an Enumerable aggregate with a block argument" do
      # `.sum(&:amount)` runs in Ruby over the already-loaded association, not as
      # a SQL SUM — the block-pass argument is the tell.
      source = <<~RUBY
        invoices.each { |invoice| invoice.offsets.sum(&:amount) }
      RUBY
      issues = detector.detect(parse(source), "w.rb")
      expect(issues).to be_empty
    end

    it "does not flag per-batch queries inside in_batches" do
      source = <<~RUBY
        Transaction.in_batches(of: 500).each do |batch|
          batch.pluck(:id)
        end
      RUBY
      issues = detector.detect(parse(source), "w.rb")
      expect(issues).to be_empty
    end

    it "still flags a query method on an association of an inferred model" do
      source = <<~RUBY
        users = User.all
        users.each { |user| user.teams.where(active: true) }
      RUBY
      issues = detector.detect(parse(source), "w.rb")
      expect(issues.size).to eq(1)
    end
  end

  describe EagerEye::Detectors::ValidationNPlusOne do
    let(:detector) { described_class.new }
    let(:uniqueness) { Set.new(%w[Card]) }

    it "does not flag a save that skips validations" do
      source = <<~RUBY
        cards.each do |card|
          card.update_column(:x, 1)
          record = Card.new
          record.save(validate: false)
        end
      RUBY
      issues = detector.detect(parse(source), "w.rb", uniqueness)
      expect(issues).to be_empty
    end

    it "still flags a validated save in a loop" do
      source = <<~RUBY
        rows.each do |row|
          record = Card.new
          record.save
        end
      RUBY
      issues = detector.detect(parse(source), "w.rb", uniqueness)
      expect(issues.size).to eq(1)
    end
  end

  describe EagerEye::Detectors::SerializerNesting do
    let(:detector) { described_class.new }

    def usage_for(source)
      parser = EagerEye::SerializerUsageParser.new
      parser.parse_file(parse(source))
      parser
    end

    it "suppresses an association eager-loaded at every render site" do
      serializer = <<~RUBY
        class UserBlueprint < Blueprinter::Base
          field :org do |user| user.organization.name end
        end
      RUBY
      render = <<~RUBY
        def index
          users = User.includes(:organization)
          UserBlueprint.render_as_hash(users)
        end
      RUBY
      issues = detector.detect(parse(serializer), "s.rb", Set.new(%i[organization]), {}, usage_for(render))
      expect(issues).to be_empty
    end

    it "suppresses when the serializer is only ever handed a single record" do
      serializer = <<~RUBY
        class UserBlueprint < Blueprinter::Base
          field :org do |user| user.organization.name end
        end
      RUBY
      render = <<~RUBY
        def show
          user = User.find(params[:id])
          UserBlueprint.render_as_hash(user)
        end
      RUBY
      issues = detector.detect(parse(serializer), "s.rb", Set.new(%i[organization]), {}, usage_for(render))
      expect(issues).to be_empty
    end

    it "still flags an association not preloaded at a collection render site" do
      serializer = <<~RUBY
        class UserBlueprint < Blueprinter::Base
          field :org do |user| user.organization.name end
        end
      RUBY
      render = <<~RUBY
        def index
          users = User.all
          UserBlueprint.render_as_hash(users)
        end
      RUBY
      issues = detector.detect(parse(serializer), "s.rb", Set.new(%i[organization]), {}, usage_for(render))
      expect(issues.size).to eq(1)
    end
  end
end
