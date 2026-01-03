# frozen_string_literal: true

# ActiveModel::Serializer style - has_many associations (N+1 risk)
class PostSerializer < ActiveModel::Serializer
  attribute :authors_list do
    object.authors.map(&:name)
  end

  attribute :categories_list do
    object.categories.map(&:title)
  end

  attribute :recent_comments do
    object.comments.last(5).map { |c| c.users.first.name }
  end
end

# Blueprinter style
class ArticleBlueprint < Blueprinter::Base
  field :authors_list do |article|
    article.authors.map(&:name)
  end

  field :tags_list do |article|
    article.tags.map(&:name)
  end
end

# Alba style
class ProductResource
  include Alba::Resource

  attribute :images_list do |product|
    product.images.map(&:url)
  end

  attribute :attachments_list do |product|
    product.attachments.map(&:filename)
  end
end

# Nested serializer with block
class OrderSerializer < ActiveModel::Serializer
  attribute :items_details do
    {
      names: object.items.map(&:name),
      prices: object.items.map(&:price),
      products: object.products.map(&:sku)
    }
  end
end
