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

      def self.detector_name
        :missing_counter_cache
      end

      def detect(ast, file_path)
        return [] unless ast

        issues = []

        traverse_ast(ast) do |node|
          next unless count_on_association?(node)

          association_name = extract_association_name(node)
          next unless association_name

          issues << create_issue(
            file_path: file_path,
            line_number: node.loc.line,
            message: "`.#{node.children[1]}` called on `#{association_name}` may cause N+1 queries",
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
    end
  end
end
