# frozen_string_literal: true

require "spec_helper"
require "eager_eye/rspec"
require "tempfile"
require "fileutils"

RSpec.describe EagerEye::RSpec::Matchers do
  include described_class

  around do |example|
    @temp_dir = Dir.mktmpdir
    example.run
    FileUtils.rm_rf(@temp_dir)
  end

  after do
    EagerEye.reset_configuration!
  end

  describe "pass_eager_eye" do
    context "with clean file" do
      before do
        File.write(File.join(@temp_dir, "clean.rb"), <<~RUBY)
          class PostsController
            def index
              @posts = Post.includes(:author).all
            end
          end
        RUBY
      end

      it "passes" do
        expect(File.join(@temp_dir, "clean.rb")).to pass_eager_eye
      end
    end

    context "with problematic file" do
      before do
        File.write(File.join(@temp_dir, "bad.rb"), <<~RUBY)
          class PostsController
            def index
              @posts = Post.all
              @posts.each { |p| p.author.name }
            end
          end
        RUBY
      end

      it "fails" do
        expect(File.join(@temp_dir, "bad.rb")).not_to pass_eager_eye
      end

      it "provides helpful error message" do
        matcher = pass_eager_eye
        matcher.matches?(File.join(@temp_dir, "bad.rb"))

        expect(matcher.failure_message).to include("loop_association")
        expect(matcher.failure_message).to include("Line")
      end
    end

    context "with only option" do
      before do
        File.write(File.join(@temp_dir, "mixed.rb"), <<~RUBY)
          class Processor
            def run
              @users.each { |u| u.posts.count }
            end
          end
        RUBY
      end

      it "checks only specified detectors" do
        # count_in_iteration catches it
        expect(File.join(@temp_dir, "mixed.rb")).not_to pass_eager_eye(
          only: [:count_in_iteration]
        )

        # serializer_nesting doesn't apply
        expect(File.join(@temp_dir, "mixed.rb")).to pass_eager_eye(
          only: [:serializer_nesting]
        )
      end
    end

    context "with max_issues option" do
      before do
        File.write(File.join(@temp_dir, "some_issues.rb"), <<~RUBY)
          class Processor
            def run
              @users.each { |u| u.profile }
              @posts.each { |p| p.author }
            end
          end
        RUBY
      end

      it "allows up to max issues" do
        expect(File.join(@temp_dir, "some_issues.rb")).to pass_eager_eye(max_issues: 5)
        expect(File.join(@temp_dir, "some_issues.rb")).not_to pass_eager_eye(max_issues: 0)
      end
    end

    context "with directory" do
      before do
        FileUtils.mkdir_p(File.join(@temp_dir, "controllers"))
        File.write(File.join(@temp_dir, "controllers", "posts_controller.rb"), <<~RUBY)
          class PostsController
            def index
              @posts = Post.includes(:author).all
            end
          end
        RUBY
      end

      it "analyzes all files in directory" do
        expect(File.join(@temp_dir, "controllers")).to pass_eager_eye
      end
    end

    context "with exclude option" do
      before do
        FileUtils.mkdir_p(File.join(@temp_dir, "legacy"))
        File.write(File.join(@temp_dir, "legacy", "old.rb"), <<~RUBY)
          class OldController
            def index
              @posts.each { |p| p.author }
            end
          end
        RUBY
        File.write(File.join(@temp_dir, "good.rb"), <<~RUBY)
          class GoodController
            def index
              @posts = Post.includes(:author).all
            end
          end
        RUBY
      end

      it "excludes matching files" do
        # Without exclude, it fails because of legacy
        expect(@temp_dir).not_to pass_eager_eye

        # With exclude, it passes
        expect(@temp_dir).to pass_eager_eye(
          exclude: [File.join(@temp_dir, "legacy/**")]
        )
      end
    end
  end

  describe "matcher description" do
    it "provides basic description" do
      matcher = pass_eager_eye
      expect(matcher.description).to eq("pass EagerEye analysis")
    end

    it "includes only detectors in description" do
      matcher = pass_eager_eye(only: %i[loop_association serializer_nesting])
      expect(matcher.description).to include("loop_association")
      expect(matcher.description).to include("serializer_nesting")
    end

    it "includes max_issues in description" do
      matcher = pass_eager_eye(max_issues: 5)
      expect(matcher.description).to include("max 5 issues")
    end
  end

  describe "failure_message_when_negated" do
    it "provides negated failure message" do
      File.write(File.join(@temp_dir, "clean.rb"), "class Foo; end")

      matcher = pass_eager_eye
      matcher.matches?(File.join(@temp_dir, "clean.rb"))

      expect(matcher.failure_message_when_negated).to include("expected")
      expect(matcher.failure_message_when_negated).to include("to have EagerEye issues")
    end
  end
end
