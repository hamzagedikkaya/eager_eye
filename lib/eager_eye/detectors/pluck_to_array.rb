# frozen_string_literal: true

module EagerEye
  module Detectors
    class PluckToArray < Base
      def self.detector_name
        :pluck_to_array
      end

      def detect(ast, file_path)
        @issues = []
        @file_path = file_path
        @pluck_variables = {}
        @map_id_variables = {}
        @critical_pluck_variables = {}

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
        @pluck_variables[var_name] = node.loc.line if pluck_call?(value)
        @map_id_variables[var_name] = node.loc.line if map_id_call?(value)
      end

      def check_where_calls(node)
        return unless where_call?(node)

        add_critical_issue(node) if critical_pluck?(node)
        add_issue(node) if regular_pluck?(node)
      end

      def local_variable_assignment?(node)
        node.type == :lvasgn
      end

      def where_call?(node)
        node.type == :send && node.children[1] == :where
      end

      def pluck_call?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :send

        method = node.children[1]
        %i[pluck ids].include?(method)
      end

      def all_pluck_call?(node)
        return false unless pluck_call?(node)

        receiver = node.children[0]
        receiver.is_a?(Parser::AST::Node) && receiver.type == :send &&
          receiver.children[1] == :all
      end

      def map_id_call?(node)
        return false unless node.is_a?(Parser::AST::Node)

        block_map?(node) || send_map?(node)
      end

      def block_map?(node)
        return false unless node.type == :block

        send_node = node.children[0]
        send_node&.type == :send && %i[map collect].include?(send_node.children[1])
      end

      def send_map?(node)
        return false unless node.type == :send

        method = node.children[1]
        %i[map collect].include?(method) &&
          node.children[2..].any? { |arg| symbol_to_proc_id?(arg) }
      end

      def symbol_to_proc_id?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :block_pass

        sym = node.children[0]
        sym&.type == :sym && %i[id to_i].include?(sym.children[0])
      end

      def regular_pluck?(node)
        where_args = node.children[2..]
        where_args.any? { |arg| pluck_var_in_hash?(arg) }
      end

      def critical_pluck?(node)
        where_args = node.children[2..]
        where_args.any? { |arg| critical_pluck_in_hash?(arg) }
      end

      def pluck_var_in_hash?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? do |pair|
          next false unless pair.type == :pair

          pluck_value?(pair.children[1])
        end
      end

      def critical_pluck_in_hash?(node)
        return false unless node.is_a?(Parser::AST::Node) && node.type == :hash

        node.children.any? do |pair|
          next false unless pair.type == :pair

          critical_value?(pair.children[1])
        end
      end

      def pluck_value?(value)
        return false unless value.type == :lvar

        var_name = value.children[0]
        @pluck_variables.key?(var_name) || @map_id_variables.key?(var_name)
      end

      def critical_value?(value)
        if value.type == :lvar
          @critical_pluck_variables.key?(value.children[0])
        else
          all_pluck_call?(value)
        end
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
    end
  end
end
