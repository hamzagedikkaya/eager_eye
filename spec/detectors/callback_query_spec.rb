# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::CallbackQuery do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :callback_query" do
      expect(described_class.detector_name).to eq(:callback_query)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "when query is inside after_save callback" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats

            private

            def update_stats
              author.articles.count
            end
          end
        RUBY
      end

      it "detects the query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("after_save")
        expect(issues.first.message).to include(".count")
      end
    end

    context "when query is inside before_create callback" do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            before_create :set_position

            def set_position
              self.position = author.posts.maximum(:position).to_i + 1
            end
          end
        RUBY
      end

      it "detects the query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("before_create")
        expect(issues.first.message).to include(".maximum")
      end
    end

    context "when iteration is inside callback" do
      let(:code) do
        <<~RUBY
          class Order < ApplicationRecord
            after_create :notify_subscribers

            private

            def notify_subscribers
              customer.followers.each do |f|
                f.notify!
              end
            end
          end
        RUBY
      end

      it "detects the iteration as error" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        iteration_issue = issues.find { |i| i.message.include?("Iteration") }
        expect(iteration_issue).not_to be_nil
        expect(iteration_issue.severity).to eq(:error)
      end
    end

    context "when update is inside callback" do
      let(:code) do
        <<~RUBY
          class Comment < ApplicationRecord
            after_create :increment_counter

            private

            def increment_counter
              post.update!(comments_count: post.comments.count)
            end
          end
        RUBY
      end

      it "detects the update query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.any? { |i| i.message.include?(".update!") }).to be true
      end

      it "detects the count query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.any? { |i| i.message.include?(".count") }).to be true
      end
    end

    context "when method is not a callback" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            def recalculate
              author.articles.count
            end
          end
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with after_commit callback" do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            after_commit :sync_to_search

            private

            def sync_to_search
              related_posts.each { |p| p.touch }
            end
          end
        RUBY
      end

      it "detects issues in after_commit" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).not_to be_empty
        expect(issues.first.message).to include("after_commit")
      end
    end

    context "with after_create_commit callback" do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            after_create_commit :send_welcome_email

            def send_welcome_email
              organization.admins.each { |a| AdminMailer.notify(a).deliver_later }
            end
          end
        RUBY
      end

      it "detects iteration in after_create_commit" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        iteration_issue = issues.find { |i| i.message.include?("Iteration") }
        expect(iteration_issue.message).to include("after_create_commit")
      end
    end

    context "with before_validation callback" do
      let(:code) do
        <<~RUBY
          class Product < ApplicationRecord
            before_validation :ensure_unique_sku

            def ensure_unique_sku
              while Product.exists?(sku: sku)
                self.sku = generate_new_sku
              end
            end
          end
        RUBY
      end

      it "detects exists? in before_validation" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.any? { |i| i.message.include?(".exists?") }).to be true
        expect(issues.first.message).to include("before_validation")
      end
    end

    context "with multiple callbacks to same method" do
      let(:code) do
        <<~RUBY
          class Invoice < ApplicationRecord
            after_save :recalculate_totals
            after_update :recalculate_totals

            def recalculate_totals
              line_items.sum(:amount)
            end
          end
        RUBY
      end

      it "detects the query (method registered once)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".sum")
      end
    end

    context "with destroy callbacks" do
      let(:code) do
        <<~RUBY
          class Category < ApplicationRecord
            before_destroy :reassign_articles

            def reassign_articles
              articles.update_all(category_id: nil)
            end
          end
        RUBY
      end

      it "detects update_all in before_destroy" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.any? { |i| i.message.include?(".update_all") }).to be true
        expect(issues.first.message).to include("before_destroy")
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats

            def update_stats
              author.articles.count
            end
          end
        RUBY
      end

      it "includes suggestion about background jobs" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.suggestion).to include("background job")
      end

      it "sets correct file_path" do
        ast = parse(code)
        issues = detector.detect(ast, "app/models/article.rb")

        expect(issues.first.file_path).to eq("app/models/article.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats
            def update_stats
              author.articles.count
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Line 4 is where author.articles.count is called
        expect(issues.first.line_number).to eq(4)
      end
    end
  end
end
