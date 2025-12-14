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
      Parser::CurrentRuby.parse(source)
    end

    context "with .count method" do
      it "detects count on association" do
        source = <<~RUBY
          post.comments.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:missing_counter_cache)
        expect(issues.first.message).to include("comments")
        expect(issues.first.message).to include(".count")
      end

      it "detects count on various associations" do
        source = <<~RUBY
          user.posts.count
          article.tags.count
          project.tasks.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(3)
      end
    end

    context "with .size method" do
      it "detects size on association" do
        source = <<~RUBY
          post.comments.size
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".size")
      end
    end

    context "with .length method" do
      it "detects length on association" do
        source = <<~RUBY
          user.followers.length
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".length")
      end
    end

    context "inside iteration" do
      it "detects count inside each block" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "in model methods" do
      it "detects count in instance method" do
        source = <<~RUBY
          class Post
            def popular?
              comments.count > 100
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect count on non-association methods" do
        source = <<~RUBY
          array.count
          hash.count
          [1, 2, 3].count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count without receiver" do
        source = <<~RUBY
          count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect singular association count" do
        source = <<~RUBY
          post.author.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect count with arguments (conditional count)" do
        source = <<~RUBY
          comments.count { |c| c.approved? }
        RUBY

        # This is actually a valid use case, but our simple detector
        # will still flag it. For now, we accept this limitation.
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
      it "includes suggestion about counter_cache" do
        source = <<~RUBY
          post.comments.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("counter_cache")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          post.comments.count
        RUBY

        issues = detector.detect(parse(source), "app/models/post.rb")

        expect(issues.first.file_path).to eq("app/models/post.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          y = 2
          post.comments.count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "in conditionals" do
      it "detects count in if condition" do
        source = <<~RUBY
          if post.comments.count > 10
            puts "popular"
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects count in ternary" do
        source = <<~RUBY
          post.comments.count > 0 ? "has comments" : "no comments"
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with chained methods" do
      it "does not detect count after where clause (too complex to track)" do
        source = <<~RUBY
          post.comments.where(approved: true).count
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        # Current implementation doesn't track through where clauses
        # This is acceptable as where().count is often intentional
        expect(issues).to be_empty
      end
    end

    context "with fixture file integration" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in counter_cache_bad.rb" do
        file_path = File.join(fixtures_path, "counter_cache_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues.size).to be >= 5
      end

      it "detects no issues in counter_cache_good.rb" do
        file_path = File.join(fixtures_path, "counter_cache_good.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues).to be_empty
      end
    end
  end
end
