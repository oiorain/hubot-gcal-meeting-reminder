# Description
#   A robot script that reminds you of upcoming meeting
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#   Gcal Meeting Reminder - send me meeting reminders
#   Gcal Meeting Reminder - stop sending me meeting reminders
#   Gcal Meeting Reminder - Who's getting reminders?
#
# Notes:
#   <optional notes required for the script>
#
# Author:
#   Marion Kamoike-Bouguet <marion.bouguet@gmail.com>


# for local dev
# try
#   {Robot,Adapter,TextMessage,User} = require 'hubot'
# catch
#   prequire = require('parent-require')
#   {Robot,Adapter,TextMessage,User} = prequire 'hubot'

module.exports = (robot) ->
  fs = require 'fs'
  readline = require 'readline'
  google = require 'googleapis'
  googleAuth = require 'google-auth-library'

  # location where auth tokens and settings files are stored
  settings_file = process.cwd()+"/gcal-meeting-reminder.json"
  settings = {}

  # the number of minutes before an event the reminder happens
  remind_me = 3
  # users who have reminders enabled
  users = robot.brain.get('reminder_users') or []
  console.log "In my brain, I remember these users: #{users.toString().replace /,/, ", "}"
  #List of users we are waiting the authentification code from
  awaiting_code = []
  oauth2Client = false
  userAuth = []

  # retrieving settings from gcal-meeting-reminder.json
  try
    fs.readFile settings_file, (err, contents) ->
      if err
        throw err
        return
      settings = JSON.parse(contents)
      console.info "Found a config file (#{settings_file})"
      auth = new googleAuth
      oauth2Client = new (auth.OAuth2)(settings.web.client_id, settings.web.client_secret, settings.web.redirect_uris[0])
      console.log "oauth2Client: #{JSON.stringify(oauth2Client, null, 6)}"
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
  # talk methods
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
    if user not in users
      # Add user to perstisted list
      awaiting_code.splice(users.indexOf(user), 1)
      users.push user if user not in users
      robot.brain.set('reminder_users', users)
      messageUser user, "Alright, #{user}! I'll send your meeting reminders from now on.\nYou can stop anytime by telling me \"stop sending me meeting reminders\"."

    else
      messageUser user, "Reminders are already enabled my dear #{user}. :simple_smile:"

  sendReminder = (robot, user, event) ->
    attendees = ""
    ressources = ""
    for attendee in event.attendees
      attendees += "#{attendee.displayName}, " if !attendee.self and attendee.responseStatus != "declined"
      ressources += "#{attendee.displayName}, " if attendee.ressource
    text = ""
    if event.start.dateTime # no dateTime if event is all day long
      start = new Date(event.start.dateTime)
      end = new Date(event.end.dateTime)
      text = "#{start.getHours()}:#{("00" + start.getMinutes()).slice (-2)}-#{end.getHours()}:#{("00" + end.getMinutes()).slice (-2)}"
      text += "At #{ressources.slice(0, -2)}" if ressources
      text += "\n"
    text += "Invited by #{event.organizer.displayName}"
    text += "\n#{event.description}" if event.description
    text += "\n with #{attendees.slice(0, -2)}" if attendees

    console.log "event : #{JSON.stringify(event)}"
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
  robot.respond /(plop|send me meeting reminders)/i, (msg) ->
    awaiting_code.push msg.message.user.name if msg.message.user.name not in awaiting_code
    robot.emit 'google:authenticate', msg, (err, oauth) ->
      console.log "oauth for #{msg.message.user.name}: #{JSON.stringify(oauth, null, 3)}"
      userAuth[msg.message.user.name] = oauth
      console.log "Got an answer from google:authenticate : #{JSON.stringify(err, null, 3)} / oauth : #{JSON.stringify(oauth)}"
      confirmReminders { user: msg.message.user.name }

  robot.respond /(stop sending me meeting reminders)/i, (msg) ->
    console.info "-> robot.reponse /stop sending me meeting reminders/ from #{msg.message.user.name}";
    users.splice(users.indexOf(msg.message.user.name), 1)
    robot.brain.set('reminder_users', users)
    msg.send "Alright, #{msg.message.user.name}. I won't send you reminders anymore."

  robot.respond /(who's getting reminders\?)/i, (msg) ->
    console.info "-> robot.reponse /who's getting reminders\?/ from #{msg.message.user.name}";
    if users.length
      msg.send "I'm currently sending reminders to #{users.toString().replace /,/, ", "}."
    else
      msg.send "I'm not currently sending reminders to anyone. :disappointed:"

  # Log and send respond if there's an error
  robot.error (err, res) ->
    robot.logger.error "DOES NOT COMPUTE"
    res.send "Arg! I'm affraid there was an error in my code T_T" if res?

  #
  # automated check loop functions
  #
  findEventUpcomingEvents = (args) ->
    calendar_args =
      auth: userAuth[args.user]
      calendarId: 'primary'
      timeMin: args.timeMin.toISOString()
      timeMax: args.timeMax.toISOString()
      maxResults: 10
      singleEvents: true
      orderBy: 'startTime'
      timeZone: "utc"

    google.calendar('v3').events.list calendar_args, (err, response) ->
      if err
        console.log "No events found for that time range.The API returned an error: #{JSON.stringify(err, null, 3)}"
        awaiting_code.push args.user if args.user not in awaiting_code
        users.splice(users.indexOf(args.user), 1)
        if err.code == 401 # invalid credentials
          console.log "Token invalid. Asking the user to renew."
          robot.emit 'google:authenticate', msg, (err, oauth) ->
            console.log "google:authenticate: #{JSON.stringify(err, null, 3)}" if err
            userAuth[user] = oauth
            awaiting_code.splice(users.indexOf(user), 1)
            users.push user if user not in users
            robot.brain.set('reminder_users', users)
          # messageUser { user: args.user, "Oups... Looks like I lost your token :cry:. Please say 'plop' and i'll renew it for you." }
      events = response.items
      if events.length > 0
        for event in events
          # Event starts within 0 to 60 seconds of now + remind_me mins
          start = new Date(event.start.dateTime)
          low_diff = Math.floor((args.timeMin.getTime() - start.getTime())/1000)
          high_diff = Math.floor((args.timeMax.getTime() - start.getTime())/1000)

          # has startTime = event is not all day long
          # not creator.self = someone else created the event
          if event.start.dateTime and event.attendees and low_diff == 0 and high_diff == 60 and event.status == "confirmed"
            console.log "Notify: #{JSON.stringify(event)}"
            sendReminder robot, args.user, event

  automate = ->
    console.log "---- now is : #{(new Date()).toISOString()}. Waiting for auth code from #{awaiting_code.toString().replace /,/, ", "}"
    for user in users
      if user not in awaiting_code
        console.log "-- #{user}"
        timeMin = nowPlusMinutes(remind_me)
        timeMax = nowPlusMinutes(remind_me+1)
        findEventUpcomingEvents {user: user, timeMin: timeMin, timeMax: timeMax}
    return

  setTimeout automate, 1000
  setInterval automate, 60000 # every minute :
