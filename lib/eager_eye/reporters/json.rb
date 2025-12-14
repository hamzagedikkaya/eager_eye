# frozen_string_literal: true

require "json"

module EagerEye
  module Reporters
    class Json < Base
      def initialize(issues, pretty: false)
        super(issues)
        @pretty = pretty
      end

      def report
        result = {
          summary: summary_hash,
          issues: issues.map(&:to_h)
        }

        @pretty ? JSON.pretty_generate(result) : JSON.generate(result)
      end

      private

      def summary_hash
        {
          total: issues.size,
          warnings: warning_count,
          errors: error_count,
          files_affected: issues_by_file.keys.size
        }
      end
    end
  end
end
