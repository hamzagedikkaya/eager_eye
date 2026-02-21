# frozen_string_literal: true

RSpec.describe EagerEye::Detectors::DelegationNPlusOne do
  let(:detector) { described_class.new }

  describe ".detector_name" do
    it "returns :delegation_n_plus_one" do
      expect(described_class.detector_name).to eq(:delegation_n_plus_one)
    end
  end

  describe "#detect" do
    def parse(source)
      Parser::CurrentRuby.parse(source)
    end

    context "with local delegate declarations" do
      it "detects delegated method called inside each block" do
        source = <<~RUBY
          class Order < ApplicationRecord
            belongs_to :user
            delegate :full_name, to: :user
          end

          orders.each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.detector).to eq(:delegation_n_plus_one)
        expect(issues.first.message).to include("order.full_name")
        expect(issues.first.message).to include("user")
        expect(issues.first.line_number).to eq(7)
      end

      it "detects multiple delegated methods to the same association" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, :email, to: :user
          end

          orders.each do |order|
            order.full_name
            order.email
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end

      it "detects delegated methods to different associations" do
        source = <<~RUBY
          class Post < ApplicationRecord
            delegate :bio, to: :author
            delegate :label, to: :category
          end

          posts.each do |post|
            post.bio
            post.label
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end

      it "detects delegation inside map block" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :company_name, to: :customer
          end

          orders.map { |order| order.company_name }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
        expect(issues.first.message).to include("order.company_name")
      end

      it "detects delegation inside select block" do
        source = <<~RUBY
          class User < ApplicationRecord
            delegate :active?, to: :subscription
          end

          users.select { |user| user.active? }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects delegation inside flat_map block" do
        source = <<~RUBY
          class Invoice < ApplicationRecord
            delegate :vat_number, to: :customer
          end

          invoices.flat_map { |invoice| invoice.vat_number }
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end

      it "detects delegation inside find_each block" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          Order.find_each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(1)
      end
    end

    context "with cross-file delegation maps" do
      it "detects delegation using provided delegation maps" do
        source = <<~RUBY
          Order.all.each do |order|
            order.full_name
            order.email
          end
        RUBY

        delegation_maps = { "Order" => { full_name: :user, email: :user } }
        issues = detector.detect(parse(source), "test.rb", delegation_maps)

        expect(issues.size).to eq(2)
        expect(issues.first.message).to include("user")
      end

      it "uses model name inferred from collection constant" do
        source = <<~RUBY
          Order.all.each do |order|
            order.company_name
          end
        RUBY

        delegation_maps = { "Order" => { company_name: :customer } }
        issues = detector.detect(parse(source), "test.rb", delegation_maps)

        expect(issues.size).to eq(1)
      end

      it "does not flag methods from a different model's delegation map" do
        source = <<~RUBY
          users.each do |user|
            user.company_name
          end
        RUBY

        delegation_maps = { "Order" => { company_name: :customer } }
        issues = detector.detect(parse(source), "test.rb", delegation_maps)

        expect(issues).to be_empty
      end
    end

    context "negative cases - should NOT detect" do
      it "does not detect when association is included inline" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.includes(:user).each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when association is preloaded inline" do
        source = <<~RUBY
          class Post < ApplicationRecord
            delegate :bio, to: :author
          end

          posts.preload(:author).each do |post|
            post.bio
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when association is eager_loaded inline" do
        source = <<~RUBY
          class Post < ApplicationRecord
            delegate :bio, to: :author
          end

          Post.eager_load(:author).each do |post|
            post.bio
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect non-delegated method calls" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.each do |order|
            order.total_price
            order.created_at
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when there are no delegate declarations and no delegation maps" do
        source = <<~RUBY
          orders.each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues).to be_empty
      end

      it "does not detect when target association is in cross-file includes" do
        source = <<~RUBY
          orders.includes(:user).each do |order|
            order.full_name
          end
        RUBY

        delegation_maps = { "Order" => { full_name: :user } }
        issues = detector.detect(parse(source), "test.rb", delegation_maps)

        expect(issues).to be_empty
      end

      it "does not flag the same delegated method twice on the same line" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.each do |order|
            puts order.full_name
            log(order.full_name)
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.size).to eq(2)
      end
    end

    context "with nil AST" do
      it "returns empty array" do
        issues = detector.detect(nil, "test.rb")

        expect(issues).to eq([])
      end
    end

    context "issue attributes" do
      it "includes suggestion with the target association" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.suggestion).to include("includes(:user)")
      end

      it "sets correct file_path" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.each { |order| order.full_name }
        RUBY

        issues = detector.detect(parse(source), "app/controllers/orders_controller.rb")

        expect(issues.first.file_path).to eq("app/controllers/orders_controller.rb")
      end

      it "sets correct line number" do
        source = <<~RUBY
          class Order < ApplicationRecord
            delegate :full_name, to: :user
          end

          orders.each do |order|
            order.full_name
          end
        RUBY

        issues = detector.detect(parse(source), "test.rb")

        expect(issues.first.line_number).to eq(6)
      end
    end

    context "with fixture files" do
      let(:fixtures_path) { File.expand_path("../fixtures", __dir__) }

      it "detects issues in delegation_n_plus_one_bad.rb" do
        file_path = File.join(fixtures_path, "delegation_n_plus_one_bad.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues.size).to be >= 5
      end

      it "detects no issues in delegation_n_plus_one_good.rb" do
        file_path = File.join(fixtures_path, "delegation_n_plus_one_good.rb")
        source = File.read(file_path)
        issues = detector.detect(parse(source), file_path)

        expect(issues).to be_empty
      end
    end
  end
end
