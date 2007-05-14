class AmiLogic < RAI::AMIHandler
  # The following are commonly used AMI Events
  # This is not a complete list
  
  def peer_status
    # Called when registration state of peer changes.
    # Params are :peer, :peer_status
    # Peer status can be values such as: Registered, Unregistered, Reachable, Unreachable
  end  
  
  def link
   # Occurs when two channels are connected.
   # Available params are :channel1, :channel2
  end
  
  def unlink
    # Occurs when two channels are disconnected.
    # Available params are: :channel1, :channel2
  end
end