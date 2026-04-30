# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::LoopAssociation do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :loop_association" do
      expect(described_class.detector_name).to eq(:loop_association)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with each iteration" do
      it "detects association call inside each block" do
        source = <<~RUBY
          posts.each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:loop_association)
        expect(issues.first.message).to include("post.author")
        expect(issues.first.line_number).to eq(2)
      end

      it "detects chained association calls" do
        source = <<~RUBY
          posts.each do |post|
            post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end

      it "detects multiple association calls in same block" do
        source = <<~RUBY
          posts.each do |post|
            post.author
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with map iteration" do
      it "detects association call inside map block" do
        source = <<~RUBY
          posts.map do |post|
            post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with select iteration" do
      it "detects association call inside select block" do
        source = <<~RUBY
          users.select do |user|
            user.posts.any?
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("user.posts")
      end
    end

    context "with brace block syntax" do
      it "detects association call inside brace block" do
        source = <<~RUBY
          posts.each { |post| post.author }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect regular method calls" do
        source = <<~RUBY
          posts.each do |post|
            post.title
            post.to_s
            post.id
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # title might be detected as it looks like association, but to_s and id should not
        association_issues = issues.select { |i| i.message.include?("to_s") || i.message.include?(".id") }
        expect(association_issues).to be_empty
      end

      it "does not detect when variable is not block variable" do
        source = <<~RUBY
          other_post = Post.first
          posts.each do |post|
            other_post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect outside iteration blocks" do
        source = <<~RUBY
          post = Post.first
          post.author
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when association is included" do
        source = <<~RUBY
          posts.includes(:author).each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when multiple associations are included" do
        source = <<~RUBY
          posts.includes(:author, :comments).each do |post|
            post.author.name
            post.comments.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when association is included with hash syntax" do
        source = <<~RUBY
          posts.includes(author: :profile).each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "detects other associations even when one is included" do
        source = <<~RUBY
          posts.includes(:author).each do |post|
            post.author
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.comments")
      end

      it "does not detect when includes is called on separate line with local variable" do
        source = <<~RUBY
          posts = Post.includes(:author)
          posts.each do |post|
            post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when preload is used on separate line" do
        source = <<~RUBY
          posts = Post.preload(:author, :comments)
          posts.each do |post|
            post.author
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when eager_load is used on separate line" do
        source = <<~RUBY
          posts = Post.eager_load(:author)
          posts.each do |post|
            post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when includes is on instance variable" do
        source = <<~RUBY
          @posts = Post.includes(:author)
          @posts.each do |post|
            post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "detects missing associations even when some are preloaded via variable" do
        source = <<~RUBY
          posts = Post.includes(:author)
          posts.each do |post|
            post.author
            post.category
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.category")
      end

      it "does not detect when iterating over single record's association (find)" do
        source = <<~RUBY
          @user = User.find(params[:id])
          @user.posts.each do |post|
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when iterating over single record's association (find_by)" do
        source = <<~RUBY
          user = User.find_by(email: "test@example.com")
          user.posts.each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when iterating over single record's association (first)" do
        source = <<~RUBY
          @post = Post.first
          @post.comments.each { |c| c.user }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when iterating over single record's association (last)" do
        source = <<~RUBY
          order = Order.last
          order.items.each { |item| item.product }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when chained find is used inline" do
        source = <<~RUBY
          User.find(1).posts.each do |post|
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "still detects N+1 on collection queries" do
        source = <<~RUBY
          @users = User.where(active: true)
          @users.each do |user|
            user.posts
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("user.posts")
      end

      it "still detects N+1 on .all queries" do
        source = <<~RUBY
          users = User.all
          users.each { |u| u.posts }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      it "includes suggestion in the issue" do
        source = <<~RUBY
          posts.each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("includes(:author)")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          posts.each { |post| post.author }
        RUBY

        issues = detector.detect(parse(source), "app/controllers/posts_controller.rb")

        expect(issues.first.file_path).to eq("app/controllers/posts_controller.rb")
      end
    end

    context "with find iteration" do
      it "detects association call inside find block" do
        source = <<~RUBY
          posts.find do |post|
            post.author.active?
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end
    end

    context "with reject iteration" do
      it "detects association call inside reject block" do
        source = <<~RUBY
          posts.reject { |post| post.category.hidden? }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.category")
      end
    end

    context "with collect iteration" do
      it "detects association call inside collect block" do
        source = <<~RUBY
          orders.collect { |order| order.customer.email }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("order.customer")
      end
    end

    context "with flat_map iteration" do
      it "detects association call inside flat_map block" do
        source = <<~RUBY
          users.flat_map { |user| user.posts }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "nested iterations" do
      it "detects associations in nested loops" do
        source = <<~RUBY
          users.each do |user|
            user.posts.each do |post|
              post.comments
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with fixture file integration" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in loop_association_bad.rb" do
        file_path = File.join(fixtures_path, "loop_association_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues.size).to be >= 5
      end

      it "detects fewer issues in loop_association_good.rb than bad" do
        good_file_path = File.join(fixtures_path, "loop_association_good.rb")
        good_source = File.read(good_file_path)
        good_issues = detector.detect(parse(good_source), good_file_path)

        bad_file_path = File.join(fixtures_path, "loop_association_bad.rb")
        bad_source = File.read(bad_file_path)
        bad_issues = detector.detect(parse(bad_source), bad_file_path)

        # Good file should have significantly fewer issues than bad file
        expect(good_issues.size).to be < bad_issues.size
      end

      context "with single model instance" do
        let(:code) do
          <<~RUBY
            user = User.find(params[:id])
            user.posts.each do |post|
              post.author.name
            end
          RUBY
        end

        it "detects single record iteration as safe" do
          issues = detector.detect(parse(code), "test.rb")
          expect(issues).to be_empty
        end
      end

      context "with association preloads from model" do
        it "uses association preloads when provided" do
          source = <<~RUBY
            Post.all.each do |post|
              post.comments
            end
          RUBY
          preloads = { "Post#comments" => Set[:comments] }
          issues = detector.detect(parse(source), "test.rb", preloads)
          # preloads are matched by key prefix, so this may still detect
          expect(issues).to be_an(Array)
        end
      end
    end

    context "with dynamic association names" do
      it "detects custom association from model parsing" do
        source = <<~RUBY
          orders.each do |order|
            order.enrollments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", {}, Set[:enrollments])

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("order.enrollments")
      end

      it "does not detect custom association without dynamic names" do
        source = <<~RUBY
          orders.each do |order|
            order.enrollments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with cross-file method queries" do
      it "detects model query method called inside loop" do
        source = <<~RUBY
          users.each do |user|
            user.active_orders
          end
        RUBY

        method_queries = { "User" => Set[:active_orders] }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, method_queries)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("user.active_orders")
        expect(issues.first.message).to include("query method defined in the model")
      end

      it "does not detect model query method without method_queries data" do
        source = <<~RUBY
          users.each do |user|
            user.active_orders
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "detects multiple cross-file query methods in same loop" do
        source = <<~RUBY
          posts.each do |post|
            post.recent_comments
            post.top_rated_comment
          end
        RUBY

        method_queries = { "Post" => Set[:recent_comments, :top_rated_comment] }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, method_queries)

        expect(issues.size).to eq(2)
      end

      it "does not flag excluded methods even if in method_queries" do
        source = <<~RUBY
          users.each do |user|
            user.name
          end
        RUBY

        method_queries = { "User" => Set[:name] }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, method_queries)

        expect(issues).to be_empty
      end

      it "detects both association and method query issues in same loop" do
        source = <<~RUBY
          posts.each do |post|
            post.author
            post.expensive_calculation
          end
        RUBY

        method_queries = { "Post" => Set[:expensive_calculation] }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, method_queries)

        expect(issues.size).to eq(2)
        messages = issues.map(&:message)
        expect(messages).to include(a_string_including("post.author"))
        expect(messages).to include(a_string_including("post.expensive_calculation"))
      end
    end

    context "with each_with_object iteration" do
      it "detects association call inside each_with_object block" do
        source = <<~RUBY
          posts.each_with_object({}) do |post, hash|
            hash[post.id] = post.author.name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end
    end

    context "with reduce iteration" do
      it "detects association call inside reduce block" do
        source = <<~RUBY
          posts.reduce([]) do |result, post|
            result << post.comments.map(&:body)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.comments")
      end

      it "does not confuse accumulator with item variable" do
        source = <<~RUBY
          posts.reduce({}) do |memo, post|
            memo.merge(post.author.name => true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end
    end

    context "with inject iteration" do
      it "detects association call inside inject block" do
        source = <<~RUBY
          users.inject([]) do |acc, user|
            acc + user.posts.to_a
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("user.posts")
      end
    end

    context "with find_each iteration" do
      it "detects association call inside find_each block" do
        source = <<~RUBY
          Post.find_each do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end

      it "detects association call inside find_in_batches block" do
        source = <<~RUBY
          Post.find_in_batches do |batch|
            batch.each do |post|
              post.author
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects association call inside in_batches block" do
        source = <<~RUBY
          Post.in_batches do |batch|
            batch.each do |post|
              post.comments
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with jbuilder json.array! iteration" do
      it "detects N+1 inside json.array! block" do
        source = <<~RUBY
          json.array! @posts do |post|
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "index.json.jbuilder")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.comments")
      end

      it "detects chained association in json.array!" do
        source = <<~RUBY
          json.array! @posts do |post|
            post.author
          end
        RUBY

        issues = detector.detect(parse(source), "index.json.jbuilder")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end
    end

    context "with pagy / multi-assignment preload tracking" do
      it "does not flag association preloaded in pagy(query)" do
        source = <<~RUBY
          query = Post.includes(:author, :comments)
          @pagy, posts = pagy(query)
          posts.each do |post|
            post.author
            post.comments
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not flag when includes is inside pagy(...) call args" do
        source = <<~RUBY
          @pagy, posts = pagy(Post.includes(:author))
          posts.each { |post| post.author }
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not flag when query is built via ternary then included" do
        source = <<~RUBY
          base = condition ? Post.joins(:author).where(x: 1) : Post.none
          @pagy, posts = pagy(base.includes(:author).order(:id))
          posts.each { |post| post.author }
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end
    end

    context "with per-model association scoping" do
      it "does not flag column access matching hardcoded name when model has no such association" do
        source = <<~RUBY
          logs.each do |log|
            log.tag
          end
        RUBY

        # ApplicationLog has no :tag association, but has other associations.
        associations_by_model = { "ApplicationLog" => Set.new(%i[user]) }
        # Ensure inferring ApplicationLog by tracking the variable's source:
        source_with_source = <<~RUBY
          logs = ApplicationLog.all
          logs.each do |log|
            log.tag
          end
        RUBY

        issues = detector.detect(parse(source_with_source), "test.rb", {}, Set.new, {}, associations_by_model)
        expect(issues).to be_empty
      end

      it "still flags real association calls when per-model map confirms it" do
        source = <<~RUBY
          posts = Post.all
          posts.each { |post| post.author }
        RUBY

        associations_by_model = { "Post" => Set.new(%i[author]) }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, {}, associations_by_model)
        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("post.author")
      end

      it "scopes method_queries lookup to the receiver's model" do
        # `lookup_owner` is defined as a query method on PrepaidWallet (not on Order).
        # Iterating Orders should NOT flag `order.lookup_owner`.
        source = <<~RUBY
          orders = Order.all
          orders.each { |order| order.lookup_owner }
        RUBY

        method_queries = { "PrepaidWallet" => Set.new(%i[lookup_owner]) }
        associations_by_model = { "Order" => Set.new(%i[customer]) }
        issues = detector.detect(parse(source), "test.rb", {}, Set.new, method_queries, associations_by_model)
        expect(issues).to be_empty
      end
    end

    context "with non-loading terminal methods" do
      it "does not flag association access used only for update_all" do
        source = <<~RUBY
          Avm.find_each do |avm|
            avm.merchant_branches.update_all(latitude: 1)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not flag association access used only for delete_all" do
        source = <<~RUBY
          users.each do |user|
            user.posts.delete_all
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "still flags association when chain ends with a SELECT-triggering method" do
        source = <<~RUBY
          users.each do |user|
            user.posts.first
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("user.posts")
      end
    end
  end
end
