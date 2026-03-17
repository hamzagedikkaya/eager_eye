# frozen_string_literal: true

module EagerEye
  class MethodQueryParser
    QUERY_METHODS = %i[where find find_by find_by! exists? any? none? many? one?
                       count sum average minimum maximum
                       pluck ids select
                       update_all delete_all destroy_all
                       create create! save save!
                       first last take].freeze

    ASSOCIATION_METHODS = %i[has_many has_one belongs_to has_and_belongs_to_many].freeze

    attr_reader :method_queries

    def initialize
      @method_queries = {}
    end

    def parse_model(ast, model_name)
      return unless ast

      traverse(ast, model_name)
    end

    private

    def traverse(node, model_name)
      return unless node.is_a?(Parser::AST::Node)

      check_method(node, model_name)
      node.children.each { |child| traverse(child, model_name) }
    end

    def check_method(node, model_name)
      return unless instance_method_def?(node)

      method_name = node.children[0]
      body = node.children[2]
      return unless body && contains_query?(body)

      @method_queries[model_name] ||= Set.new
      @method_queries[model_name] << method_name
    end

    def instance_method_def?(node)
      node.type == :def
    end

    def contains_query?(node)
      return false unless node.is_a?(Parser::AST::Node)
      return true if query_call?(node)

      node.children.any? { |child| contains_query?(child) }
    end

    def query_call?(node)
      node.type == :send && QUERY_METHODS.include?(node.children[1])
    end
  end
end
