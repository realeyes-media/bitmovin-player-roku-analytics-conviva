sub init()
  m.top.functionName = "internalInit"
  m.port = CreateObject("roMessagePort")
  m.LivePass = invalid
  m.cSession = invalid
  m.DEBUG = false
  m.video = invalid
  m.PodIndex = 0
  m.adTracking = invalid
  m.adTrackingMode = 0

  m.contentMetadataBuilder = CreateObject("roSGNode", "ContentMetadataBuilder")

  ' Workaround for wrong event order of the bitmovinPlayerSDK
  ' In case of an error the resulting SourceUnloaded event is fired before the actual Error event.
  ' This leads to a clean session closing instead of an error. To work around this we delay the onSourceUnloaded event
  ' by 100 ms
  m.sourceUnloadedTimer = invalid
end sub

sub internalInit()
  debugLog("[ConvivaAnalytics] setting up")

  m.video = m.top.player.findNode("MainVideo")
  m.DEBUG = m.top.config.debuggingEnabled

  apiKey = m.top.customerKey
  if m.top.config.gatewayUrl <> invalid
    cfg = {}
    cfg.gatewayUrl = m.top.config.gatewayUrl
    m.LivePass = ConvivaLivePassInitWithSettings(apiKey, cfg)
  else
    m.LivePass = ConvivaLivePassInitWithSettings(apiKey)
  end if

  m.adTrackingMode = m.top.config.adTrackingMode
  if m.adTrackingMode > m.top.adTrackingModes.BASIC
    m.adTracking = initAdTracking(m.top.player, m.livePass)
  end if

  registerEvents()
  monitorVideo()
end sub

sub sendCustomApplicationEvent(eventName, attributes)
  m.livePass.sendEvent(eventName, attributes)
end sub

sub sendCustomPlaybackEvent(eventName, attributes)
  if not isSessionActive()
    debugLog("Cannot send playback event, no active monitoring session")
    return
  end if

  m.livePass.sendSessionEvent(m.cSession, eventName, attributes)
end sub

sub updateContentMetadata(metadataOverrides)
  m.contentMetadataBuilder.callFunc("setOverrides", metadataOverrides)

  if isSessionActive()
    buildContentMetadata()
    updateSession()
  end if
end sub

sub monitorVideo()
  debugLog("[ConvivaAnalytics] start video element monitoring")
  while true
    msg = ConvivaWait(0, m.port, invalid)
    if type(msg) = "roSGNodeEvent"
      field = msg.getField()
      data = msg.getData()
      if field = m.top.player.BitmovinFields.SEEK
        onSeek()
      else if field = m.top.player.BitmovinFields.PLAY
        onPlay()
      else if field = m.top.player.BitmovinFields.SOURCE_LOADED
        onSourceLoaded()
      else if field = m.top.player.BitmovinFields.SOURCE_UNLOADED
        onSourceUnloaded()
      else if field = "state"
        onStateChanged(data)
      else if field = "invoke"
        invoke(data)
      else if field = m.top.player.BitmovinFields.AD_BREAK_STARTED
        onAdBreakStarted()
      else if field = m.top.player.BitmovinFields.AD_BREAK_FINISHED
        onAdBreakFinished()
      else if field = "adError"
        onAdError()
      else if field = m.top.player.BitmovinFields.AD_SKIPPED
        onAdSkipped()
      end if
    end if

    if m.sourceUnloadedTimer <> invalid and m.sourceUnloadedTimer.TotalMilliseconds() > 100
      m.sourceUnloadedTimer = invalid
      endSession()
    end if
  end while
end sub

' We need to use observeField for all external calls into this task.
' For more information see #registerExternalManagingEvents
sub invoke(data)
  debugLog("[ConvivaAnalytics] invoke external: " + data.method)

  if data.method = "updateContentMetadata"
    updateContentMetadata(data.contentMetadata)
  else if data.method = "endSession"
    endSession()
  else if data.method = "reportPlaybackDeficiency"
    reportPlaybackDeficiency(data.message, data.isFatal, data.endSession)
  else if data.method = "sendCustomApplicationEvent"
    sendCustomApplicationEvent(data.eventName, data.attributes)
  else if data.method = "sendCustomPlaybackEvent"
    sendCustomPlaybackEvent(data.eventName, data.attributes)
  end if
end sub

sub onStateChanged(state)
  debugLog("[ConvivaAnalytics] state changed: " + state)
  if state = "finished"
    onPlaybackFinished()
  else if state = "stopped"
    endSession()
  end if
  ' Other states are handled by conviva
end sub

sub onPlaybackFinished()
  endSession()
end sub

sub onPlay()
  debugLog("[Player Event] onPlay")
  if not isSessionActive()
    createConvivaSession()
  end if 
end sub

sub onPlaying()
  debugLog("[Player Event] onPlaying")
  m.contentMetadataBuilder.callFunc("setPlaybackStarted", true)
end sub

sub onSeek()
  debugLog("[Player Event] onSeek")

  m.LivePass.setPlayerSeekStart(m.cSession, -1)
end sub

sub onSourceLoaded()
  debugLog("[Player Event] onSourceLoaded!")
  ' On source swap, onSourceUnloaded gets called, then onSourceLoaded gets called. But onSourceUnloaded
  ' has a 100ms delay that makes it close the session after onSourceLoaded. That is for cases of errors
  ' but for source swaps, we need to skip that delay, so we kill that timer
  if m.sourceUnloadedTimer <> invalid and isSessionActive()
    m.sourceUnloadedTimer = invalid
    endSession()
  end if 
end sub

sub onSourceUnloaded()
  debugLog("[Player Event] onSourceUnloaded")
  if not isSessionActive() then return

  m.sourceUnloadedTimer = CreateObject("roTimespan")
  m.sourceUnloadedTimer.mark() ' start the timer

end sub

function onAdBreakStarted()
  m.livePass.detachStreamer()
  m.livePass.adStart()

  if m.adTrackingMode > m.top.adTrackingModes.BASIC then m.adTracking.onAdBreakStarted()
end function

function onAdBreakFinished()
  m.LivePass.adEnd()
  m.LivePass.attachStreamer()

  if m.adTrackingMode > m.top.adTrackingModes.BASIC then m.adTracking.onAdBreakFinished()
end function

sub onAdError()
  sendCustomPlaybackEvent("adError", invalid)
  onAdFinished()
end sub

sub onAdSkipped()
  sendCustomPlaybackEvent("adSkipped", invalid)
  onAdFinished()
end sub

sub createConvivaSession()
  notificationPeriod = m.video.notificationinterval
  buildContentMetadata()
  m.cSession = m.LivePass.createSession(true, m.contentMetadataBuilder.callFunc("build"), notificationPeriod, m.video)
  m.PodIndex = 0
  if m.adTracking <> invalid then m.adTracking.updateSession(m.cSession)
  debugLog("[ConvivaAnalytics] start session")
end sub

sub endSession()
  debugLog("[ConvivaAnalytics] closing session")
  m.livePass.cleanupSession(m.cSession)
  m.cSession = invalid

  m.contentMetadataBuilder.callFunc("reset")
end sub

sub reportPlaybackDeficiency(message, isFatal, closeSession = true)
  if not isSessionActive() then return

  debugLog("[ConvivaAnalytics] reporting deficiency")

  m.livePass.reportError(m.cSession, message, isFatal)

  if closeSession
    endSession()
  end if
end sub

function isSessionActive()
  return m.cSession <> invalid
end function

sub buildContentMetadata()
  m.contentMetadataBuilder.callFunc("setDuration", m.video.duration)
  m.contentMetadataBuilder.callFunc("setStreamType", m.top.player.callFunc("isLive"))

  internalCustomTags = {
    "integrationVersion": "1.0.0"
  }

  config = m.top.player.callFunc("getConfig")
  if config.playback <> invalid and config.playback.autoplay <> invalid
    internalCustomTags.autoplay = ToString(config.playback.autoplay)
  end if

  if config.adaptation <> invalid and config.adaptation.preload <> invalid
    internalCustomTags.preload = ToString(config.adaptation.preload)
  end if

  m.contentMetadataBuilder.callFunc("setCustom", internalCustomTags)

  source = config.source
  if source <> invalid
    buildSourceRelatedMetadata(source)
  end if

end sub

sub buildSourceRelatedMetadata(source)
  if source.title <> invalid
    m.contentMetadataBuilder.callFunc("setAssetName", source.title)
  else
    m.contentMetadataBuilder.callFunc("setAssetName", "Untitled (no source.title set)")
  end if

  m.contentMetadataBuilder.callFunc("setViewerId", m.contentMetadataBuilder.callFunc("getViewerId"))
  m.contentMetadataBuilder.callFunc("setStreamUrl", m.video.content.url)
end sub

sub updateSession()
  if not isSessionActive() then return

  m.LivePass.updateContentMetadata(m.cSession, m.contentMetadataBuilder.callFunc("build"))
end sub

sub registerEvents()
  registerPlayerEvents()
  registerExternalManagingEvents()
  registerConvivaEvents()
  registerAdEvents()
end sub

sub registerPlayerEvents()
  ' Passing everything to m.port so that conviva can intercept and track them
  m.top.player.observeField(m.top.player.BitmovinFields.SEEK, m.port)
  m.top.player.observeField(m.top.player.BitmovinFields.PLAY, m.port)
  m.top.player.observeField(m.top.player.BitmovinFields.SOURCE_LOADED, m.port)
  m.top.player.observeField(m.top.player.BitmovinFields.SOURCE_UNLOADED, m.port)

  ' In case of autoplay we miss the inital play callback.
  ' See #registerExternalManagingEvents for more details.
  ' This does not affect VST.
  if m.top.player[m.top.player.BitmovinFields.PLAY] = true
    onPlay()
  end if
end sub

sub registerExternalManagingEvents()
  ' Since we are in a task, we can't use callFunc to invoke public functions.
  ' Instead we need to use observeField to communicate with the task.
  m.top.observeField("invoke", m.port)

  ' We have a race condition when some external methods are called right after initializing the ConvivaAnalytics, such
  ' as updateContentMetadata right after initializing.
  ' In this case we need to check if we missed a invoke and call it.
  ' Possible Issue: If there are more than one we only able to track the last one as it will be overridden.
  if m.top.invoke <> invalid
    invoke(m.top.invoke)
  end if
end sub

sub registerConvivaEvents()
  ' Auto collected by conviva within ConvivaWait.
  m.video.observeField("streamInfo", m.port)
  m.video.observeField("state", m.port)
  m.video.observeField("position", m.port)
  m.video.observeField("duration", m.port)
  m.video.observeField("streamingSegment", m.port)
  m.video.observeField("errorCode", m.port)
  m.video.observeField("errorMsg", m.port)
  m.video.observeField("downloadedSegment", m.port)
end sub

sub registerAdEvents()
  m.top.player.observeField("adBreakStarted", m.port)
  m.top.player.observeField("adBreakFinished", m.port)
  m.top.player.observeField("adError", m.port)
  m.top.player.observeField("adSkipped", m.port)
end sub

sub debugLog(message as String)
  if m.DEBUG then ?message
end sub

function getAd(mediaId)
  adBreaks = m.top.player.callFunc(m.top.player.BitmovinFunctions.AD_LIST)
  for each adBreak in adBreaks
    for each ad in adBreak.ads
      if ad.id = mediaId then return ad
    end for
  end for

  return invalid
end function
