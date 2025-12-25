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

        return @issues unless ast

        collect_pluck_assignments(ast)
        collect_map_id_assignments(ast)
        find_where_with_pluck_var(ast)

        @issues
      end

      private

      def collect_pluck_assignments(node)
        return unless node.is_a?(Parser::AST::Node)

        if local_variable_assignment?(node)
          var_name = node.children[0]
          value = node.children[1]

          @pluck_variables[var_name] = node.loc.line if pluck_call?(value)
        end

        node.children.each do |child|
          collect_pluck_assignments(child)
        end
      end

      def collect_map_id_assignments(node)
        return unless node.is_a?(Parser::AST::Node)

        if local_variable_assignment?(node)
          var_name = node.children[0]
          value = node.children[1]

          @map_id_variables[var_name] = node.loc.line if map_id_call?(value)
        end

        node.children.each do |child|
          collect_map_id_assignments(child)
        end
      end

      def find_where_with_pluck_var(node)
        return unless node.is_a?(Parser::AST::Node)

        add_issue(node) if where_call_with_pluck_var?(node)

        node.children.each do |child|
          find_where_with_pluck_var(child)
        end
      end

      def local_variable_assignment?(node)
        node.type == :lvasgn
      end

      def pluck_call?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless node.type == :send

        method_name = node.children[1]
        %i[pluck ids].include?(method_name)
      end

      def map_id_call?(node)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :block then block_map_call?(node)
        when :send then send_map_id_call?(node)
        else false
        end
      end

      def block_map_call?(node)
        send_node = node.children[0]
        return false unless send_node&.type == :send

        %i[map collect].include?(send_node.children[1])
      end

      def send_map_id_call?(node)
        method_name = node.children[1]
        return false unless %i[map collect].include?(method_name)

        node.children[2..].any? { |arg| symbol_to_proc_id?(arg) }
      end

      def symbol_to_proc_id?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless node.type == :block_pass

        sym_node = node.children[0]
        return false unless sym_node&.type == :sym

        %i[id to_i].include?(sym_node.children[0])
      end

      def where_call_with_pluck_var?(node)
        return false unless node.type == :send
        return false unless node.children[1] == :where

        args = node.children[2..]
        args.any? { |arg| hash_with_pluck_var?(arg) }
      end

      def hash_with_pluck_var?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return false unless node.type == :hash

        node.children.any? do |pair|
          next false unless pair.type == :pair

          value = pair.children[1]
          if value.type == :lvar
            var_name = value.children[0]
            @pluck_variables.key?(var_name) || @map_id_variables.key?(var_name)
          else
            false
          end
        end
      end

      def add_issue(node)
        @issues << create_issue(
          file_path: @file_path,
          line_number: node.loc.line,
          message: "Using plucked/mapped array in `where` causes two queries and holds IDs in memory",
          suggestion: "Use `.select(:id)` subquery: `Model.where(col: OtherModel.condition.select(:id))`"
        )
      end
    end
  end
end
