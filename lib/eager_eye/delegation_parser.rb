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
      return unless delegate_call?(node)

      args = node.children[2..]
      methods = extract_sym_args(args)
      return if methods.empty?

      to_target = extract_to_target(args)
      return unless to_target

      @delegation_maps[model_name] ||= {}
      methods.each { |m| @delegation_maps[model_name][m] = to_target }
    end

    def delegate_call?(node)
      node.type == :send && node.children[0].nil? && node.children[1] == :delegate
    end

    def extract_sym_args(args)
      args.select { |a| a&.type == :sym }.map { |a| a.children[0] }
    end

    def extract_to_target(args)
      hash_arg = args.find { |a| a&.type == :hash }
      return unless hash_arg

      to_pair = find_to_pair(hash_arg)
      return unless to_pair

      value = to_pair.children[1]
      value.children[0] if value&.type == :sym
    end

    def find_to_pair(hash_node)
      hash_node.children.find do |p|
        p.type == :pair && p.children[0]&.type == :sym && p.children[0].children[0] == :to
      end
    end
  end
end
