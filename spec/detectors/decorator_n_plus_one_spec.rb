# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::DecoratorNPlusOne do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :decorator_n_plus_one" do
      expect(described_class.detector_name).to eq(:decorator_n_plus_one)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with Draper::Decorator subclass" do
      it "detects has_many association access via object" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def comment_summary
              object.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:decorator_n_plus_one)
        expect(issues.first.message).to include("object.comments")
        expect(issues.first.line_number).to eq(3)
      end

      it "detects multiple association accesses across methods" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def tag_list
              object.tags.map(&:name)
            end

            def author_list
              object.authors.map(&:bio)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end

      it "detects multiple associations in one method" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def summary
              { comments: object.comments.count, tags: object.tags.map(&:name) }
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with SimpleDelegator subclass" do
      it "detects association access via __getobj__" do
        source = <<~RUBY
          class OrderDecorator < SimpleDelegator
            def item_names
              __getobj__.items.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("__getobj__.items")
      end
    end

    context "with Delegator subclass" do
      it "detects association access via object" do
        source = <<~RUBY
          class ReportDecorator < Delegator
            def row_data
              object.items.map(&:value)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with class name patterns" do
      it "detects in classes ending with Decorator" do
        source = <<~RUBY
          class UserDecorator
            def post_titles
              object.posts.map(&:title)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects in classes ending with Presenter" do
        source = <<~RUBY
          class UserPresenter
            def recent_posts
              model.posts.last(5)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("model.posts")
      end

      it "detects in classes ending with ViewObject" do
        source = <<~RUBY
          class InvoiceViewObject
            def order_list
              object.orders.map(&:total)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with different object references" do
      it "detects via source reference" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def tag_names
              source.tags.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("source.tags")
      end

      it "detects via model reference" do
        source = <<~RUBY
          class UserPresenter
            def subscription_list
              model.accounts.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("model.accounts")
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect in non-decorator classes" do
        source = <<~RUBY
          class PostsController
            def index
              object.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect plain attribute access" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def formatted_title
              object.title.upcase
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect belongs_to style singular associations" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def author_name
              object.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect ActiveStorage attachment calls" do
        source = <<~RUBY
          class UserDecorator < Draper::Decorator
            def avatar_url
              object.avatar.attached? ? object.avatar.url : nil
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when receiver is not an object reference" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def related_comments
              @post.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      it "includes suggestion to eager load in controller" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def tag_names
              object.tags.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("Eager load")
        expect(issues.first.suggestion).to include(":tags")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def comment_list
              object.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "app/decorators/post_decorator.rb")

        expect(issues.first.file_path).to eq("app/decorators/post_decorator.rb")
      end

      it "sets correct line number" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def comment_list
              object.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "with cross-file method queries" do
      it "detects model query method in decorator" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def comment_summary
              object.cached_comment_count
            end
          end
        RUBY

        method_queries = { "Post" => Set[:cached_comment_count] }
        issues = detector.detect(parse(source), "test.rb", Set.new, method_queries)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("cached_comment_count")
        expect(issues.first.message).to include("query method defined in the model")
      end

      it "does not detect model query method without method_queries data" do
        source = <<~RUBY
          class PostDecorator < Draper::Decorator
            def comment_summary
              object.cached_comment_count
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "detects both association and model query method" do
        source = <<~RUBY
          class OrderDecorator < Draper::Decorator
            def details
              object.items.map(&:name)
            end

            def total
              object.compute_total
            end
          end
        RUBY

        method_queries = { "Order" => Set[:compute_total] }
        issues = detector.detect(parse(source), "test.rb", Set.new, method_queries)

        expect(issues.size).to eq(2)
        messages = issues.map(&:message)
        expect(messages).to include(a_string_including("items"))
        expect(messages).to include(a_string_including("compute_total"))
      end
    end

    context "with fixture files" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in decorator_n_plus_one_bad.rb" do
        file_path = File.join(fixtures_path, "decorator_n_plus_one_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues.size).to be >= 5
      end

      it "detects no issues in decorator_n_plus_one_good.rb" do
        file_path = File.join(fixtures_path, "decorator_n_plus_one_good.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues).to be_empty
      end
    end
  end
end
