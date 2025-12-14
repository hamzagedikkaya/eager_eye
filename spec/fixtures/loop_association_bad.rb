# frozen_string_literal: true

class LoopAssociationBadController
  def index
    # Basic each loop with association
    @posts = Post.all
    @posts.each do |post|
      post.author.name
      post.category.title
    end
  end

  def show
    # Map with association
    @comments = Comment.all
    @comments.map { |comment| comment.user.email }
  end

  def edit
    # Select with association
    @orders = Order.all
    @orders.select { |order| order.customer.active? }
  end

  def update
    # Find with association
    @items = Item.all
    @items.find { |item| item.vendor.verified? }
  end

  def nested
    # Nested loops with associations
    @users = User.all
    @users.each do |user|
      user.posts.each do |post|
        post.comments.each do |comment|
          comment.author.name
        end
      end
    end
  end

  def chained
    # Chained method calls
    @posts = Post.all
    @posts.each do |post|
      post.author.profile.avatar_url
    end
  end
end
