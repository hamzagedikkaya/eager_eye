# frozen_string_literal: true

# ActiveModel::Serializer style
class PostSerializer < ActiveModel::Serializer
  attribute :author_name do
    object.author.name
  end

  attribute :category_title do
    object.category.title
  end

  attribute :recent_comments do
    object.comments.last(5).map { |c| c.user.name }
  end
end

# Blueprinter style
class ArticleBlueprint < Blueprinter::Base
  field :author_name do |article|
    article.author.name
  end

  field :editor_email do |article|
    article.editor.email
  end
end

# Alba style
class ProductResource
  include Alba::Resource

  attribute :manufacturer_name do |product|
    product.manufacturer.name
  end

  attribute :supplier_info do |product|
    product.supplier.contact_info
  end
end

# Nested serializer with block
class OrderSerializer < ActiveModel::Serializer
  attribute :customer_details do
    {
      name: object.customer.name,
      email: object.customer.email,
      address: object.customer.address.full_address
    }
  end
end
