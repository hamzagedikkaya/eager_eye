# frozen_string_literal: true

class LoopAssociationGoodController
  def index
    # Properly eager loaded
    @posts = Post.includes(:author, :category).all
    @posts.each do |post|
      post.author.name
      post.category.title
    end
  end

  def show
    # Only accessing non-association methods
    @posts = Post.all
    @posts.each do |post|
      post.title
      post.body
      post.created_at
    end
  end

  def edit
    # Using local variables
    @items = Item.all
    @items.each do |item|
      price = item.price
      quantity = item.quantity
      _total = price * quantity
    end
  end

  def safe_methods
    # Using safe ActiveRecord methods
    @posts = Post.all
    @posts.each do |post|
      post.id
      post.persisted?
      post.new_record?
      post.to_param
    end
  end
end
