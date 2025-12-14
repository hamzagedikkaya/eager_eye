# frozen_string_literal: true

require "parser/current"

module EagerEye
  module Detectors
    class Base
      class << self
        def detector_name
          raise NotImplementedError, "Subclasses must implement .detector_name"
        end
      end

      def detect(_ast, _file_path)
        raise NotImplementedError, "Subclasses must implement #detect"
      end

      protected

      def create_issue(file_path:, line_number:, message:, severity: :warning, suggestion: nil)
        Issue.new(
          detector: self.class.detector_name,
          file_path: file_path,
          line_number: line_number,
          message: message,
          severity: severity,
          suggestion: suggestion
        )
      end

      def traverse_ast(node, &block)
        return unless node.is_a?(Parser::AST::Node)

        yield node

        node.children.each do |child|
          traverse_ast(child, &block)
        end
      end

      def parse_source(source)
        Parser::CurrentRuby.parse(source)
      rescue Parser::SyntaxError
        nil
      end
    end
  end
end
