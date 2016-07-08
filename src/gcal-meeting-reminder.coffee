# Description
#   A robot script that reminds you of upcoming meeting
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#   hubot please send me meeting reminders
#   hubot please stop sending me meeting reminders
#   hubot remind me <minutes> before meeting
#   hubot Who's getting reminders?
#
# Notes:
#   <optional notes required for the script>
#
# Author:
#   Marion Bouguet <marion.bouguet@gmail.com>


# for local dev
try
  {Robot,Adapter,TextMessage,User} = require 'hubot'
catch
  prequire = require('parent-require')
  {Robot,Adapter,TextMessage,User} = prequire 'hubot'

module.exports = (robot) ->
  fs = require 'fs'
  readline = require 'readline'
  google = require 'googleapis'
  googleAuth = require 'google-auth-library'

  # location where auth tokens and settings files are stored
  token_dir = (process.env.HOME or process.env.HOMEPATH or process.env.USERPROFILE) + '/.gcal-meeting-reminder/'
  settings_file = process.cwd()+"/gcal-meeting-reminder.json"
  settings = {}

  # the number of minutes before an event the reminder happens
  remind_me = 3
  # users who have reminders enabled
  users = robot.brain.get('reminder_users') or []

  # # just for faster dev
  # msg =
  #   message:
  #     user:
  #       name: "marion"
  users = robot.brain.get('reminder_users') or ['marion']

  # retrieving settings from gcal-meeting-reminder.json
  try
    fs.readFile settings_file, (err, contents) ->
      if err
        throw err
        return
      settings = JSON.parse(contents)
  catch e
    console.warn "Could not find or read #{settings_file} file: #{err}"

  authorize = (callback, args) ->
    console.log "authorize :"
    auth = new googleAuth
    oauth2Client = new (auth.OAuth2)(settings.web.client_id, settings.web.client_secret, settings.web.redirect_uris[0])
    # Check if we have previously stored a token for user speaking
    token_path = token_dir + "#{args.user}-credentials.json"
    console.log token_path
    fs.readFile token_path, (err, token) ->
      if err
        console.log "no token found"
        getNewToken oauth2Client, callback, args, token_path
      else
        console.log "no error : getting credentials"
        oauth2Client.credentials = JSON.parse(token)
        console.log "calling callback"
        callback args, oauth2Client
      return
    return

  getNewToken = (oauth2Client, callback, args, token_path) ->
    console.log "get new token"
    authUrl = oauth2Client.generateAuthUrl(
      access_type: 'offline'
      scope: [ 'https://www.googleapis.com/auth/calendar.readonly' ])
    robot.emit 'slack.attachment',
      channel: args.user
      text: "Authorize this app by visiting this url: #{authUrl}"
      # attachments: attachments

    robot.emit 'slack.attachment',
      channel: args.user
      text: "then give the code to Marion :simple_smile:"
      # attachments: attachments
    rl = readline.createInterface(input: process.stdin, output: process.stdout)
    rl.question 'Enter the code from that page here: ', (code) ->
      rl.close()
      oauth2Client.getToken code, (err, token) ->
        if err
          console.log 'Error while trying to retrieve access token', err
          messageUser args.user, "Sorry I couldn't retrieve the token to give you access :sad:."
          return
        oauth2Client.credentials = token
        storeToken token, token_path
        console.log "callback"
        callback args, oauth2Client
        return
      return
    return

  storeToken = (token, token_path) ->
    try
      fs.mkdirSync token_dir
    catch err
      if err.code != 'EEXIST'
        throw err
    fs.writeFile token_path, JSON.stringify(token)
    console.log 'Token stored to ' + token_path
    return

  nowPlusMinutes = (mins) ->
    now = new Date
    now.setMinutes now.getMinutes() + mins
    now.setSeconds 0
    now

  randomReaction =  ->
    reaction = [
      ":simple_smile:"
      ":muscle:"
      ":muscle: :simple_smile:"
      ":slightly_smiling_face:"
      ":wave:"
      ":rabbit:"
      ":cat2:"
      ":coffee:"
    ]
    reaction[Math.floor(Math.random() * (reaction.length))]

  confirmReminders = (args) ->
    user = args.user
    msg = args.msg
    if user not in users
      users.push user
      robot.brain.set('reminder_users', users)
      msg.send "Sure, "+msg.message.user.name+". I'll send your meeting reminders from now on."
      msg.send "You can stop anytime by telling me \"please stop sending me meeting reminders\"."
    else
      msg.send "Reminders are already enabled my dear #{msg.message.user.name}. :simple_smile:"

  sendReminder = (robot, user, event) ->
    text = ""
    if event.start.dateTime # no dateTime if event is all day long
      start = new Date(event.start.dateTime)
      end = new Date(event.end.dateTime)
      text = "#{start.getHours()}:#{("00" + start.getMinutes()).slice (-2)}-#{end.getHours()}:#{("00" + end.getMinutes()).slice (-2)}\n"
    text += "Invited by #{event.organizer.displayName}"
    text += "\n#{event.description}" if event.description

    console.log "event"+JSON.stringify(event)
    robot.emit 'slack.attachment',
      channel: user
      content: [{
        pretext: "Ready? #{randomReaction()}"
        fallback: "Ready for #{event.summary} in #{remind_me}minutes? :simple_smile:"
        color: "#439FE0"
        mrkdwn_in: ["text", "pretext", "fields"]
        title: event.summary
        title_link: event.hangoutLink
        text: text
      }]

  messageUser = (user, message) ->
    robot.emit 'slack.attachment',
      channel: user
      pretext: message

#
# hubot interactions
#
  robot.respond /(please send me meeting reminders)/i, (msg) ->
    # for dev
    authorize confirmReminders, { user: msg.message.user.name, msg: msg }
    # for prod
    # robot.emit 'google:authenticate', msg, (err, oauth) ->
    #   confirmReminders msg

  robot.respond /(please stop sending me meeting reminders)/i, (msg) ->
    users.splice(users.indexOf(msg.message.user.name), 1)
    robot.brain.set('reminder_users', users)
    msg.send "Alright, #{msg.message.user.name}. I won't send you reminders anymore."

  robot.respond /(Who's getting reminders\?)/i, (msg) ->
    if users.length
      msg.send "I'm currently sending reminders to #{users.toString().replace /,/, ", "}."
    else
      msg.send "I'm not currently sending reminders to anyone."

  findEventUpcomingEvents = (args, oauth2Client) ->
    calendar = google.calendar('v3')
    calendar_args =
      auth: oauth2Client
      calendarId: 'primary'
      timeMin: args.timeMin.toISOString()
      timeMax: args.timeMax.toISOString()
      maxResults: 10
      singleEvents: true
      orderBy: 'startTime'
      timeZone: "utc"

    calendar.events.list calendar_args, (err, response) ->
      if err
        console.log "No events found for that time range.The API returned an error: #{JSON.stringify(err)}"
        if err.code == 400 # invalid_request
          console.log "Let's ask for a new token"
          token_path = token_dir + "#{args.user}-credentials.json"
          getNewToken oauth2Client, (->), msg, token_path
        return
      events = response.items
      if events.length > 0
        for event in events
          # Event starts within 0 to 60 seconds of now + remind_me mins
          start = new Date(event.start.dateTime)
          low_diff = Math.floor((args.timeMin.getTime() - start.getTime())/1000)
          high_diff = Math.floor((args.timeMax.getTime() - start.getTime())/1000)

          console.log "----------------------------------------------"
          console.log "#{event.start.dateTime} - #{event.summary} // #{low_diff} : #{high_diff}"

          # has startTime = event is not all day long
          # not creator.self = someone else created the event
          # if event.start.dateTime and not event.creator.self and low_diff == 0 and high_diff == 60 and event.status == "confirmed"
          if event.start.dateTime and not event.creator.self and low_diff <= 0 and high_diff >= 60 and event.status == "confirmed"
            console.log "#{JSON.stringify(event)}"
            console.log "remind about event."
            sendReminder robot, args.user, event

  automate = ->
    console.log "-----------------------------"
    for user in users
      timeMin = nowPlusMinutes(remind_me)
      timeMax = nowPlusMinutes(remind_me+30) # should be 1
      console.log "Looking at events for #{user} between #{timeMin.toISOString()} and #{timeMax.toISOString()}."

      authorize findEventUpcomingEvents, {user: user, timeMin: timeMin, timeMax, timeMax}
    return


  # for dev
  setTimeout (
    console.log "=================="
    automate
  ), 1000

  setInterval (
    console.log "=================="
    console.log "now is : #{(new Date()).toISOString()}"
    automate
  ), 60000 # every minute :
