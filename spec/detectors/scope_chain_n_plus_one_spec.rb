# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::ScopeChainNPlusOne do
  let(:detector) { described_class.new }
  let(:scope_maps) { { "Comment" => Set[:recent, :approved, :published] } }

  describe ".detector_name" do
    it "returns :scope_chain_n_plus_one" do
      expect(described_class.detector_name).to eq(:scope_chain_n_plus_one)
    end
  end

  describe "#detect" do
    def parse(source)
      EagerEye::SourceParser.parse(source)
    end

    context "with scope call on association inside iteration" do
      it "detects scope call on association" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:scope_chain_n_plus_one)
        expect(issues.first.message).to include(".recent")
        expect(issues.first.message).to include("post.comments")
      end

      it "detects chained scope with count" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.approved.count
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include(".approved")
      end

      it "detects multiple scope calls in same block" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.recent
            post.comments.approved
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(2)
      end
    end

    context "with different iteration methods" do
      it "detects in map block" do
        source = <<~RUBY
          posts.map { |post| post.comments.recent }
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
      end

      it "detects in select block" do
        source = <<~RUBY
          posts.select { |post| post.comments.approved.any? }
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
      end

      it "detects in flat_map block" do
        source = <<~RUBY
          posts.flat_map { |post| post.comments.published }
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
      end

      it "detects in find_each block" do
        source = <<~RUBY
          Post.find_each do |post|
            post.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect scope call outside iteration" do
        source = <<~RUBY
          post = Post.find(1)
          post.comments.recent
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues).to be_empty
      end

      it "does not detect when method is not a known scope" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.where(active: true)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues).to be_empty
      end

      it "does not detect direct method call on block variable" do
        source = <<~RUBY
          posts.each do |post|
            post.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues).to be_empty
      end

      it "does not detect when scope_maps is empty" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", {})

        expect(issues).to be_empty
      end

      it "does not detect when not on block variable" do
        source = <<~RUBY
          other = Post.find(1)
          posts.each do |post|
            other.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb", scope_maps)

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      it "includes suggestion" do
        source = <<~RUBY
          posts.each do |post|
            post.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.first.suggestion).to include("preloading")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          posts.each { |post| post.comments.recent }
        RUBY

        issues = detector.detect(parse(source), "app/controllers/posts_controller.rb", scope_maps)

        expect(issues.first.file_path).to eq("app/controllers/posts_controller.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          posts.each do |post|
            post.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "with multiple models' scopes" do
      let(:scope_maps) do
        {
          "Comment" => Set[:recent, :approved],
          "Post" => Set[:published, :draft]
        }
      end

      it "detects scopes from different models" do
        source = <<~RUBY
          users.each do |user|
            user.posts.published
            user.comments.recent
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", scope_maps)

        expect(issues.size).to eq(2)
      end
    end
  end
end
