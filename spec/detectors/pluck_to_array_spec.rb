# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::PluckToArray do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :pluck_to_array" do
      expect(described_class.detector_name).to eq(:pluck_to_array)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "when pluck result is used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("pluck")
        expect(issues.first.suggestion).to include(".select(:id)")
      end
    end

    context "when .ids is used" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.ids
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when map(&:id) is used" do
      let(:code) do
        <<~RUBY
          user_ids = users.map(&:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when collect(&:id) is used" do
      let(:code) do
        <<~RUBY
          ids = records.collect(&:id)
          Item.where(record_id: ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when map(&:to_i) is used" do
      let(:code) do
        <<~RUBY
          ids = strings.map(&:to_i)
          Item.where(id: ids)
        RUBY
      end

      it "detects the issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "when select subquery is used correctly" do
      let(:code) do
        <<~RUBY
          Post.where(user_id: User.active.select(:id))
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when pluck is used for non-where purposes" do
      let(:code) do
        <<~RUBY
          emails = User.active.pluck(:email)
          send_newsletter(emails)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when pluck variable is not used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          process_ids(user_ids)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "when different variable is used in where" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          other_ids = [1, 2, 3]
          Post.where(user_id: other_ids)
        RUBY
      end

      it "does not report an issue" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      let(:code) do
        <<~RUBY
          user_ids = User.active.pluck(:id)
          Post.where(user_id: user_ids)
        RUBY
      end

      it "sets correct detector name" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.detector).to eq(:pluck_to_array)
      end

      it "sets correct file_path" do
        ast = parse(code)
        issues = detector.detect(ast, "app/services/post_service.rb")

        expect(issues.first.file_path).to eq("app/services/post_service.rb")
      end

      it "sets correct line_number" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.line_number).to eq(2)
      end

      it "includes suggestion about select subquery" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.first.suggestion).to include("select")
      end
    end

    context "with critical .all.pluck pattern" do
      let(:code) do
        <<~RUBY
          Post.where(user_id: User.all.pluck(:id))
        RUBY
      end

      it "detects critical issue with error severity" do
        ast = parse(code)
        issues = detector.detect(ast, "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.severity).to eq(:error)
        expect(issues.first.message).to include(".all.pluck")
      end
    end
  end
end
