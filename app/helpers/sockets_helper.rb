#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module SocketsHelper
 include ApplicationHelper

 def obj_id(object)
    (object.is_a? Post) ? object.id : object.post_id
  end

  def action_hash(uid, object, opts={})
    begin
      user = User.find_by_id uid
      if object.is_a? Post
        v = render_to_string(:partial => 'shared/stream_element', :locals => {:post => object, :current_user => user}) unless object.is_a? Retraction
      else
        v = render_to_string(:partial => type_partial(object), :locals => {:post => object, :current_user => user}) unless object.is_a? Retraction
      end
    rescue Exception => e
      Rails.logger.error("web socket view rendering failed for object #{object.inspect}.")
      raise e
    end
    action_hash = {:class =>object.class.to_s.underscore.pluralize,  :html => v, :post_id => obj_id(object)}
    action_hash.merge! opts
    if object.is_a? Photo
      action_hash[:photo_hash] = object.thumb_hash
    end

    if object.is_a? Comment
      action_hash[:my_post?] = (object.post.person.owner.id == uid)
      action_hash[:notification] = notification(object)
    end

    action_hash[:mine?] = object.person && (object.person.owner.id == uid)

    action_hash.to_json
  end

  def notification(object)
    begin
      render_to_string(:partial => 'shared/notification', :locals => {:object => object})
    rescue Exception => e
      Rails.logger.error("web socket notification failed for object #{object.inspect}.")
    end
  end
end
