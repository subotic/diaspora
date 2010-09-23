#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3.  See
#   the COPYRIGHT file.


require 'lib/hcard'

class Person
  include MongoMapper::Document
  include ROXML
  include Encryptor::Public

  xml_accessor :_id
  xml_accessor :diaspora_handle
  xml_accessor :url
  xml_accessor :profile, :as => Profile
  xml_reader :exported_key

  key :url,            String
  key :diaspora_handle, String, :unique => true
  key :serialized_key, String

  key :owner_id,  ObjectId

  one :profile, :class_name => 'Profile'
  many :albums, :class_name => 'Album', :foreign_key => :person_id
  belongs_to :owner, :class_name => 'User'

  timestamps!

  before_destroy :remove_all_traces
  before_validation :clean_url
  validates_presence_of :url, :profile, :serialized_key
  validates_format_of :url, :with =>
     /^(https?):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*(\.[a-z]{2,5})?(:[0-9]{1,5})?(\/.*)?$/ix

  def self.search(query)
    query = Regexp.escape( query.to_s.strip )
    Person.all('profile.first_name' => /^#{query}/i) | Person.all('profile.last_name' => /^#{query}/i)
  end

  def real_name
    "#{profile.first_name.to_s} #{profile.last_name.to_s}"
  end
  def owns?(post)
    self.id == post.person.id
  end

  def receive_url
    "#{self.url}receive/users/#{self.id}/"
  end

  def encryption_key
    OpenSSL::PKey::RSA.new( serialized_key )
  end

  def encryption_key= new_key
    raise TypeError unless new_key.class == OpenSSL::PKey::RSA
    serialized_key = new_key.export
  end

  def public_key_hash
    Base64.encode64 OpenSSL::Digest::SHA256.new(self.exported_key).to_s
  end

  def public_key
    encryption_key.public_key
  end

  def exported_key
    encryption_key.public_key.export
  end

  def exported_key= new_key
    raise "Don't change a key" if serialized_key
    @serialized_key = new_key
  end

  #webfinger methods
  def self.by_account_identifier(identifier)
    self.first(:diaspora_handle => identifier.gsub('acct:', '').to_s.downcase)
  end

  def self.local_by_account_identifier(identifier)
    person = self.by_account_identifier(identifier)
   (person.nil? || person.remote?) ? nil : person
  end

  def self.from_webfinger(identifier, opts = {})
    local_person = self.by_account_identifier(identifier)
    if local_person
      Rails.logger.info("Do not need to webfinger, found a local person #{local_person.real_name}")
      return local_person
    end
    unless opts[:webfinger_profile]
        begin
        Rails.logger.info("Webfingering #{identifier}")
        profile = Redfinger.finger(identifier)
      rescue
        raise "There was a profile with webfingering #{identifier}"
      end
      self.from_webfinger_profile(identifier, profile)
    else
      self.from_webfinger_nokogiri(identifier, opts[:webfinger_profile])
    end
    # loop here until opts[:webfinger_profile] is not nil

  end



def self.from_webfinger_profile( identifier, profile)
    new_person = Person.new

    public_key_entry = profile.links.select{|x| x.rel == 'diaspora-public-key'}
    
    return nil unless public_key_entry
    
    pubkey = public_key_entry.first.href
    new_person.exported_key = Base64.decode64 pubkey

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

      webfinger_profile = EventMachine::HttpRequest.new(webfinger_profile_url).get :timeout => 5

        webfinger_profile.callback {
          return webfinger_profile.response 
        }

        webfinger_profile.errback {
          raise "no webfinger found for that user"
        }
    end  
  
    def self.from_webfinger_nokogiri(account, webfinger_profile)
      new_person = Person.new
      new_person.diaspora_handle = account
      doc = Nokogiri::XML.parse(webfinger_profile)
      
      doc.css('Link').each do |l|  
        case l.attribute("rel").value 
          when "http://microformats.org/profile/hcard"
            #new_person.hcard = l.attribute("href").value
          when "http://joindiaspora.com/guid"
            new_person.id = l.attribute("href").value          
          when "http://joindiaspora.com/seed_location"
             new_person.url = l.attribute("href").value
        end
      end
      pubkey = doc.at('Link[rel=diaspora-public-key]').attribute('href').value
      return false if pubkey.nil?
      new_person.profile = Profile.new(:first_name => "unknown", :last_name => "person")
      new_person.exported_key = Base64.decode64 pubkey
      new_person.save!
      new_person
    end


    def xrd_url(domain, ssl = false)
      "http#{'s' if ssl}://#{domain}/.well-known/host-meta"
    end

    def swizzle(account, template)
      template.gsub '{uri}', account
    end

##end webfinger stuff


  def remote?
    owner.nil?
  end

  def as_json(opts={})
    {
      :person => {
        :id           => self.id,
        :name         => self.real_name,
        :diaspora_handle        => self.diaspora_handle,
        :url          => self.url,
        :exported_key => exported_key
      }
    }
  end

  protected
  def clean_url
    self.url ||= "http://localhost:3000/" if self.class == User
    if self.url
      self.url = 'http://' + self.url unless self.url.match('http://' || 'https://')
      self.url = self.url + '/' if self.url[-1,1] != '/'
    end
  end

  private
  def remove_all_traces
    Post.all(:person_id => id).each{|p| p.delete}
    Album.all(:person_id => id).each{|p| p.delete}
  end
end
