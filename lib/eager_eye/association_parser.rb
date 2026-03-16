# frozen_string_literal: true

module EagerEye
  class AssociationParser
    ASSOCIATION_METHODS = %i[has_many has_one belongs_to has_and_belongs_to_many].freeze

    attr_reader :preloaded_associations, :association_names

    def initialize
      @preloaded_associations = {}
      @association_names = Set.new
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

      @association_names << association_name

      preloaded = extract_preloaded_associations(node)
      return if preloaded.empty?

      @preloaded_associations["#{model_name}##{association_name}"] = preloaded
    end

    def extract_association_name(node)
      first_arg = node.children[2]
      first_arg&.type == :sym ? first_arg.children[0] : nil
    end

    def extract_preloaded_associations(node)
      preloaded = Set.new
      block_node = node.children[2..].find { |arg| arg&.type == :block }
      traverse_for_preloads(block_node&.children&.[](2), preloaded) if block_node
      preloaded
    end

    def traverse_for_preloads(node, preloaded)
      return unless node.is_a?(Parser::AST::Node)

      extract_includes_from_method(node, preloaded) if preload_call?(node)

      node.children.each { |child| traverse_for_preloads(child, preloaded) }
    end

    def preload_call?(node)
      node.type == :send && %i[includes preload eager_load].include?(node.children[1])
    end

    def extract_includes_from_method(node, included)
      node.children[2..].each { |arg| add_included_sym(arg, included) }
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
