# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::Concerns::NonArSourceDetector do
  let(:test_class) do
    Class.new do
      include EagerEye::Detectors::Concerns::NonArSourceDetector

      def parse(source)
        EagerEye::SourceParser.parse(source)
      end

      def test_ar_receiver?(code)
        ast = parse(code)
        # Find the where call
        find_where_call(ast)
      end

      def test_non_db_source?(code)
        ast = parse(code)
        # Find assignment value
        find_assignment_value(ast)
      end

      private

      def find_where_call(node)
        return nil unless node.is_a?(Parser::AST::Node)

        return ar_receiver?(node) if node.type == :send && node.children[1] == :where

        node.children.each do |child|
          result = find_where_call(child)
          return result unless result.nil?
        end
        nil
      end

      def find_assignment_value(node)
        return nil unless node.is_a?(Parser::AST::Node)

        return non_db_source?(node.children[1]) if node.type == :lvasgn

        node.children.each do |child|
          result = find_assignment_value(child)
          return result unless result.nil?
        end
        nil
      end
    end
  end

  let(:detector) { test_class.new }

  describe "#ar_receiver?" do
    it "returns true for ActiveRecord model" do
      expect(detector.test_ar_receiver?("User.where(id: 1)")).to be true
    end

    it "returns false for Sidekiq::Queue" do
      expect(detector.test_ar_receiver?("Sidekiq::Queue.where(id: 1)")).to be false
    end

    it "returns false for Redis" do
      expect(detector.test_ar_receiver?("Redis.where(id: 1)")).to be false
    end
  end

  describe "#non_db_source?" do
    it "returns true for Sidekiq::Queue.map" do
      expect(detector.test_non_db_source?("ids = Sidekiq::Queue.new.map { |j| j.id }")).to be true
    end

    it "returns true for redis.smembers" do
      expect(detector.test_non_db_source?("ids = redis.smembers('key')")).to be true
    end

    it "returns false for ActiveRecord pluck" do
      expect(detector.test_non_db_source?("ids = User.pluck(:id)")).to be false
    end
  end
end
