# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::CustomMethodQuery do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :custom_method_query" do
      expect(described_class.detector_name).to eq(:custom_method_query)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with .where inside iteration" do
      it "detects where call on association" do
        source = <<~RUBY
          @users.each do |user|
            user.teams.where(name: "Lakers")
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:custom_method_query)
        expect(issues.first.message).to include(".where")
        expect(issues.first.message).to include("user.teams")
      end

      it "detects chained query methods (where.first)" do
        source = <<~RUBY
          @users.each do |user|
            user.teams.where(name: "Lakers").first
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Both where and first are detected as query methods
        expect(issues.size).to eq(2)
        methods = issues.map { |i| i.message[/\.(\w+\??)/, 1] }
        expect(methods).to include("where", "first")
      end
    end

    context "with .exists? inside iteration" do
      it "detects exists? call on association" do
        source = <<~RUBY
          @users.each do |user|
            user.teams.exists?
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".exists?")
      end

      it "detects chained where.exists?" do
        source = <<~RUBY
          @users.each do |user|
            user.teams.where(name: "Lakers").exists?
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Both where and exists? are detected
        expect(issues.size).to eq(2)
      end
    end

    context "with .find_by inside iteration" do
      it "detects find_by call on association" do
        source = <<~RUBY
          @orders.map do |order|
            order.line_items.find_by(featured: true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".find_by")
        expect(issues.first.message).to include("order.line_items")
      end
    end

    context "with .pluck inside iteration" do
      it "detects pluck call on association" do
        source = <<~RUBY
          @posts.each do |post|
            post.comments.pluck(:id)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".pluck")
      end
    end

    context "with .first inside iteration" do
      it "detects first call on association" do
        source = <<~RUBY
          @users.each do |user|
            user.posts.first
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".first")
      end
    end

    context "with .last inside iteration" do
      it "detects last call on association" do
        source = <<~RUBY
          @users.each do |user|
            user.comments.last
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".last")
      end
    end

    context "with .sum inside iteration" do
      it "detects sum call on association" do
        source = <<~RUBY
          @orders.each do |order|
            order.line_items.sum(:price)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".sum")
      end
    end

    context "with multiple query methods in same iteration" do
      it "detects all query method calls" do
        source = <<~RUBY
          @orders.each do |order|
            order.coupons.where(active: true).first
            order.line_items.find_by(featured: true)
            order.products.pluck(:id)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # where.first counts as 2, find_by counts as 1, pluck counts as 1 = 4 total
        expect(issues.size).to eq(4)
      end
    end

    context "with different iteration methods" do
      it "detects in map block" do
        source = <<~RUBY
          @users.map { |user| user.posts.where(published: true) }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects in select block" do
        source = <<~RUBY
          @users.select { |user| user.posts.exists? }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects in reject block" do
        source = <<~RUBY
          @users.reject { |user| user.posts.where(spam: true).exists? }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # where.exists? counts as 2
        expect(issues.size).to eq(2)
      end

      it "detects in flat_map block" do
        source = <<~RUBY
          @users.flat_map { |user| user.posts.pluck(:id) }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect query outside iteration" do
        source = <<~RUBY
          user = User.find(1)
          user.teams.where(active: true)
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when not on block variable" do
        source = <<~RUBY
          other = User.find(1)
          @users.each do |user|
            other.teams.where(active: true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect Ruby array methods" do
        source = <<~RUBY
          items.map do |item|
            [item.first, item.last]
          end
        RUBY

        # .map returns array, .first and .last on block variable are Array methods
        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect Hash#keys and Hash#values methods" do
        source = <<~RUBY
          items.each do |item|
            item.metadata.keys.first
            item.metadata.values.last
            item.config.keys.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # No methods should be detected (even count is safe on keys/values)
        expect(issues).to be_empty
      end

      it "does not detect String#split methods" do
        source = <<~RUBY
          items.each do |item|
            item.url.split("?").first
            item.name.split(".").last
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect bracket access methods" do
        source = <<~RUBY
          items.each do |item|
            item["key"].first
            item[:key].last
            item[0].find { |x| x > 0 }
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect params iteration (tuple access)" do
        source = <<~RUBY
          params[:items].each do |item_params|
            item_params.last
            item_params.first
          end
        RUBY

        issues = detector.detect(parse(source), "controller.rb")
        expect(issues).to be_empty
      end

      it "does not detect hash literal iteration" do
        source = <<~RUBY
          { a: 1, b: 2 }.each do |pair|
            pair.last
            pair.first
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not detect pluck iteration" do
        source = <<~RUBY
          User.pluck(:id).each do |id|
            id + 1
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not detect variable assignment iteration (pluck)" do
        source = <<~RUBY
          ids = User.pluck(:id)
          ids.each do |id|
            id.to_s
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not detect count on scalar/string conversion" do
        source = <<~RUBY
          items.each do |item|
            item.id.to_s.count
            item.name.chars.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not detect count on array iteration" do
        source = <<~RUBY
          [[1, 2], [3, 4]].each do |arr|
            arr.count
            arr.sum
            arr.find { |x| x > 0 }
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "does not detect variable assignment with to_s" do
        source = <<~RUBY
          items.each do |item|
             str = item.to_s
             str.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "still detects queries on associations" do
        source = <<~RUBY
          @users.each do |user|
            user.tags.first
          end
        RUBY

        # user.tags.first is still a query method on association
        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".first")
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
          @users.each do |user|
            user.teams.where(active: true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("preloading")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          @users.each { |user| user.teams.where(active: true) }
        RUBY

        issues = detector.detect(parse(source), "app/services/user_service.rb")

        expect(issues.first.file_path).to eq("app/services/user_service.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          @users.each do |user|
            user.teams.where(active: true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "edge cases" do
      it "handles literal array iteration" do
        source = <<~RUBY
          [1, 2, 3].each { |n| puts n }
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "handles non-node receiver" do
        source = <<~RUBY
          items.each { |item| 42.to_s }
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end
    end
  end
end
