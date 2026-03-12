# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::ValidationNPlusOne do
  let(:detector) { described_class.new }
  let(:uniqueness_models) { Set["User"] }

  describe ".detector_name" do
    it "returns :validation_n_plus_one" do
      expect(described_class.detector_name).to eq(:validation_n_plus_one)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with Model.create inside iteration" do
      it "detects create call" do
        source = <<~RUBY
          params[:users].each do |user_params|
            User.create!(user_params)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:validation_n_plus_one)
        expect(issues.first.message).to include("User.create!")
        expect(issues.first.message).to include("uniqueness validation")
      end

      it "detects create (non-bang) call" do
        source = <<~RUBY
          items.each do |attrs|
            User.create(attrs)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("User.create")
      end
    end

    context "with Model.new + save inside iteration" do
      it "detects new + save! pattern" do
        source = <<~RUBY
          params[:users].each do |user_params|
            user = User.new(user_params)
            user.save!
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("User.save!")
      end

      it "detects new + save pattern" do
        source = <<~RUBY
          rows.each do |row|
            u = User.new(email: row[:email])
            u.save
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("User.save")
      end
    end

    context "with different iteration methods" do
      it "detects in map block" do
        source = <<~RUBY
          data.map { |d| User.create!(d) }
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
      end

      it "detects in find_each block" do
        source = <<~RUBY
          CSV.find_each do |row|
            User.create!(row)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(1)
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect create outside iteration" do
        source = <<~RUBY
          User.create!(email: "test@example.com")
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues).to be_empty
      end

      it "does not detect model without uniqueness validation" do
        source = <<~RUBY
          items.each do |attrs|
            Post.create!(attrs)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues).to be_empty
      end

      it "does not detect when uniqueness_models is empty" do
        source = <<~RUBY
          items.each { |attrs| User.create!(attrs) }
        RUBY

        issues = detector.detect(parse(source), "test.rb", Set.new)

        expect(issues).to be_empty
      end

      it "does not detect save on untracked variable" do
        source = <<~RUBY
          items.each do |item|
            item.save!
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues).to be_empty
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb", uniqueness_models)

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      it "includes suggestion" do
        source = <<~RUBY
          items.each { |attrs| User.create!(attrs) }
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.first.suggestion).to include("insert_all")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          items.each { |attrs| User.create!(attrs) }
        RUBY

        issues = detector.detect(parse(source), "app/services/importer.rb", uniqueness_models)

        expect(issues.first.file_path).to eq("app/services/importer.rb")
      end

      it "sets correct line_number" do
        source = <<~RUBY
          x = 1
          items.each do |attrs|
            User.create!(attrs)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.first.line_number).to eq(3)
      end
    end

    context "with multiple models" do
      let(:uniqueness_models) { Set["User", "Account"] }

      it "detects both models" do
        source = <<~RUBY
          data.each do |row|
            User.create!(row[:user])
            Account.create!(row[:account])
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb", uniqueness_models)

        expect(issues.size).to eq(2)
      end
    end
  end
end
