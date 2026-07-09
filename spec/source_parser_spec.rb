# frozen_string_literal: true

RSpec.describe EagerEye::SourceParser do
  describe ".parse" do
    it "parses valid Ruby source into an AST" do
      ast = described_class.parse("users.each { |user| user.posts }")

      expect(ast).to be_a(Parser::AST::Node)
      expect(ast.type).to eq(:block)
    end

    it "names the buffer after the given file path" do
      ast = described_class.parse("x = 1", "app/models/user.rb")

      expect(ast.loc.expression.source_buffer.name).to eq("app/models/user.rb")
    end

    it "defaults the buffer name to (string)" do
      ast = described_class.parse("x = 1")

      expect(ast.loc.expression.source_buffer.name).to eq("(string)")
    end

    it "raises Parser::SyntaxError on invalid syntax without printing diagnostics" do
      expect do
        expect { described_class.parse("def broken(", "bad.rb") }.to raise_error(Parser::SyntaxError)
      end.not_to output.to_stderr
    end

    it "raises quietly on string literals whose escapes are invalid UTF-8" do
      source = 'KEY = "\x8E\xAFH-\xC9"'

      expect do
        expect { described_class.parse(source, "app/models/coupon.rb") }
          .to raise_error(Parser::SyntaxError, /escape sequences incompatible/)
      end.not_to output.to_stderr
    end

    it "raises quietly on unknown magic encoding comments (an ArgumentError, not a SyntaxError)" do
      source = "# encoding: utf8\nx = 1"

      expect do
        expect { described_class.parse(source, "bad.rb") }
          .to raise_error(Parser::UnknownEncodingInMagicComment)
      end.not_to output.to_stderr
    end

    it "reports the file path in the diagnostic location" do
      described_class.parse('KEY = "\x8E"', "app/models/coupon.rb")
      raise "expected Parser::SyntaxError"
    rescue Parser::SyntaxError => e
      expect(e.diagnostic.location.source_buffer.name).to eq("app/models/coupon.rb")
    end

    it "does not mutate the given source string" do
      source = "x = 1"
      described_class.parse(source)

      expect(source.encoding).to eq(Encoding::UTF_8)
      expect(source).to eq("x = 1")
    end
  end

  describe "library load" do
    it "requires eager_eye without the parser/current version-deviation warning" do
      lib = File.expand_path("../lib", __dir__)
      output = IO.popen(
        [RbConfig.ruby, "-I", lib, "-e", 'require "eager_eye"', { err: %i[child out] }], &:read
      )

      expect(Process.last_status).to be_success
      expect(output).not_to match(%r{parser/current is loading})
    end
  end
end
