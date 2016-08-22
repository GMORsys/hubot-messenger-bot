{Robot, Adapter, TextMessage} = require "hubot"

class Messenger extends Adapter
    constructor: (@robot) ->
        super @robot
        @verifyToken = process.env.MESSENGER_VERIFY_TOKEN
        @accessToken = process.env.MESSENGER_ACCESS_TOKEN
        @apiURL = "https://graph.facebook.com/v2.6"
        @robot.logger.info "hubot-messenger-bot: Adapter loaded."

    _subscribe: ->
        subscribeURL = "#{@apiURL}/me/subscribed_apps?access_token=#{@accessToken}"
        @robot.http(subscribeURL)
            .post() (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error subscribing app to page - #{body} #{httpRes.statusCode} (#{err})"
                @robot.logger.info "hubot-messenger-bot: Subscribed app to page.", body

    _createUser: (userId, roomId, cb) ->
        profileURL = "#{@apiURL}/#{userId}?fields=first_name,last_name&access_token=#{@accessToken}"
        @robot.http(profileURL)
            .get() (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error getting profile - #{body} #{httpRes.statusCode} (#{err})"
                _user = JSON.parse(body)
                _userName = "#{_user.first_name} #{_user.last_name}"
                cb @robot.brain.userForId(userId, name: _userName, room: roomId)

    _processMsg: (msg) ->
        return unless msg.message?.text?
        _sender = msg.sender.id
        _recipient = msg.recipient.id
        _mid = msg.message.mid
        _text = msg.message.text
        @_createUser _sender, _recipient, (user) =>
            message = new TextMessage user, _text.trim(), _mid
            @receive(message) if message?

    _sendMsg: (context, msg) ->
        data = JSON.stringify({
            recipient:
                id: context.user.id
            message: msg
        })
        console.log 'adapter message : ' + data
        @robot.http("#{@apiURL}/me/messages?access_token=#{@accessToken}")
            .header('Content-Type', 'application/json')
            .post(data) (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error sending message - #{body} #{httpRes.statusCode} (#{err})"

    send: (envelope, strings...) ->
        @_sendMsg envelope, strings[0]

    textMessage: (strings) ->
        text = strings.join "\n"
        message = {
            # Facebook Messenger Platform only allows up to 320 characters
            # Use a plugin like https://github.com/ClaudeBot/hubot-longtext
            # to handle long messages...
            text: text.substring(0, 320)
        }
        message

    postbackButtonMessage: (strings, buttons...) ->
        buttonMessages = []
        for button in buttons
            buttonMessage = {
                "type": "postback",
                "title": button.title,
                "payload": button.payload
            }

            buttonMessages.push buttonMessage

        message = {
            "attachment": {
                "type": "template",
                "payload": {
                    "template_type": "button",
                    "test": strings,
                    "buttons": buttonMessages
                }
            }
        }
        message

    imageMessage: (url) ->
        message = {
            "attachment": {
                "type":"image",
                "payload": {
                    "url": url
                }
            }
        }
        message

    videmMessage: (url) ->
        message = {
            "attachment": {
                "type":"video",
                "payload": {
                    "url": url
                }
            }
        }
        message

    reply: (envelope, strings...) ->
        @_sendMsg envelope, envelope.user.name + ": " + strings.join "\n #{envelope.user.name}: "

    run: ->
        unless @verifyToken
            @emit "error", new Error "You must configure the MESSENGER_VERIFY_TOKEN environment variable."
        unless @accessToken
            @emit "error", new Error "You must configure the MESSENGER_ACCESS_TOKEN environment variable."

        @robot.router.get "/webhook/", (req, res) =>
            if req.query["hub.verify_token"] is @verifyToken
              res.send req.query["hub.challenge"]
              # @_subscribe()
              return
            @robot.logger.warning "hubot-messenger-bot: Wrong validation token."
            res.send "Error, wrong validation token"

        @robot.router.post "/webhook/", (req, res) =>
            msgEvents = req.body.entry[0].messaging
            for msgEvent in msgEvents
                @_processMsg msgEvent

            res.send 200

        @robot.logger.info "hubot-messenger-bot: Adapter running."
        @emit "connected"

exports.use = (robot) ->
    new Messenger robot
