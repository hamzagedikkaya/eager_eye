# frozen_string_literal: true

# Clean serializer - no association access in blocks
class CleanPostSerializer < ActiveModel::Serializer
  attributes :id, :title, :body, :created_at

  attribute :formatted_date do
    object.created_at.strftime("%Y-%m-%d")
  end

  attribute :excerpt do
    object.body.truncate(100)
  end

  # Using declared associations instead of blocks
  belongs_to :author
  has_many :comments
end

# Blueprinter without N+1
class CleanArticleBlueprint < Blueprinter::Base
  identifier :id
  fields :title, :content, :published_at

  field :word_count do |article|
    article.content.split.size
  end

  field :status do |article|
    article.published? ? "published" : "draft"
  end
end

# Alba without N+1
class CleanProductResource
  include Alba::Resource

  attributes :id, :name, :price, :sku

  attribute :discounted_price do |product|
    product.price * 0.9
  end

  attribute :in_stock do |product|
    product.quantity > 0
  end
end
