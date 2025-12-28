# frozen_string_literal: true

module EagerEye
  class AssociationParser
    ASSOCIATION_METHODS = %i[has_many has_one belongs_to has_and_belongs_to_many].freeze

    attr_reader :preloaded_associations

    def initialize
      @preloaded_associations = {}
    end

    def parse_model(ast, model_name)
      return unless ast

      traverse(ast, model_name)
    end

    private

    def traverse(node, model_name)
      return unless node.is_a?(Parser::AST::Node)

      check_association_definition(node, model_name)
      node.children.each { |child| traverse(child, model_name) }
    end

    def check_association_definition(node, model_name)
      return unless node.type == :send
      return unless node.children[0].nil? # receiver is nil (class context)

      method_name = node.children[1]
      return unless ASSOCIATION_METHODS.include?(method_name)

      association_name = extract_association_name(node)
      return unless association_name

      preloaded = extract_preloaded_associations(node)
      return if preloaded.empty?

      @preloaded_associations["#{model_name}##{association_name}"] = preloaded
    end

    def extract_association_name(node)
      args = node.children[2..]
      return nil if args.empty?

      first_arg = args[0]
      return nil unless first_arg&.type == :sym

      first_arg.children[0]
    end

    def extract_preloaded_associations(node)
      preloaded = Set.new
      args = node.children[2..]
      return preloaded if args.empty?

      # Check for block with includes/preload/eager_load
      block_node = args.find { |arg| arg&.type == :block }
      return preloaded unless block_node

      extract_from_block(block_node, preloaded)
      preloaded
    end

    def extract_from_block(block_node, preloaded)
      block_body = block_node.children[2]
      traverse_for_preloads(block_body, preloaded)
    end

    def traverse_for_preloads(node, preloaded)
      return unless node.is_a?(Parser::AST::Node)

      extract_includes_from_method(node, preloaded) if preload_call?(node)

      node.children.each { |child| traverse_for_preloads(child, preloaded) }
    end

    def preload_call?(node)
      return false unless node.type == :send

      method = node.children[1]
      %i[includes preload eager_load].include?(method)
    end

    def extract_includes_from_method(node, included)
      args = node.children[2..]
      return if args.empty?

      args.each { |arg| add_included_sym(arg, included) }
    end

    def add_included_sym(arg, included)
      case arg&.type
      when :sym
        included << arg.children[0]
      when :hash
        arg.children.each { |pair| extract_sym_from_pair(pair, included) }
      end
    end

    def extract_sym_from_pair(pair, included)
      return unless pair.type == :pair

      key = pair.children[0]
      included << key.children[0] if key&.type == :sym
    end
  end
end
