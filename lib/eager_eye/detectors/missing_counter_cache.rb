# frozen_string_literal: true

module EagerEye
  module Detectors
    class MissingCounterCache < Base
      COUNT_METHODS = %i[count size length].freeze
      PLURAL_ASSOCIATIONS = %w[
        posts comments tags categories articles users members items orders products tasks projects
        images attachments documents files messages notifications reviews ratings followers followings
        likes favorites bookmarks votes children replies responses answers questions
      ].freeze
      ITERATION_METHODS = %i[each map collect select reject find_all filter filter_map flat_map
                             each_with_index each_with_object reduce inject sum
                             find_each find_in_batches in_batches].freeze

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
        return false unless COUNT_METHODS.include?(node.children[1])

        receiver = node.children[0]
        receiver && likely_association_receiver?(receiver)
      end

      def likely_association_receiver?(node)
        node.type == :send && PLURAL_ASSOCIATIONS.include?(node.children[1].to_s)
      end

      def extract_association_name(node)
        receiver = node.children[0]
        receiver.children[1].to_s if receiver&.type == :send
      end

      def inside_iteration?(node)
        parent = node
        while (parent = @parent_map[parent])
          return true if iteration_block?(parent)
        end
        false
      end

      def traverse_ast(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        @parent_map ||= {}
        yield node
        node.children.each do |child|
          next unless child.is_a?(Parser::AST::Node)

          @parent_map[child] = node
          traverse_ast(child, &block)
        end
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end
    end
  end
end
