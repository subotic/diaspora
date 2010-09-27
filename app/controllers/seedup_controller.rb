class SeedupController < ApplicationController
    def get
        getKey = params[:id]
        key = "9c1d33312211d7fe25c3d277d6bc9e40"
        
        if getKey == key
            require 'mongo'
            db = Mongo::Connection.new.db("diaspora-"+RAILS_ENV)
            @userCount = db["users"].count;
            @commitCount = `git log --pretty=oneline | wc -l`;
            render :inline => '<?xml version="1.0"?><root><version><%= @commitCount %></version><users><%= @userCount %></users></root>', :content_type => "application/xml"
        else
            render :inline => '<?xml version="1.0"?> <root> <errorcode>401<errorcode> <error>Unauthorized</error></root>', :content_type => "application/xml"
        end
    end
end