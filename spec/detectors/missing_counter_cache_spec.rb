# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::MissingCounterCache do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :missing_counter_cache" do
      expect(described_class.detector_name).to eq(:missing_counter_cache)
    end
  end

  describe "#detect" do
    def parse(source)
      EagerEye::SourceParser.parse(source)
    end

    context "inside iteration - should detect" do
      it "detects count inside each block" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:missing_counter_cache)
        expect(issues.first.message).to include("comments")
        expect(issues.first.message).to include(".count")
        expect(issues.first.message).to include("inside iteration")
      end

      it "detects count inside map block" do
        source = <<~RUBY
          posts.map do |post|
            post.comments.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects count inside select block" do
        source = <<~RUBY
          posts.select do |post|
            post.comments.count > 10
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects size inside iteration" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.size
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".size")
      end

      it "detects length inside iteration" do
        source = <<~RUBY
          users.each do |user|
            user.followers.length
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".length")
      end

      it "detects count on various associations inside iteration" do
        source = <<~RUBY
          items.each do |item|
            item.posts.count
            item.tags.count
            item.tasks.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(3)
      end

      it "detects count inside sum block" do
        source = <<~RUBY
          posts.sum { |post| post.comments.count }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects count inside reduce block" do
        source = <<~RUBY
          posts.reduce(0) { |sum, post| sum + post.comments.count }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "outside iteration - should NOT detect" do
      it "does not detect single count call" do
        source = <<~RUBY
          post.comments.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect multiple single count calls" do
        source = <<~RUBY
          user.posts.count
          article.tags.count
          project.tasks.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect size outside iteration" do
        source = <<~RUBY
          post.comments.size
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect length outside iteration" do
        source = <<~RUBY
          user.followers.length
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count in model instance method" do
        source = <<~RUBY
          class Post
            def popular?
              comments.count > 100
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count in if condition outside iteration" do
        source = <<~RUBY
          if post.comments.count > 10
            puts "popular"
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count in ternary outside iteration" do
        source = <<~RUBY
          post.comments.count > 0 ? "has comments" : "no comments"
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect count on non-association methods" do
        source = <<~RUBY
          items.each do |item|
            array.count
            hash.count
            [1, 2, 3].count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count without receiver" do
        source = <<~RUBY
          items.each { |item| count }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect singular association count" do
        source = <<~RUBY
          posts.each do |post|
            post.author.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count after where clause" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.where(approved: true).count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Current implementation doesn't track through where clauses
        # This is acceptable as where().count is often intentional
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
      it "includes suggestion about counter_cache" do
        source = <<~RUBY
          posts.each { |post| post.comments.count }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("counter_cache")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          posts.each { |post| post.comments.count }
        RUBY

        issues = detector.detect(parse(source), "app/models/post.rb")

        expect(issues.first.file_path).to eq("app/models/post.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          y = 2
          posts.each { |post| post.comments.count }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "with fixture file integration" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in counter_cache_bad.rb" do
        file_path = File.join(fixtures_path, "counter_cache_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        # Only count calls inside iterations should be detected
        expect(issues.size).to be >= 4
      end

      it "detects no issues in counter_cache_good.rb" do
        file_path = File.join(fixtures_path, "counter_cache_good.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues).to be_empty
      end
    end

    context "with find_each iteration" do
      it "detects count on association inside find_each" do
        source = <<~RUBY
          Post.find_each do |post|
            post.comments.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("comments")
      end
    end
  end
end
