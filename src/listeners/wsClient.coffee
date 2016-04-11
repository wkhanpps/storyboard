socketio    = require 'socket.io-client'
timm        = require 'timm'
_           = require '../vendor/lodash'
k           = require '../gral/constants'
ifExtension = require './interfaceExtension'
serializeAttachments = require './serializeAttachments'

DEFAULT_CONFIG = 
  uploadClientStories: false

#-------------------------------------------------
# ## Extension I/O
#-------------------------------------------------
_extensionRxMsg = (msg) ->
  {type, data} = msg
  if type is 'CONNECT_REQUEST'
    rspType = if _fSocketConnected then 'WS_CONNECTED' else 'WS_DISCONNECTED'
    ifExtension.tx {type: rspType}
  if not((type is 'CONNECT_REQUEST') or (type is 'CONNECT_RESPONSE'))
    _txMsg {type, data}
  return

#-------------------------------------------------
# ## Websocket I/O
#-------------------------------------------------
_socketio = null
_fSocketConnected = false
_socketInit = (config) ->
  if not _socketio
    url = k.WS_NAMESPACE
    if process.env.TEST_BROWSER 
      url = "http://localhost:8090#{k.WS_NAMESPACE}"
    _socketio = socketio.connect url
    socketConnected = ->
      ifExtension.tx {type: 'WS_CONNECTED'}
      _fSocketConnected = true
    socketDisconnected = ->
      ifExtension.tx {type: 'WS_DISCONNECTED'}
      _fSocketConnected = false
    _socketio.on 'connect', socketConnected
    _socketio.on 'reconnect', socketConnected
    _socketio.on 'disconnect', socketDisconnected
    _socketio.on 'error', socketDisconnected
    _socketio.on 'MSG', _rxMsg
  _socketio.sbConfig = config

_rxMsg = (msg) -> ifExtension.tx msg
_txMsg = (msg) ->
  ### istanbul ignore if ###
  if not _socketio
    console.error "Cannot send '#{msg.type}' message to server: socket unavailable"
    return
  _socketio.emit 'MSG', msg

_uploadBuf = []
_uploadPending = ->
  return if not _fSocketConnected
  _txMsg {type: 'UPLOAD_RECORDS', data: [].concat(_uploadBuf)}
  _uploadBuf.length = 0

_uploadRecord = (record, config) ->
  return if not config.uploadClientStories
  record = serializeAttachments record
  record = timm.set record, 'fUploaded', true
  if _uploadBuf.length < 2000
    _uploadBuf.push record
  _uploadPending()

#-------------------------------------------------
# ## API
#-------------------------------------------------
create = (baseConfig) ->
  config = timm.addDefaults baseConfig, DEFAULT_CONFIG
  listener =
    type: 'WS_CLIENT'
    init: -> 
      _socketInit config
      ifExtension.rx _extensionRxMsg
    process: (record) -> _uploadRecord record, config
    config: (newConfig) -> _.extend config, newConfig
  listener

module.exports = {
  create,
}
