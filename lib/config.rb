
require 'webrick/config'
#require 'RAI/call_handler'

module Telegraph
  
  DEFAULT_PORT = 4573

  module Config

    # for HTTPServer, HTTPRequest, HTTPResponse ...
    Standard = WEBrick::Config::General.dup.update(
      :Port           => Telegraph::DEFAULT_PORT
    )

    Globals = {
      # Name of the box running the agi server, so that asterisk can find it
      # by default this will use your Ruby server's name
      "agiServer" => 'localhost',
      
      # Path to use for saving outgoing call files
      "outgoingCallPath" => 
        ENV['RAI_OUT_CALL_PATH'] ? ENV['RAI_OUT_CALL_PATH'] : "/var/spool/asterisk/outgoing",

      # Path to use for saving wakeup call files
      "wakeupCallPath" =>
        ENV['RAI_WAKEUP_CALL_PATH'] ? ENV['RAI_WAKEUP_CALL_PATH'] : "var/spool/asterisk/wakeups",

       "SOUNDPATH" => 
        ENV['RAI_SOUND_PATH'] ? ENV['RAI_SOUND_PATH'] : File.expand_path(File.join(RAILS_ROOT,'sounds')),
        
        "RECORDINGPATH" =>
          ENV['RAI_RECORDING_PATH'] ? ENV['RAI_RECORDING_PATH'] : File.expand_path(File.join(RAILS_ROOT,'public/sound_files'))
        
      
    }

  end
end
