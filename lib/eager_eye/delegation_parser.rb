# frozen_string_literal: true

module EagerEye
  class DelegationParser
    attr_reader :delegation_maps

    def initialize
      @delegation_maps = {}
    end

    def parse_model(ast, model_name)
      return unless ast

      traverse(ast, model_name)
    end

    private

    def traverse(node, model_name)
      return unless node.is_a?(Parser::AST::Node)

      check_delegate(node, model_name)
      node.children.each { |child| traverse(child, model_name) }
    end

    def check_delegate(node, model_name)
      return unless bare_delegate_call?(node)

      args = node.children[2..]
      methods = delegate_methods(args)
      return if methods.empty?

      to_target = extract_to_target(args)
      return unless to_target

      register_delegates(model_name, methods, to_target)
    end

    def bare_delegate_call?(node)
      node.type == :send && node.children[0].nil? && node.children[1] == :delegate
    end

    def delegate_methods(args)
      args.select { |a| a&.type == :sym }.map { |a| a.children[0] }
    end

    def register_delegates(model_name, methods, to_target)
      @delegation_maps[model_name] ||= {}
      methods.each { |m| @delegation_maps[model_name][m] = to_target }
    end

    def extract_to_target(args)
      hash_arg = args.find { |a| a&.type == :hash }
      return unless hash_arg

      to_pair = hash_arg.children.find { |p| to_key_pair?(p) }
      extract_sym_value(to_pair)
    end

    def extract_sym_value(node)
      return unless node

      value = node.children[1]
      value.children[0] if value&.type == :sym
    end

    def to_key_pair?(pair)
      pair.type == :pair &&
        pair.children[0]&.type == :sym &&
        pair.children[0].children[0] == :to
    end
  end
end
