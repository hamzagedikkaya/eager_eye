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
        resolved_severity = severity || configured_severity
        Issue.new(
          detector: self.class.detector_name,
          file_path: file_path,
          line_number: line_number,
          message: message,
          severity: resolved_severity,
          suggestion: suggestion
        )
      end

      def configured_severity
        EagerEye.configuration.severity_for(self.class.detector_name)
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
