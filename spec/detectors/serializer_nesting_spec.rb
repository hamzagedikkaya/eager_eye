# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::SerializerNesting do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :serializer_nesting" do
      expect(described_class.detector_name).to eq(:serializer_nesting)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with ActiveModel::Serializer" do
      it "detects nested association in attribute block" do
        source = <<~RUBY
          class PostSerializer < ActiveModel::Serializer
            attribute :author_name do
              object.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "app/serializers/post_serializer.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:serializer_nesting)
        expect(issues.first.message).to include("object.author")
        expect(issues.first.line_number).to eq(3)
      end

      it "detects multiple nested associations" do
        source = <<~RUBY
          class PostSerializer < ActiveModel::Serializer
            attribute :author_name do
              object.author.name
            end

            attribute :category_title do
              object.category.title
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with Blueprinter" do
      it "detects nested association in field block" do
        source = <<~RUBY
          class PostBlueprint < Blueprinter::Base
            field :author_name do |post|
              post.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("author")
      end
    end

    context "with Alba" do
      it "detects nested association in attribute block" do
        source = <<~RUBY
          class PostResource
            include Alba::Resource

            attribute :author_name do |post|
              post.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with class name patterns" do
      it "detects in classes ending with Serializer" do
        source = <<~RUBY
          class UserSerializer
            attribute :company_name do
              object.company.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects in classes ending with Blueprint" do
        source = <<~RUBY
          class UserBlueprint
            attribute :posts_count do
              object.posts.count
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects in classes ending with Resource" do
        source = <<~RUBY
          class UserResource
            attribute :company_name do
              object.company.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect in non-serializer classes" do
        source = <<~RUBY
          class PostsController
            def index
              object.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect regular method calls" do
        source = <<~RUBY
          class PostSerializer
            attribute :title do
              object.title
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect has_many/belongs_to declarations" do
        source = <<~RUBY
          class PostSerializer < ActiveModel::Serializer
            has_many :comments, serializer: CommentSerializer
            belongs_to :author
          end
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
          class PostSerializer
            attribute :author_name do
              object.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("Eager load")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          class PostSerializer
            attribute :author_name do
              object.author.name
            end
          end
        RUBY

        issues = detector.detect(parse(source), "app/serializers/post_serializer.rb")

        expect(issues.first.file_path).to eq("app/serializers/post_serializer.rb")
      end
    end
  end
end
