# frozen_string_literal: true

module EagerEye
  module Detectors
    class DelegationNPlusOne < Base
      ITERATION_METHODS = %i[
        each map collect select find_all reject filter filter_map flat_map
        find_each find_in_batches in_batches
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
          next unless block_var

          block_body = node.children[2]
          next unless block_body

          collection_node = node.children[0]
          model_name = infer_model_name(collection_node)
          delegates = build_delegates(model_name, delegation_maps, local_delegates)
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
          next unless delegate_call?(node)

          extract_delegate_info(node, delegates)
        end
        delegates
      end

      def delegate_call?(node)
        node.type == :send && node.children[0].nil? && node.children[1] == :delegate
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

      def build_delegates(model_name, delegation_maps, local_delegates)
        cross_file = model_name ? (delegation_maps[model_name] || {}) : {}
        cross_file.merge(local_delegates)
      end

      def iteration_block?(node)
        node.type == :block &&
          node.children[0]&.type == :send &&
          ITERATION_METHODS.include?(node.children[0].children[1])
      end

      def extract_block_variable(block_node)
        args = block_node&.children&.[](1)
        first_arg = args&.children&.first
        first_arg&.type == :arg ? first_arg.children[0] : nil
      end

      def infer_model_name(node)
        root = find_root_receiver(node)
        root&.type == :const ? root.children[1].to_s : nil
      end

      def find_root_receiver(node)
        current = node
        current = current.children[0] while current&.type == :send
        current
      end

      def extract_included_associations(collection_node)
        included = Set.new
        return included unless collection_node&.type == :send

        current = collection_node
        while current&.type == :send
          extract_from_preload(current, included) if PRELOAD_METHODS.include?(current.children[1])
          current = current.children[0]
        end
        included
      end

      def extract_from_preload(method_node, included_set)
        args = extract_method_args(method_node)
        included_set.merge(extract_symbols_from_args(args))
      end

      def find_delegated_calls(block_body, block_var, delegates, included, file_path, issues)
        reported = Set.new
        traverse_ast(block_body) do |node|
          target_assoc = delegation_target(node, block_var, delegates, included, reported)
          next unless target_assoc

          issues << create_delegation_issue(node, block_var, target_assoc, file_path)
        end
      end

      def delegation_target(node, block_var, delegates, included, reported)
        return unless node.type == :send
        return unless block_var_receiver?(node, block_var)

        method = node.children[1]
        target_assoc = delegates[method]
        return unless target_assoc
        return if included.include?(target_assoc)
        return unless reported.add?("#{node.loc.line}:#{method}")

        target_assoc
      end

      def block_var_receiver?(node, block_var)
        receiver = node.children[0]
        receiver&.type == :lvar && receiver.children[0] == block_var
      end

      def create_delegation_issue(node, block_var, target_assoc, file_path)
        method = node.children[1]
        create_issue(
          file_path: file_path,
          line_number: node.loc.line,
          message: "Potential N+1: `#{block_var}.#{method}` is delegated to `#{target_assoc}` — " \
                   "loads `#{target_assoc}` on each iteration",
          suggestion: "Use `includes(:#{target_assoc})` before iterating"
        )
      end
    end
  end
end
