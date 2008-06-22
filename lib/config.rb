require 'webrick/config'
require 'yaml'

#require 'RAI/call_handler'

module Telegraph
  module Config
    begin
      Globals = YAML.load_file(RAILS_ROOT + '/config/telegraph.yaml')[RAILS_ENV]
    rescue
    
      Globals = {}
    end
    # set defaults if any values are missing.
    
    #NOTE:: You can not use symbols here to access the config because they are coming from the 
    # YAML files as strings
    Globals['agi_port'] ||= 4573
    Globals['agi_server'] ||= '0.0.0.0'
    Globals['ami_server'] ||= "druby://localhost:9000"
    Globals['outgoing_call_path'] ||= ( ENV['RAI_OUT_CALL_PATH'] || '')
    Globals['wakeup_call_path'] ||= (ENV['RAI_WAKEUP_CALL_PATH'] || '')
    #default to relative paths
    Globals['sound_path'] ||= (ENV['RAI_SOUND_PATH'] || '')
    Globals['recording_path'] ||= (ENV['RAI_RECORDING_PATH'] || '')
    Globals['ami_host'] ||= 'localhost'
    Globals['ami_port'] ||= 5038
    Globals['ami_username'] ||= 'asterisk'
    Globals['ami_secret'] ||= 'secret'

 
    # for HTTPServer, HTTPRequest, HTTPResponse ...
    Standard = WEBrick::Config::General.dup.update(
        :Port => Telegraph::Config::Globals['agi_port']
    )
   end
end
