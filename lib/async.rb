class Async
  AsyncResponse = [-1, {}, []].freeze
    
  def self.call(env)
    
    # Get the headers out there asap, let the client know we're alive...
      
      puts env['QUERY_STRING']
      account = env['QUERY_STRING'].dup
      account = account.split('=')[1]
      account = account.gsub('%40', '@')
      domain = account.split('@')[1]# get after the email address
      EventMachine.next_tick do
        puts "getting xrd"
        body = DeferrableBody.new
        
        
        xrd = EventMachine::HttpRequest.new(xrd_url(domain)).get :timeout => 5
          xrd.callback {
            doc = Nokogiri::XML::Document.parse(xrd.response)  
            webfinger_profile_url = swizzle account, doc.at('Link[rel=lrdd]').attribute('template').value 
            puts "getting webfinger profile"
            webfinger_profile = EventMachine::HttpRequest.new(webfinger_profile_url).get :timeout => 5

            webfinger_profile.callback {
            
              env["async.callback"].call [200, {'Content-Type' => 'text/plain'}, body]
              body.call [webfinger_profile.response]
              body.succeed
            }

            webfinger_profile.errback {
              env["async.callback"].call [200, {'Content-Type' => 'text/plain'}, body]
              body.call ["no webfinger found for that user"]
              body.succeed
            }
        }
         xrd.errback {
           puts "made it to the errback"
           env["async.callback"].call [200, {'Content-Type' => 'text/plain'}, body]
           body.call ["no xrd"]
           body.succeed
         }
     end
       
    AsyncResponse
  end

  
  def self.xrd_url(domain, ssl = false)
    "http#{'s' if ssl}://#{domain}/.well-known/host-meta"
  end

  def self.swizzle(account, template)
    template.gsub '{uri}', account
  end
  
  
  class DeferrableBody
    include EventMachine::Deferrable

    def call(body)
      body.each do |chunk|
        @body_callback.call(chunk)
      end
    end

    def each &blk
      @body_callback = blk
    end
  end
end