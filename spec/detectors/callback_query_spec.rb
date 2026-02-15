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

    context "when single query is inside after_save callback" do
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

      it "does not detect single query (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when query is inside iteration in after_save callback" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats

            private

            def update_stats
              authors.each do |author|
                author.articles.count
              end
            end
          end
        RUBY
      end

      it "detects the query inside iteration" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        query_issue = issues.find { |i| i.message.include?(".count") }
        expect(query_issue).not_to be_nil
        expect(query_issue.message).to include("after_save")
      end
    end

    context "when single query is inside before_create callback" do
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

      it "does not detect single query (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when iteration is inside callback with AR query on iteration variable" do
      let(:code) do
        <<~RUBY
          class Order < ApplicationRecord
            after_create :notify_subscribers

            private

            def notify_subscribers
              customer.followers.each do |f|
                f.notifications.create!(message: "New order")
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

    context "when iteration is inside callback without AR query (e.g., Redis/Sidekiq)" do
      let(:code) do
        <<~RUBY
          class Job < ApplicationRecord
            after_destroy :delete_reset_job

            private

            def delete_reset_job
              Sidekiq::ScheduledSet.new.select { |job| job.item["args"].include?(id) }.each(&:delete)
            end
          end
        RUBY
      end

      it "does not detect iteration without AR query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when iteration has non-AR method call on iteration variable" do
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

      it "does not detect iteration without AR query methods" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when iteration is over a constant array" do
      let(:code) do
        <<~RUBY
          class Order < ApplicationRecord
            CONDITIONS = [:pending, :shipped].freeze

            after_save :handle_conditions

            def handle_conditions
              CONDITIONS.each { |c| send("handle_\#{c}") }
            end
          end
        RUBY
      end

      it "does not detect iteration over constant" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when iteration is over an inline array" do
      let(:code) do
        <<~RUBY
          class Order < ApplicationRecord
            after_save :set_flags

            def set_flags
              [:flag1, :flag2].each { |f| self.send("\#{f}=", true) }
            end
          end
        RUBY
      end

      it "does not detect iteration over inline array" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when iteration is over a range" do
      let(:code) do
        <<~RUBY
          class Order < ApplicationRecord
            after_save :process_range

            def process_range
              (1..5).each { |i| process_item(i) }
            end
          end
        RUBY
      end

      it "does not detect iteration over range" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when single update is inside callback" do
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

      it "does not detect single update (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when update is inside iteration in callback" do
      let(:code) do
        <<~RUBY
          class Comment < ApplicationRecord
            after_create :update_all_counters

            private

            def update_all_counters
              posts.each do |post|
                post.update!(comments_count: post.comments.count)
              end
            end
          end
        RUBY
      end

      it "detects the update query inside iteration" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.any? { |i| i.message.include?(".update!") }).to be true
      end

      it "detects the count query inside iteration" do
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

    context "with after_commit callback containing AR query" do
      let(:code) do
        <<~RUBY
          class Post < ApplicationRecord
            after_commit :sync_to_search

            private

            def sync_to_search
              related_posts.each { |p| p.comments.update_all(synced: true) }
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

    context "with after_commit callback without AR query" do
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

      it "does not detect iteration without AR query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with after_create_commit callback containing AR query" do
      let(:code) do
        <<~RUBY
          class User < ApplicationRecord
            after_create_commit :send_welcome_email

            def send_welcome_email
              organization.admins.each { |a| a.notifications.create!(message: "Welcome!") }
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

    context "with after_create_commit callback without AR query" do
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

      it "does not detect iteration without AR query" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with single exists? in before_validation callback" do
      let(:code) do
        <<~RUBY
          class Product < ApplicationRecord
            before_validation :ensure_unique_sku

            def ensure_unique_sku
              if Product.exists?(sku: sku)
                self.sku = generate_new_sku
              end
            end
          end
        RUBY
      end

      it "does not detect single exists? (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with multiple callbacks to same method with single query" do
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

      it "does not detect single query (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with multiple callbacks to same method with iteration" do
      let(:code) do
        <<~RUBY
          class Invoice < ApplicationRecord
            after_save :recalculate_totals
            after_update :recalculate_totals

            def recalculate_totals
              line_items.each do |item|
                item.update!(calculated_total: item.amount * item.quantity)
              end
            end
          end
        RUBY
      end

      it "detects query inside iteration" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        iteration_issue = issues.find { |i| i.message.include?("Iteration") }
        expect(iteration_issue).not_to be_nil
      end
    end

    context "with single update_all in destroy callback" do
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

      it "does not detect single update_all (not N+1)" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "when query inside iteration is NOT on the iteration variable (false positive case)" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :process_items

            def process_items
              items.each do |item|
                SomeService.call(item.name)
                OtherModel.where(name: item.name).first
              end
            end
          end
        RUBY
      end

      it "does not flag query or iteration when iteration variable is not the receiver" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        # Should have no issues since no AR query on iteration variable
        expect(issues).to be_empty
      end
    end

    context "when query inside iteration IS on the iteration variable" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :process_items

            def process_items
              items.each do |item|
                item.related_items.where(active: true).first
              end
            end
          end
        RUBY
      end

      it "flags query when iteration variable is the receiver" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        query_issues = issues.select { |i| i.message.include?("Query method") }
        expect(query_issues).not_to be_empty
      end
    end

    context "issue attributes" do
      let(:code) do
        <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats

            def update_stats
              authors.each do |author|
                author.articles.count
              end
            end
          end
        RUBY
      end

      it "includes suggestion about background jobs for iteration issues" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        iteration_issue = issues.find { |i| i.message.include?("Iteration") }
        expect(iteration_issue.suggestion).to include("background job")
      end

      it "sets correct file_path" do
        ast = parse(code)
        issues = detector.detect(ast, "app/models/article.rb")

        expect(issues.first.file_path).to eq("app/models/article.rb")
      end

      it "sets correct line_number for iteration" do
        source = <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats
            def update_stats
              authors.each do |author|
                author.articles.count
              end
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Line 4 is where the iteration starts
        iteration_issue = issues.find { |i| i.message.include?("Iteration") }
        expect(iteration_issue.line_number).to eq(4)
      end

      it "sets correct line_number for query inside iteration" do
        source = <<~RUBY
          class Article < ApplicationRecord
            after_save :update_stats
            def update_stats
              authors.each do |author|
                author.articles.count
              end
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Line 5 is where author.articles.count is called
        query_issue = issues.find { |i| i.message.include?(".count") }
        expect(query_issue.line_number).to eq(5)
      end
    end

    context "with find_each in callback" do
      it "detects find_each iteration in callback" do
        source = <<~RUBY
          class Order < ApplicationRecord
            after_create :notify_all

            def notify_all
              User.find_each do |user|
                user.notifications.create!(message: "New order")
              end
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        iteration_issue = issues.find { |i| i.message.include?("find_each") || i.message.include?("Iteration") }
        expect(iteration_issue).not_to be_nil
      end
    end
  end
end
