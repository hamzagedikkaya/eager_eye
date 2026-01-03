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
            attribute :authors_count do
              object.authors.count
            end
          end
        RUBY

        issues = detector.detect(parse(source), "app/serializers/post_serializer.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:serializer_nesting)
        expect(issues.first.message).to include("object.authors")
        expect(issues.first.line_number).to eq(3)
      end

      it "detects multiple nested associations" do
        source = <<~RUBY
          class PostSerializer < ActiveModel::Serializer
            attribute :authors_list do
              object.authors.map(&:name)
            end

            attribute :categories_list do
              object.categories.map(&:title)
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
            field :comments_list do |post|
              post.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("comments")
      end
    end

    context "with Alba" do
      it "detects nested association in attribute block" do
        source = <<~RUBY
          class PostResource
            include Alba::Resource

            attribute :tags_list do |post|
              post.tags.map(&:name)
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
            attribute :projects_list do
              object.projects.map(&:name)
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
            attribute :orders_list do
              object.orders.map(&:id)
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
            attribute :comments_list do
              object.comments.map(&:body)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("Eager load")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          class PostSerializer
            attribute :tags_list do
              object.tags.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "app/serializers/post_serializer.rb")

        expect(issues.first.file_path).to eq("app/serializers/post_serializer.rb")
      end
    end

    context "with deeply nested associations" do
      it "detects deeply chained association calls" do
        source = <<~RUBY
          class OrderSerializer
            attribute :items_data do
              object.items.map(&:name)
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("items")
      end
    end

    context "with hash return in block" do
      it "detects associations inside hash values" do
        source = <<~RUBY
          class PostSerializer
            attribute :meta do
              { authors: object.authors.map(&:name), categories: object.categories.map(&:title) }
            end
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with fixture file integration" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in serializer_bad.rb" do
        file_path = File.join(fixtures_path, "serializer_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues.size).to be >= 5
      end

      it "detects no issues in serializer_good.rb" do
        file_path = File.join(fixtures_path, "serializer_good.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues).to be_empty
      end
    end

    context "edge cases" do
      it "handles class without body" do
        source = "class EmptySerializer; end"
        issues = detector.detect(parse(source), "test.rb")
        expect(issues).to be_empty
      end

      it "handles class with non-const parent" do
        source = <<~RUBY
          class PostSerializer < base_class
            attribute :comments_list do
              object.comments.map(&:body)
            end
          end
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues.size).to eq(1)
      end

      it "handles record reference in block" do
        source = <<~RUBY
          class PostSerializer
            attribute :tags_list do
              record.tags.map(&:name)
            end
          end
        RUBY
        issues = detector.detect(parse(source), "test.rb")
        expect(issues.size).to eq(1)
      end
    end
  end
end
