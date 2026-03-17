# frozen_string_literal: true

RSpec.describe EagerEye::MethodQueryParser do
  let(:parser) { described_class.new }

  describe "#parse_model" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    it "detects methods containing where queries" do
      source = <<~RUBY
        class Post < ApplicationRecord
          def recent_comments
            Comment.where("created_at > ?", 1.week.ago)
          end
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.method_queries["Post"]).to include(:recent_comments)
    end

    it "detects methods containing find_by queries" do
      source = <<~RUBY
        class User < ApplicationRecord
          def primary_address
            Address.find_by(primary: true, user_id: id)
          end
        end
      RUBY

      parser.parse_model(parse(source), "User")

      expect(parser.method_queries["User"]).to include(:primary_address)
    end

    it "detects methods containing count queries" do
      source = <<~RUBY
        class Post < ApplicationRecord
          def comments_count
            comments.count
          end
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.method_queries["Post"]).to include(:comments_count)
    end

    it "detects methods containing exists? queries" do
      source = <<~RUBY
        class Order < ApplicationRecord
          def has_refund?
            Refund.exists?(order_id: id)
          end
        end
      RUBY

      parser.parse_model(parse(source), "Order")

      expect(parser.method_queries["Order"]).to include(:has_refund?)
    end

    it "detects methods containing pluck queries" do
      source = <<~RUBY
        class Team < ApplicationRecord
          def member_names
            members.pluck(:name)
          end
        end
      RUBY

      parser.parse_model(parse(source), "Team")

      expect(parser.method_queries["Team"]).to include(:member_names)
    end

    it "collects multiple query methods from a single model" do
      source = <<~RUBY
        class Post < ApplicationRecord
          def recent_comments
            comments.where("created_at > ?", 1.day.ago)
          end

          def top_comment
            comments.find_by(featured: true)
          end

          def display_title
            title.upcase
          end
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.method_queries["Post"]).to include(:recent_comments, :top_comment)
      expect(parser.method_queries["Post"]).not_to include(:display_title)
    end

    it "does not detect methods without queries" do
      source = <<~RUBY
        class Post < ApplicationRecord
          def full_title
            "\#{title} by \#{author_name}"
          end

          def slug
            title.parameterize
          end
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.method_queries).to be_empty
    end

    it "handles multiple models" do
      source1 = <<~RUBY
        class Post < ApplicationRecord
          def recent_comments
            comments.where("created_at > ?", 1.week.ago)
          end
        end
      RUBY

      source2 = <<~RUBY
        class User < ApplicationRecord
          def active_orders
            orders.where(active: true)
          end
        end
      RUBY

      parser.parse_model(parse(source1), "Post")
      parser.parse_model(parse(source2), "User")

      expect(parser.method_queries["Post"]).to include(:recent_comments)
      expect(parser.method_queries["User"]).to include(:active_orders)
    end

    it "handles nil AST" do
      parser.parse_model(nil, "Post")

      expect(parser.method_queries).to be_empty
    end

    it "detects nested query calls within conditionals" do
      source = <<~RUBY
        class Post < ApplicationRecord
          def featured_comment
            if published?
              comments.find_by(featured: true)
            end
          end
        end
      RUBY

      parser.parse_model(parse(source), "Post")

      expect(parser.method_queries["Post"]).to include(:featured_comment)
    end

    it "detects sum and average aggregate queries" do
      source = <<~RUBY
        class Order < ApplicationRecord
          def total_amount
            line_items.sum(:price)
          end

          def average_rating
            reviews.average(:score)
          end
        end
      RUBY

      parser.parse_model(parse(source), "Order")

      expect(parser.method_queries["Order"]).to include(:total_amount, :average_rating)
    end
  end
end
