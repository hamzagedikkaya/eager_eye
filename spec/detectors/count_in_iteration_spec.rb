# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::CountInIteration do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :count_in_iteration" do
      expect(described_class.detector_name).to eq(:count_in_iteration)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "when .count is called inside each" do
      let(:code) do
        <<~RUBY
          @users.each do |user|
            user.posts.count
          end
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:count_in_iteration)
        expect(issues.first.message).to include(".count")
        expect(issues.first.suggestion).to include(".size")
      end
    end

    context "when .count is called inside map" do
      let(:code) do
        <<~RUBY
          @posts.map do |post|
            post.comments.count
          end
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when .count is called inside select" do
      let(:code) do
        <<~RUBY
          @users.select do |user|
            user.posts.count > 5
          end
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when .count is called inside flat_map" do
      let(:code) do
        <<~RUBY
          @users.flat_map { |user| user.posts.count }
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when .size is used instead" do
      let(:code) do
        <<~RUBY
          @users.each do |user|
            user.posts.size
          end
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when .length is used instead" do
      let(:code) do
        <<~RUBY
          @users.each do |user|
            user.posts.length
          end
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when count is called outside iteration" do
      let(:code) do
        <<~RUBY
          total = User.all.count
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with nested association chain" do
      let(:code) do
        <<~RUBY
          @orders.each do |order|
            order.customer.orders.count
          end
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("order.customer.orders")
      end
    end

    context "with deeply nested chain" do
      let(:code) do
        <<~RUBY
          @companies.each do |company|
            company.departments.first.employees.count
          end
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when count is not on block variable" do
      let(:code) do
        <<~RUBY
          other = User.find(1)
          @users.each do |user|
            other.posts.count
          end
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with multiple count calls in same block" do
      let(:code) do
        <<~RUBY
          @users.each do |user|
            user.posts.count
            user.comments.count
          end
        RUBY
      end

      it "detects all issues" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(2)
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
          @users.each do |user|
            user.posts.count
          end
        RUBY
      end

      it "includes correct detector name" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.detector).to eq(:count_in_iteration)
      end

      it "includes suggestion about size and counter_cache" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.suggestion).to include(".size")
        expect(issues.first.suggestion).to include("counter_cache")
      end

      it "sets correct file_path" do
        ast = parse(code)
        issues = detector.detect(ast, "app/models/user.rb")

        expect(issues.first.file_path).to eq("app/models/user.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          @users.each do |user|
            user.posts.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "when .count is called on _ids association helper (returns Array)" do
      it "does not flag coupon_ids.count as AR query" do
        source = <<~RUBY
          @transactions.each do |trx|
            total_count = trx.coupon_ids.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not flag other _ids suffixed methods" do
        source = <<~RUBY
          @orders.each do |order|
            order.tag_ids.count
            order.product_ids.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "still detects count on regular AR associations" do
        source = <<~RUBY
          @orders.each do |order|
            order.tags.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "edge cases" do
      it "handles non-send receiver type" do
        source = <<~RUBY
          @users.each do |user|
            [1, 2].count
          end
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "handles nil receiver" do
        source = <<~RUBY
          @users.each { |user| count }
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end
    end

    context "with find_each iteration" do
      it "detects .count inside find_each block" do
        source = <<~RUBY
          User.find_each do |user|
            user.posts.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".count")
      end
    end
  end
end
