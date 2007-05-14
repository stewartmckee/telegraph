# Copy server files into script/server
require 'ftools'

%w{agi_server ami_server ami_event_handler}.each do |f|
  File.copy "#{File.dirname(__FILE__)}/lib/#{f}", "#{File.dirname(__FILE__)}/../../../script/#{f}"
end