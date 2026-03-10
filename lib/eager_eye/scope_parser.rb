# frozen_string_literal: true

module EagerEye
  class ScopeParser
    attr_reader :scope_maps

    def initialize
      @scope_maps = {}
    end

    def parse_model(ast, model_name)
      return unless ast

      traverse(ast, model_name)
    end

    private

    def traverse(node, model_name)
      return unless node.is_a?(Parser::AST::Node)

      check_scope(node, model_name)
      node.children.each { |child| traverse(child, model_name) }
    end

    def check_scope(node, model_name)
      return unless scope_call?(node)

      scope_name = extract_scope_name(node)
      return unless scope_name

      @scope_maps[model_name] ||= Set.new
      @scope_maps[model_name] << scope_name
    end

    def scope_call?(node)
      node.type == :send && node.children[0].nil? && node.children[1] == :scope
    end

    def extract_scope_name(node)
      first_arg = node.children[2]
      first_arg&.type == :sym ? first_arg.children[0] : nil
    end
  end
end
