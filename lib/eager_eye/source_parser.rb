# frozen_string_literal: true

# Require the grammar matching the running Ruby's minor version (parser/ruby33
# for any 3.3.x) instead of parser/current, which insists on an exact *patch*
# match and warns on every load otherwise ("parser/current is loading
# parser/ruby33, which recognizes 3.3.4-compliant syntax, but you are running
# 3.3.1"). Grammar only changes between minor versions, so the versioned
# require is exactly as correct — and is the parser gem's documented way to
# opt out of the warning. Unknown future Rubies fall back to parser/current.
begin
  require "parser/ruby#{RUBY_VERSION.split(".").first(2).join}"
rescue LoadError
  require "parser/current"
end

module EagerEye
  # Single entry point for turning Ruby source into an AST. Differs from
  # `Parser::CurrentRuby.parse` in two ways that matter for a CLI tool:
  #
  #   * No stderr side effects. The default parser prints every lexer/parser
  #     diagnostic straight to $stderr — so one unparseable file (e.g. a model
  #     holding a binary string literal whose escapes are invalid UTF-8) dumps
  #     a raw three-line diagnostic once per analysis pass. Diagnostics stay
  #     quiet here; failures surface only as the raised exception.
  #   * The buffer is named after the real file, so callers can report
  #     "app/models/coupon.rb", not "(string)".
  #
  # Raises like the original — Parser::SyntaxError, EncodingError, or
  # Parser::UnknownEncodingInMagicComment (an ArgumentError, NOT a
  # SyntaxError, raised for e.g. `# encoding: utf8` typos); callers decide
  # whether and how to report.
  module SourceParser
    PARSER_CLASS =
      begin
        Parser.const_get(:"Ruby#{RUBY_VERSION.split(".").first(2).join}", false)
      rescue NameError
        Parser::CurrentRuby
      end

    def self.parse(source, file_path = "(string)")
      parser = PARSER_CLASS.new
      parser.diagnostics.all_errors_are_fatal = true
      parser.diagnostics.ignore_warnings = true

      buffer = Parser::Source::Buffer.new(file_path, 1)
      buffer.source = source.dup.force_encoding(parser.default_encoding)
      parser.parse(buffer)
    end
  end
end
