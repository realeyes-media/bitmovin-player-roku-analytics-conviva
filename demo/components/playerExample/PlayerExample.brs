sub init()
  m.playerConfig = getExamplePlayerConfig()

  ' Creates the ComponentLibrary (the BitmovinPlayerSDK in this case)
  m.bitmovinPlayerSDK = CreateObject("roSGNode", "ComponentLibrary")
  m.bitmovinPlayerSDK.id = "BitmovinPlayerSDK"
  m.bitmovinPlayerSDK.uri = "https://cdn.bitmovin.com/player/roku/1.7.0-b.1/bitmovinplayer.zip"

  ' Adding the ComponentLibrary node to the scene will start the download of the library
  m.top.appendChild(m.bitmovinPlayerSDK)
  m.bitmovinPlayerSDK.observeField("loadStatus", "onLoadStatusChanged")
end sub

' The ComponentLibrary loadStatus field can equal "none", "ready", "loading" or "failed"
sub onLoadStatusChanged()
  print "LOAD STATUS FOR BITMOVINPLAYER LIBRARY: "; m.bitmovinPlayerSDK.loadStatus

  if (m.bitmovinPlayerSDK.loadStatus = "ready")
    ' Once the library is loaded and ready, we can use it to reference the BitmovinPlayer
    m.bitmovinPlayer = CreateObject("roSGNode", "BitmovinPlayerSDK:BitmovinPlayer")
    m.top.appendChild(m.bitmovinPlayer)
    m.BitmovinFunctions = m.bitmovinPlayer.BitmovinFunctions
    m.BitmovinFields = m.bitmovinPlayer.BitmovinFields
    m.bitmovinPlayer.ObserveField(m.BitmovinFields.ERROR, "catchVideoError")
    m.bitmovinPlayer.ObserveField(m.BitmovinFields.WARNING, "catchVideoWarning")
    m.bitmovinPlayer.ObserveField(m.BitmovinFields.SEEK, "onSeek")
    m.bitmovinPlayer.ObserveField(m.BitmovinFields.SEEKED, "onSeeked")

    m.convivaAnalytics = CreateObject("roSGNode", "ConvivaAnalytics")
    player = m.bitmovinPlayer
    customerKey = "61a16fe47d5345ac124fee77eb07a2ed1a5b82ab"
    config = {
      debuggingEnabled : true,
      gatewayUrl : "https://nbcsports-test.testonly.conviva.com" ' TOUCHSTONE_SERVICE_URL for testing
    }
    m.convivaAnalytics.callFunc("setup", player, customerKey, config)
    contentMetadataOverrides = {
      playerName: "Conviva Integration Test Channel",
      viewerId: "MyAwesomeViewerId",
      tags: {
        CustomKey: "CustomValue"
      }
    }
    m.convivaAnalytics.callFunc("updateContentMetadata", contentMetadataOverrides)

    m.bitmovinPlayer.callFunc(m.BitmovinFunctions.SETUP, m.playerConfig)

  end if
end sub

sub catchVideoError()
  print "ERROR: "; m.bitmovinPlayer.error.code.toStr() + ": " + m.bitmovinPlayer.error.message
end sub

sub catchVideoWarning()
  print "WARNING: "; m.bitmovinPlayer.warning.code.toStr() + ": " + m.bitmovinPlayer.warning.message
end sub

sub onSeek()
  print "SEEKING"
end sub

sub onSeeked()
  print "SEEKED: "; m.bitmovinPlayer.seeked
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
  handled = false
  print "##### key received!"
  if press AND (key = "down" OR key = "up" )
    handled = true
    if key = "up"
      m.playerConfig = getExamplePlayerConfig2()
    else 
      m.playerConfig = getExamplePlayerConfig()
    end if
    ' m.bitmovinPlayer.callFunc(m.BitmovinFunctions.SETUP, m.playerConfig)
    m.bitmovinPlayer.callFunc(m.BitmovinFunctions.LOAD, m.playerConfig.source)
    contentMetadataOverrides = {
      playerName: "Conviva Integration Test Channel",
      viewerId: "MyAwesomeViewerId" + key,
      tags: {
        CustomKey: "CustomValue",
        KeyPress: key
      }
    }
    m.convivaAnalytics.callFunc("updateContentMetadata", contentMetadataOverrides)
  end if
  return handled
end function