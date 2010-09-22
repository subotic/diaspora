require 'sinatra/async'

class AsyncController < Sinatra::Base
  register Sinatra::Async

  aget '/finger' do
    account = params[:webfinger_handle]
    domain = params[:webfinger_handle].split('@')[1] # get after the email address
    xrd = EventMachine::HttpRequest.new(xrd_url(domain)).get :timeout => 5
      xrd.callback {
        doc = Nokogiri::XML::Document.parse(xrd.response)  
        puts doc.to_s    
        webfinger_profile_url = swizzle account, doc.at('Link[rel=lrdd]').attribute('template').value 
        
        webfinger_profile = EventMachine::HttpRequest.new(webfinger_profile_url).get :timeout => 5
      
        webfinger_profile.callback {
          puts webfinger_profile.response
          body { webfinger_profile.response} 
        }
      
        webfinger_profile.errback {
          body {"no webfinger found for that user"}
        }
    }
    
    
     xrd.errback {
       body {"no xrd found"}
     }
  end
  
  def xrd_url(domain, ssl = false)
    "http#{'s' if ssl}://#{domain}/.well-known/host-meta"
  end

  def swizzle(account, template)
    template.gsub '{uri}', account
  end
end


