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

  def with_preload
    # Using preload on separate line
    @orders = Order.preload(:customer)
    @orders.each do |order|
      order.customer.email
    end
  end

  def with_eager_load
    # Using eager_load on separate line
    comments = Comment.eager_load(:user)
    comments.each do |comment|
      comment.user.name
    end
  end

  def with_includes_separate_line
    # Using includes assigned to variable, then iterated
    posts = Post.includes(:author)
    posts.each { |post| post.author.name }
  end

  def show_action
    # Single record - no N+1 possible
    @user = User.find(params[:id])
    @user.posts.each do |post|
      post.comments.each(&:author)
    end
  end

  def with_find_by
    # Single record via find_by
    user = User.find_by(email: params[:email])
    user.orders.each(&:items)
  end

  def with_first_last
    # Single record via first/last
    @latest_post = Post.last
    @latest_post.comments.each { |c| c.user.name }
  end
end
