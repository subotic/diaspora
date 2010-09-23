module Diaspora
  module Webfinger
    
    #webfinger methods
    def self.by_account_identifier(identifier)
      Person.first(:diaspora_handle => identifier.gsub('acct:', '').to_s.downcase)
    end

    def self.local_by_account_identifier(identifier)
      person = Person.by_account_identifier(identifier)
     (person.nil? || person.remote?) ? nil : person
    end

    def self.from_webfinger(identifier, opts = {})
      local_person = Person.by_account_identifier(identifier)
      if local_person
        Rails.logger.info("Do not need to webfinger, found a local person #{local_person.real_name}")
        return local_person
      end
      unless opts[:webfinger_profile]
          begin
          Rails.logger.info("Webfingering #{identifier}")
          opts[:webfinger_profile] = self.webfinger(identifier)
        rescue
          raise "There was a profile with webfingering #{identifier}"
        end
      end
      #here on out, webfinger_profile is set with a profile

      Person.create_from_webfinger_profile(identifier, opts[:webfinger_profile])
    end


    def self.webfinger(identifier)
      domain = identifier.split('@')[1] # get after the email address
        EventMachine::next_tick do
          xrd = EventMachine::HttpRequest.new(xrd_url(domain)).get :timeout => 5
          xrd.callback {
            self.get_webfinger_profile(identifier, xrd_response)
          }
           xrd.errback {
             raise "no xrd found"
           }
        end
    end

    def self.get_webfinger_profile(account, xrd_response)
      doc = Nokogiri::XML::Document.parse(xrd_response)  
      webfinger_profile_url = swizzle account, doc.at('Link[rel=lrdd]').attribute('template').value 
      pubkey = public_key_entry.first.href
      new_person.exported_key = Base64.decode64 pubkey

      guid = profile.links.select{|x| x.rel == 'http://joindiaspora.com/guid'}.first.href
      new_person.id = guid

      webfinger_profile = EventMachine::HttpRequest.new(webfinger_profile_url).get :timeout => 5

        webfinger_profile.callback {
          return webfinger_profile.response #Person.create_from_webfinger(identifier, webfinger_profile.response)
        }

        webfinger_profile.errback {
          raise "no webfinger found for that user"
        }
    end


    def self.create_from_webfinger_profile(identifier, profile)

      new_person = Person.new    
      public_key_entry = profile.links.select{|x| x.rel == 'diaspora-public-key'}
      return nil unless public_key_entry
      public_key = public_key_entry.first.href
      new_person.exported_key = Base64.decode64 public_key

      guid = profile.links.select{|x| x.rel == 'http://joindiaspora.com/guid'}.first.href
      new_person.id = guid

      new_person.diaspora_handle = identifier

      hcard = HCard.find profile.hcard.first[:href]

      new_person.url = hcard[:url]
      new_person.profile = Profile.new(:first_name => hcard[:given_name], :last_name => hcard[:family_name])
      if new_person.save
        new_person
      else
        nil
      end
    end


    def xrd_url(domain, ssl = false)
      "http#{'s' if ssl}://#{domain}/.well-known/host-meta"
    end

    def swizzle(account, template)
      template.gsub '{uri}', account
    end
  end
end