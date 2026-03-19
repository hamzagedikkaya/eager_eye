# frozen_string_literal: true

module EagerEye
  module Detectors
    class DelegationNPlusOne < Base
      ITERATION_METHODS = %i[
        each map collect select find_all reject filter filter_map flat_map
        find_each find_in_batches in_batches array!
      ].freeze
      PRELOAD_METHODS = %i[includes preload eager_load].freeze

      def self.detector_name
        :delegation_n_plus_one
      end

      def detect(ast, file_path, delegation_maps = {})
        return [] unless ast

        issues = []
        local_delegates = collect_local_delegates(ast)

        traverse_ast(ast) do |node|
          next unless iteration_block?(node)

          block_var = extract_block_variable(node)
          block_body = node.children[2]
          next unless block_var && block_body

          collection_node = node.children[0]
          delegates = build_delegates(infer_model_name(collection_node), delegation_maps, local_delegates)
          next if delegates.empty?

          included = extract_included_associations(collection_node)
          find_delegated_calls(block_body, block_var, delegates, included, file_path, issues)
        end

        issues
      end

      private

      def collect_local_delegates(ast)
        delegates = {}
        traverse_ast(ast) do |node|
          next unless node.type == :send && node.children[0].nil? && node.children[1] == :delegate

          extract_delegate_info(node, delegates)
        end
        delegates
      end

      def extract_delegate_info(node, delegates)
        args = node.children[2..]
        methods = args.select { |a| a&.type == :sym }.map { |a| a.children[0] }
        return if methods.empty?

        to_target = extract_to_target(args)
        return unless to_target

        methods.each { |m| delegates[m] = to_target }
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

      def build_delegates(model_name, delegation_maps, local_delegates)
        cross_file = model_name ? (delegation_maps[model_name] || {}) : {}
        cross_file.merge(local_delegates)
      end

      def iteration_block?(node)
        node.type == :block && node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def infer_model_name(node)
        current = node
        current = current.children[0] while current&.type == :send
        current&.type == :const ? current.children[1].to_s : nil
      end

      def extract_included_associations(collection_node)
        included = Set.new
        return included unless collection_node&.type == :send

        current = collection_node
        while current&.type == :send
          if PRELOAD_METHODS.include?(current.children[1])
            included.merge(extract_symbols_from_args(extract_method_args(current)))
          end
          current = current.children[0]
        end
        included
      end

      def find_delegated_calls(block_body, block_var, delegates, included, file_path, issues)
        reported = Set.new
        traverse_ast(block_body) do |node|
          target_assoc = delegation_target(node, block_var, delegates, included, reported)
          next unless target_assoc

          method = node.children[1]
          issues << create_issue(
            file_path: file_path,
            line_number: node.loc.line,
            message: "Potential N+1: `#{block_var}.#{method}` is delegated to `#{target_assoc}` — " \
                     "loads `#{target_assoc}` on each iteration",
            suggestion: "Use `includes(:#{target_assoc})` before iterating"
          )
        end
      end

      def delegation_target(node, block_var, delegates, included, reported)
        return unless node.type == :send && block_var_receiver?(node, block_var)

        method = node.children[1]
        target_assoc = delegates[method]
        return unless target_assoc && !included.include?(target_assoc)

        reported.add?("#{node.loc.line}:#{method}") ? target_assoc : nil
      end

      def block_var_receiver?(node, block_var)
        receiver = node.children[0]
        receiver&.type == :lvar && receiver.children[0] == block_var
      end
    end
  end
end
