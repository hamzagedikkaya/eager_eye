# frozen_string_literal: true

# Fixture: decorator N+1 good examples
# These patterns should NOT be detected by DecoratorNPlusOne detector

# Good: non-decorator class — not flagged
class PostsController
  def index
    object.comments.map(&:body) # not inside a decorator, ignored
  end
end

# Good: decorator that only accesses plain attributes
class PostDecorator < Draper::Decorator
  delegate_all

  def formatted_title
    object.title.upcase
  end

  def published_date
    object.created_at.strftime("%B %d, %Y")
  end

  def status_label
    object.status.to_s.humanize
  end
end

# Good: Presenter with no has_many association access
class UserPresenter
  def full_name
    "#{model.first_name} #{model.last_name}"
  end

  def avatar_url
    model.avatar.attached? ? model.avatar.url : "/default_avatar.png"
  end
end

# Good: class name does not match decorator patterns
class PostHelper
  def comment_list(object)
    object.comments.map(&:body) # not a decorator class, ignored
  end
end
