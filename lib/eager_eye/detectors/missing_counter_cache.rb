# frozen_string_literal: true

module EagerEye
  module Detectors
    class MissingCounterCache < Base
      # Methods that trigger COUNT queries
      COUNT_METHODS = %i[count size length].freeze

      # Common has_many association names (plural)
      PLURAL_ASSOCIATIONS = %w[
        posts comments tags categories articles users members
        items orders products tasks projects images attachments
        documents files messages notifications reviews ratings
        followers followings likes favorites bookmarks votes
        children replies responses answers questions
      ].freeze

      # Iteration methods that indicate a loop context
      ITERATION_METHODS = %i[each map collect select reject find_all
                             filter filter_map flat_map each_with_index
                             each_with_object reduce inject sum].freeze

      def self.detector_name
        :missing_counter_cache
      end

      def detect(ast, file_path)
        return [] unless ast

        issues = []

        traverse_ast(ast) do |node|
          next unless count_on_association?(node)
          next unless inside_iteration?(node)

          association_name = extract_association_name(node)
          next unless association_name

          issues << create_issue(
            file_path: file_path,
            line_number: node.loc.line,
            message: "`.#{node.children[1]}` called on `#{association_name}` inside iteration may cause N+1 queries",
            suggestion: "Consider adding `counter_cache: true` to the belongs_to association"
          )
        end

        issues
      end

      private

      def count_on_association?(node)
        return false unless node.type == :send

        method_name = node.children[1]
        return false unless COUNT_METHODS.include?(method_name)

        receiver = node.children[0]
        return false unless receiver

        likely_association_receiver?(receiver)
      end

      def likely_association_receiver?(node)
        return false unless node.type == :send

        method_name = node.children[1]
        PLURAL_ASSOCIATIONS.include?(method_name.to_s)
      end

      def extract_association_name(node)
        receiver = node.children[0]
        return nil unless receiver&.type == :send

        receiver.children[1].to_s
      end

      # Check if the node is inside an iteration block
      def inside_iteration?(node)
        parent = node
        while (parent = find_parent(parent))
          return true if iteration_block?(parent)
        end
        false
      end

      def find_parent(node)
        @parent_map ||= {}
        @parent_map[node]
      end

      # Override traverse_ast to build parent map
      def traverse_ast(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        @parent_map ||= {}

        yield node

        node.children.each do |child|
          if child.is_a?(Parser::AST::Node)
            @parent_map[child] = node
            traverse_ast(child, &block)
          end
        end
      end

      def iteration_block?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        return false unless send_node&.type == :send

        method_name = send_node.children[1]
        ITERATION_METHODS.include?(method_name)
      end
    end
  end
end
