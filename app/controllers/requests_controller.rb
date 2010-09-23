#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3.  See
#   the COPYRIGHT file.


class RequestsController < ApplicationController
  before_filter :authenticate_user!
  include RequestsHelper

  respond_to :html

  def destroy
    if params[:accept]
      if params[:aspect_id]
        @friend = current_user.accept_and_respond( params[:id], params[:aspect_id])
        flash[:notice] = I18n.t 'requests.destroy.success'
        respond_with :location => current_user.aspect_by_id(params[:aspect_id])
      else
        flash[:error] = I18n.t 'requests.destroy.error'
        respond_with :location => requests_url
      end
    else
      current_user.ignore_friend_request params[:id]
      flash[:notice] = I18n.t 'requests.destroy.ignore'
      respond_with :location => requests_url
    end
  end

  def new
    @request = Request.new
  end

  def create
    puts params.inspect
    aspect = current_user.aspect_by_id(params[:aspect_id])
    account = params[:account_identifier]

    #if we have used the controller, or it it is a local friend, we are all set
    person = Person.by_account_identifier(account)

    #you are passed a an email, and you dont have a person for it, therefore need to webfinger
    #if looks like a valid email
    person ||= Person.from_webfinger(account)

    respond_with :location => aspect if person.nil?
  
    
    Rails.logger.info "sending a request to " + person.diaspora_handle
     
     begin
       @request = current_user.send_friend_request_to(person, aspect)
     rescue Exception => e
       raise e unless e.message.include? "already friends"
       flash[:notice] = "You are already friends with #{person.diaspora_handle}!"
       respond_with :location => aspect
       return
     end
     
     if @request
       flash[:notice] =  "A friend request was sent to #{person.diaspora_handle}."
       respond_with :location => aspect
     else
       flash[:error] = "Something went horribly wrong."
       respond_with :location => aspect
     end
  end
end
