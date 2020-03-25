class Gel::GitGemsManager
  # These gems all live in rails/rails repository.
  META_GEMS = {
    "activesupport" => "rails",
    "actionpack" => "rails",
    "actionview" => "rails",
    "activemodel" => "rails",
    "activerecord" => "rails",
    "actionmailer" => "rails",
    "activejob" => "rails",
    "actioncable" => "rails",
    "activestorage" => "rails",
    "actionmailbox" => "rails",
    "actiontext" => "rails",
    "railties" => "rails",
  }

  def self.lookup(name)
    META_GEMS.fetch(name) { name }
  end
end
