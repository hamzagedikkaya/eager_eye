# frozen_string_literal: true

RSpec.describe EagerEye::ValidationParser do
  let(:parser) { described_class.new }

  describe "#parse_model" do
    def parse(source)
      EagerEye::SourceParser.parse(source)
    end

    it "detects validates with uniqueness option" do
      source = <<~RUBY
        class User < ApplicationRecord
          validates :email, uniqueness: true
        end
      RUBY

      parser.parse_model(parse(source), "User")

      expect(parser.uniqueness_models).to include("User")
    end

    it "detects validates_uniqueness_of" do
      source = <<~RUBY
        class User < ApplicationRecord
          validates_uniqueness_of :email
        end
      RUBY

      parser.parse_model(parse(source), "User")

      expect(parser.uniqueness_models).to include("User")
    end

    it "detects uniqueness with scope option" do
      source = <<~RUBY
        class Membership < ApplicationRecord
          validates :user_id, uniqueness: { scope: :team_id }
        end
      RUBY

      parser.parse_model(parse(source), "Membership")

      expect(parser.uniqueness_models).to include("Membership")
    end

    it "does not flag non-uniqueness validations" do
      source = <<~RUBY
        class Post < ApplicationRecord
          validates :title, presence: true
          validates :body, length: { minimum: 10 }
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.uniqueness_models).to be_empty
    end

    it "handles nil AST" do
      parser.parse_model(nil, "Post")

      expect(parser.uniqueness_models).to be_empty
    end

    it "handles multiple models" do
      source1 = <<~RUBY
        class User < ApplicationRecord
          validates :email, uniqueness: true
        end
      RUBY

      source2 = <<~RUBY
        class Post < ApplicationRecord
          validates :title, presence: true
        end
      RUBY

      parser.parse_model(parse(source1), "User")
      parser.parse_model(parse(source2), "Post")

      expect(parser.uniqueness_models).to eq(Set["User"])
    end
  end
end
