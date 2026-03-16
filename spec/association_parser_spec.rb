# frozen_string_literal: true

require "spec_helper"

RSpec.describe EagerEye::AssociationParser do
  let(:parser) { described_class.new }

  describe "#parse_model" do
    it "extracts has_many associations with preload scopes" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { includes(:author) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author)
    end

    it "extracts has_one associations with preload scopes" do
      code = <<~RUBY
        class User < ApplicationRecord
          has_one :profile, -> { includes(:avatar) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "User")

      expect(parser.preloaded_associations["User#profile"]).to include(:avatar)
    end

    it "extracts belongs_to associations with preload scopes" do
      code = <<~RUBY
        class Comment < ApplicationRecord
          belongs_to :post, -> { includes(:author) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Comment")

      expect(parser.preloaded_associations["Comment#post"]).to include(:author)
    end

    it "handles multiple preloads in a single scope" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { includes(:author, :likes) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author, :likes)
    end

    it "handles preload method instead of includes" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { preload(:author) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author)
    end

    it "handles eager_load method" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { eager_load(:author) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author)
    end

    it "ignores associations without preload scope" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations).to be_empty
    end

    it "handles complex scope blocks with other methods" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { includes(:author).where(active: true).order(:created_at) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author)
    end

    it "ignores non-association method calls" do
      code = <<~RUBY
        class Post < ApplicationRecord
          def comments_with_authors
            comments.includes(:author)
          end
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations).to be_empty
    end

    it "handles has_and_belongs_to_many associations" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_and_belongs_to_many :tags, -> { includes(:category) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#tags"]).to include(:category)
    end

    it "returns nil when ast is nil" do
      expect(parser.parse_model(nil, "Post")).to be_nil
      expect(parser.preloaded_associations).to be_empty
    end

    it "stores preloads with correct key format" do
      code = <<~RUBY
        class Article < ApplicationRecord
          has_many :comments, -> { includes(:author) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Article")

      expect(parser.preloaded_associations.keys).to include("Article#comments")
    end

    it "handles nested includes with hash syntax" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { includes(author: :profile) }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      expect(parser.preloaded_associations["Post#comments"]).to include(:author)
    end

    it "handles multiple association definitions" do
      code = <<~RUBY
        class User < ApplicationRecord
          has_many :posts, -> { includes(:comments) }
          has_many :likes, -> { includes(:post) }
          has_one :profile
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "User")

      expect(parser.preloaded_associations.size).to eq(2)
      expect(parser.preloaded_associations["User#posts"]).to include(:comments)
      expect(parser.preloaded_associations["User#likes"]).to include(:post)
      expect(parser.preloaded_associations).not_to have_key("User#profile")
    end

    it "collects all association names" do
      code = <<~RUBY
        class User < ApplicationRecord
          has_many :posts
          has_one :profile
          belongs_to :company
          has_many :enrollments
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "User")

      expect(parser.association_names).to include(:posts, :profile, :company, :enrollments)
    end

    it "collects association names even without preload scopes" do
      code = <<~RUBY
        class Order < ApplicationRecord
          has_many :subscriptions
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Order")

      expect(parser.association_names).to include(:subscriptions)
      expect(parser.preloaded_associations).to be_empty
    end

    it "handles edge case with empty includes" do
      code = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments, -> { includes() }
        end
      RUBY

      ast = Parser::CurrentRuby.parse(code)
      parser.parse_model(ast, "Post")

      # Empty includes should not add to preloaded_associations
      expect(parser.preloaded_associations["Post#comments"]).to be_nil
    end
  end
end
