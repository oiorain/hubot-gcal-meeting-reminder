# Description
#   A robot script that reminds you of upcoming meeting
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#   hubot send me meeting reminders
#   hubot stop sending me meeting reminders
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
  #List of users we are waiting the authentification code from
  awaiting_code = []
  oauth2Client = false

  # retrieving settings from gcal-meeting-reminder.json
  try
    fs.readFile settings_file, (err, contents) ->
      if err
        throw err
        return
      settings = JSON.parse(contents)
      auth = new googleAuth
      oauth2Client = new (auth.OAuth2)(settings.web.client_id, settings.web.client_secret, settings.web.redirect_uris[0])
  catch e
    console.warn "Could not find or read #{settings_file} file: #{err}"


  #
  # Helper functions
  #
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

  #
  # Auth functions
  #
  getTokenPath = (user) ->
    token_dir + "#{user}-credentials.json"

  # Check if we have previously stored a token for user speaking
  authorize = (callback, args) ->
    fs.readFile getTokenPath(args.user), (err, token) ->
      if err
        console.log "no token found #{getTokenPath(args.user)}"
        authUrl = oauth2Client.generateAuthUrl
          access_type: 'offline'
          scope: [ 'https://www.googleapis.com/auth/calendar.readonly' ]

        awaiting_code.push(args.user)
        messageUser args.user, "Authorize this app by visiting this url: #{authUrl} then give me the code please :simple_smile:"

      else
        oauth2Client.credentials = JSON.parse(token)
        callback args

  storeToken = (token, token_path) ->
    try
      fs.mkdirSync token_dir
    catch err
      if err.code != 'EEXIST'
        throw err
    fs.writeFile token_path, JSON.stringify(token)
    console.log 'Token stored to ' + token_path

  #
  # talk functions
  #
  messageUser = (user, message) ->
    console.log "> @#{user}: #{message}"
    robot.emit 'slack.attachment',
      channel: user
      content: [{
        pretext: message
      }]

  confirmReminders = (args) ->
    user = args.user
    console.log "confirmReminders for #{user}: users list is #{users.toString().replace /,/, ", "}"

    if user not in users
      # Add user to perstisted list
      users.push user
      robot.brain.set('reminder_users', users)

      messageUser user, "Sure, #{user}. I'll send your meeting reminders from now on.\nYou can stop anytime by telling me \"stop sending me meeting reminders\"."

    else
      messageUser user, "Reminders are already enabled my dear #{user}. :simple_smile:"

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

  #
  # hubot events
  #
  robot.respond /(send me meeting reminders)/i, (msg) ->
    console.log "#{msg.message.user.name} to reminders wants reminders."
    authorize confirmReminders, { user: msg.message.user.name }

  robot.respond /(stop sending me meeting reminders)/i, (msg) ->
    users.splice(users.indexOf(msg.message.user.name), 1)
    robot.brain.set('reminder_users', users)
    msg.send "Alright, #{msg.message.user.name}. I won't send you reminders anymore."

  robot.respond /(Who's getting reminders\?)/i, (msg) ->
    if users.length
      msg.send "I'm currently sending reminders to #{users.toString().replace /,/, ", "}."
    else
      msg.send "I'm not currently sending reminders to anyone."

  # Wait for a auth code from user : codes start with 4\
  robot.respond /(4\/(.*))/i, (msg) ->
    user = msg.message.user.name
    if user in awaiting_code
      code = "#{msg.match[1]}"
      console.log "the code would be : #{code}"

      oauth2Client.getToken code, (err, token) ->
        if err
          console.log 'Error while trying to retrieve access token', err
          msg.send "Sorry I couldn't retrieve the token to give you access :sad:."
          return
        oauth2Client.credentials = token
        storeToken token, getTokenPath user

        msg.send "Thanks!"
        awaiting_code.splice(awaiting_code.indexOf(msg.message.user.name), 1)
    else
      msg.send "Sorry, I didn't get that.."

  # Log and send respond if there's an error
  robot.error (err, res) ->
    robot.logger.error "DOES NOT COMPUTE"
    if res?
      res.send "Arg! I'm affraid there was an error in my code T_T"

  #
  # automated check loop functions
  #
  findEventUpcomingEvents = (args) ->
    calendar_args =
      auth: oauth2Client
      calendarId: 'primary'
      timeMin: args.timeMin.toISOString()
      timeMax: args.timeMax.toISOString()
      maxResults: 10
      singleEvents: true
      orderBy: 'startTime'
      timeZone: "utc"

    google.calendar('v3').events.list calendar_args, (err, response) ->
      if err
        console.log "No events found for that time range.The API returned an error: #{JSON.stringify(err)}"
        if err.code == 400 # invalid_request
          console.log "Let's ask for a new token"
          authorize confirmReminders, { user: user }
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
          # if event.start.dateTime and event.attendees and low_diff == 0 and high_diff == 60 and event.status == "confirmed"
          if event.start.dateTime and event.attendees and low_diff <= 0 and high_diff >= 60 and event.status == "confirmed"
            console.log "#{JSON.stringify(event)}"
            sendReminder robot, args.user, event

  automate = ->
    console.log "-----------------------------"
    console.log "now is : #{(new Date()).toISOString()}. BTW, I'm awaiting auth code from #{awaiting_code.toString().replace /,/, ", "}"
    for user in users
      if user not in awaiting_code
        timeMin = nowPlusMinutes(remind_me)
        timeMax = nowPlusMinutes(remind_me+1)
        console.log "Looking at events for #{user} between #{timeMin.toISOString()} and #{timeMax.toISOString()}."
        authorize findEventUpcomingEvents, {user: user, timeMin: timeMin, timeMax, timeMax}
    return


  setTimeout automate, 1000
  setInterval automate, 60000 # every minute :
