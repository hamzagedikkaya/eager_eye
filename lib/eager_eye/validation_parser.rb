# frozen_string_literal: true

module EagerEye
  class ValidationParser
    attr_reader :uniqueness_models

    def initialize
      @uniqueness_models = Set.new
    end

    def parse_model(ast, model_name)
      return unless ast

      traverse(ast, model_name)
    end

    private

    def traverse(node, model_name)
      return unless node.is_a?(Parser::AST::Node)

      check_uniqueness(node, model_name)
      node.children.each { |child| traverse(child, model_name) }
    end

    def check_uniqueness(node, model_name)
      return unless node.type == :send && node.children[0].nil?

      case node.children[1]
      when :validates
        @uniqueness_models << model_name if uniqueness_option?(node)
      when :validates_uniqueness_of
        @uniqueness_models << model_name
      end
    end

    def uniqueness_option?(node)
      node.children[2..].any? do |arg|
        next false unless arg.is_a?(Parser::AST::Node) && arg.type == :hash

        arg.children.any? { |pair| uniqueness_pair?(pair) }
      end
    end

    def uniqueness_pair?(pair)
      return false unless pair.type == :pair

      key = pair.children[0]
      key&.type == :sym && key.children[0] == :uniqueness
    end
  end
end
