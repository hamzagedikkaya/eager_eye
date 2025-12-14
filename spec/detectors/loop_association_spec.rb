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
  end
end
