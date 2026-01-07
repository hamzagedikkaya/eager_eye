# frozen_string_literal: true

module EagerEye
  module Detectors
    class PluckToArray < Base
      SMALL_COLLECTIONS = %w[tags settings options categories roles permissions statuses types priorities].freeze

      def self.detector_name
        :pluck_to_array
      end

      def detect(ast, file_path)
        @issues = []
        @file_path = file_path
        @pluck_variables = {}
        @map_id_variables = {}
        @critical_pluck_variables = {}
        @small_collection_variables = {}

        return @issues unless ast

        visit(ast)
        @issues
      end

      private

      def visit(node)
        return unless node.is_a?(Parser::AST::Node)

        collect_assignments(node)
        check_where_calls(node)

        node.children.each { |child| visit(child) }
      end

      def collect_assignments(node)
        return unless local_variable_assignment?(node)

        var_name = node.children[0]
        value = node.children[1]

        @critical_pluck_variables[var_name] = node.loc.line if all_pluck_call?(value)
        @small_collection_variables[var_name] = node.loc.line if small_collection_pluck?(value)
        @pluck_variables[var_name] = node.loc.line if pluck_call?(value)
        @map_id_variables[var_name] = node.loc.line if map_id_call?(value)
      end

      def check_where_calls(node)
        return unless where_call?(node)

        if critical_pluck?(node)
          add_critical_issue(node)
        elsif small_collection?(node)
          add_info_issue(node)
        elsif regular_pluck?(node)
          add_issue(node)
        end
      end

      def local_variable_assignment?(node) = node.type == :lvasgn

      def where_call?(node) = node.type == :send && node.children[1] == :where

      def pluck_call?(node)
        node.is_a?(Parser::AST::Node) && node.type == :send && %i[pluck ids].include?(node.children[1])
      end

      def all_pluck_call?(node)
        return false unless pluck_call?(node)

        receiver = node.children[0]
        receiver.is_a?(Parser::AST::Node) && receiver.type == :send && receiver.children[1] == :all
      end

      def small_collection_pluck?(node)
        return false unless pluck_call?(node)

        receiver = node.children[0]
        return false unless receiver.is_a?(Parser::AST::Node) && receiver.type == :send

        method_name = receiver.children[1].to_s
        SMALL_COLLECTIONS.any? { |c| method_name.include?(c) }
      end

      def map_id_call?(node)
        node.is_a?(Parser::AST::Node) && (block_map?(node) || send_map?(node))
      end

      def block_map?(node)
        node.type == :block && node.children[0]&.type == :send &&
          %i[map collect].include?(node.children[0].children[1])
      end

      def send_map?(node)
        node.type == :send && %i[map collect].include?(node.children[1]) &&
          node.children[2..].any? { |arg| symbol_to_proc_id?(arg) }
      end

      def symbol_to_proc_id?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :block_pass

        node.children[0]&.type == :sym && %i[id to_i].include?(node.children[0].children[0])
      end

      def regular_pluck?(node)
        node.children[2..].any? { |arg| pluck_var_in_hash?(arg) }
      end

      def critical_pluck?(node)
        node.children[2..].any? { |arg| critical_pluck_in_hash?(arg) }
      end

      def small_collection?(node)
        node.children[2..].any? { |arg| small_collection_in_hash?(arg) }
      end

      def pluck_var_in_hash?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? { |pair| pair.type == :pair && pluck_value?(pair.children[1]) }
      end

      def critical_pluck_in_hash?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? { |pair| pair.type == :pair && critical_value?(pair.children[1]) }
      end

      def small_collection_in_hash?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? { |pair| pair.type == :pair && small_collection_value?(pair.children[1]) }
      end

      def pluck_value?(value)
        value.type == :lvar && (@pluck_variables.key?(value.children[0]) || @map_id_variables.key?(value.children[0]))
      end

      def critical_value?(value)
        value.type == :lvar ? @critical_pluck_variables.key?(value.children[0]) : all_pluck_call?(value)
      end

      def small_collection_value?(value)
        value.type == :lvar && @small_collection_variables.key?(value.children[0])
      end

      def add_issue(node)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Using plucked array in `where` causes two queries and memory overhead",
          suggestion: "Use `.select(:id)` subquery instead: `Model.where(col: OtherModel.select(:id))`",
          severity: :warning
        )
      end

      def add_critical_issue(node)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Using `.all.pluck(:id)` loads entire table into memory - highly inefficient",
          suggestion: "Use `.select(:id)` subquery: `Model.where(col: OtherModel.select(:id))`",
          severity: :error
        )
      end

      def add_info_issue(node)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Small collection pluck may be acceptable for few records",
          suggestion: "Consider `.select(:id)` for consistency, but pluck is fine for small collections",
          severity: :info
        )
      end
    end
  end
end
