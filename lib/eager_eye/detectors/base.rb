# frozen_string_literal: true

require "parser/current"

module EagerEye
  module Detectors
    class Base
      class << self
        def detector_name
          raise NotImplementedError, "Subclasses must implement .detector_name"
        end

        def default_severity
          :warning
        end
      end

      def detect(_ast, _file_path)
        raise NotImplementedError, "Subclasses must implement #detect"
      end

      protected

      def create_issue(file_path:, line_number:, message:, severity: nil, suggestion: nil)
        Issue.new(
          detector: self.class.detector_name,
          file_path: file_path,
          line_number: line_number,
          message: message,
          severity: severity || configured_severity,
          suggestion: suggestion
        )
      end

      def configured_severity
        EagerEye.configuration.severity_for(self.class.detector_name)
      end

      def traverse_ast(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        yield node
        node.children.each { |child| traverse_ast(child, &block) }
      end

      def parse_source(source)
        Parser::CurrentRuby.parse(source)
      rescue Parser::SyntaxError
        nil
      end

      def extract_method_args(node)
        return [] unless node&.type == :send

        node.children[2..]
      end

      def extract_symbols_from_args(args)
        symbols = Set.new
        args.each do |arg|
          case arg&.type
          when :sym then symbols.add(arg.children[0])
          when :hash then extract_symbols_from_hash(arg, symbols)
          end
        end
        symbols
      end

      def extract_symbols_from_hash(hash_node, symbols)
        hash_node.children.each do |pair|
          key = pair.children[0]
          symbols.add(key.children[0]) if key&.type == :sym
        end
      end

      def extract_block_variable(block_node)
        args = block_node&.children&.[](1)
        first_arg = args&.children&.first
        first_arg&.type == :arg ? first_arg.children[0] : nil
      end

      def receiver_chain_starts_with?(node, target_var)
        return false unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar then node.children[0] == target_var
        when :send then receiver_chain_starts_with?(node.children[0], target_var)
        else false
        end
      end

      def reconstruct_chain(node)
        return "" unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvar then node.children[0].to_s
        when :send
          receiver_str = reconstruct_chain(node.children[0])
          receiver_str.empty? ? node.children[1].to_s : "#{receiver_str}.#{node.children[1]}"
        else ""
        end
      end
    end
  end
end
