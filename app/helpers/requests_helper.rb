#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3.  See
#   the COPYRIGHT file.


module RequestsHelper
  def relationship_flow(identifier)
    action = :none
    person = nil


    if identifier.contains?('@')#prob an email
      person = Person.from_webfinger identifier
    end

    if person
      action = (person == current_user.person ? :none : :friend)
    end
    { action => person }
  end
end
