# frozen_string_literal: true

RSpec.describe EagerEye::ScopeParser do
  let(:parser) { described_class.new }

  describe "#parse_model" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    it "extracts scope definitions from model" do
      source = <<~RUBY
        class Comment < ApplicationRecord
          scope :recent, -> { where("created_at > ?", 1.week.ago) }
          scope :approved, -> { where(approved: true) }
        end
      RUBY

      parser.parse_model(parse(source), "Comment")

      expect(parser.scope_maps["Comment"]).to eq(Set[:recent, :approved])
    end

    it "handles multiple models" do
      source1 = <<~RUBY
        class Post < ApplicationRecord
          scope :published, -> { where(published: true) }
        end
      RUBY

      source2 = <<~RUBY
        class Comment < ApplicationRecord
          scope :recent, -> { where("created_at > ?", 1.week.ago) }
        end
      RUBY

      parser.parse_model(parse(source1), "Post")
      parser.parse_model(parse(source2), "Comment")

      expect(parser.scope_maps["Post"]).to eq(Set[:published])
      expect(parser.scope_maps["Comment"]).to eq(Set[:recent])
    end

    it "ignores non-scope methods" do
      source = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments
          belongs_to :author
          validates :title, presence: true
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.scope_maps).to be_empty
    end

    it "handles nil AST" do
      parser.parse_model(nil, "Post")

      expect(parser.scope_maps).to be_empty
    end
  end
end
