# Description
#   A robot script that reminds you of upcoming meeting
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#   Gcal Meeting Reminder - send me meeting reminders
#   Gcal Meeting Reminder - stop sending me meeting reminders
#   Gcal Meeting Reminder - who's getting reminders?
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

  # the number of minutes before an event the reminder happens
  remind_me = 3
  # list of users asking for reminders
  usersFile = process.cwd()+"/gcal-meeting-reminder.json"
  users = []

  # arguments for Google Calendar query
  calendar_args =
    auth: null
    calendarId: 'primary'
    timeMin: null
    timeMax: null
    maxResults: 10
    singleEvents: true
    orderBy: 'startTime'
    timeZone: "utc"

  #
  # Setting functions
  #

  getUserListFromFile = ->
    try
      fs.readFile usersFile, (err, contents) ->
        throw err if err
        users = JSON.parse(contents)
        console.log "Found those user saved neatly: #{users.toString().replace /,/, ", "}"
    catch err
      console.log "couldnt retrieve user list from #{usersFile} file: #{err}"

  setUserListToFile = ->
    try
      fs.writeFile usersFile, users, { flag: 'wx' }, (err) ->
        throw err if err
    catch err
      console.log "couldnt write user list from the token file #{usersFile} file: #{err}"

  # Add/remove user to reminder list
  AddUserToReminderList = (user) ->
    users.push user if user not in users
    setUserListToFile()
  removeUserFromReminderList = (user) ->
    users.splice(users.indexOf(user), 1)
    setUserListToFile()

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
  confirmReminders = (args) ->
    user = args.user
    if user not in users
      console.log " Has my user list been saved properly ? #{users.toString()}"
      messageUser user, "Alright, #{user}! I'll send your meeting reminders from now on.\nYou can stop anytime by telling me \"stop sending me meeting reminders\"."
    else
      messageUser user, "Reminders are already enabled my dear #{user}. :simple_smile:"

  messageUser = (user, message) ->
    console.log "> @#{user}: #{message}"
    robot.emit 'slack.attachment',
      channel: user
      content: [{
        pretext: message
      }]

  sendReminder = (robot, user, event) ->
    console.log "event : #{JSON.stringify(event)}"
    text = ""
    attendees = ""
    for att in event.attendees
      if !att.self and att.responseStatus != "declined" and !att.resource
        attendees += "#{att.displayName}, " if att.displayName
        attendees += "#{att.email}, " if not att.displayName
    if event.start.dateTime # no dateTime if event is all day long
      start = new Date(event.start.dateTime)
      end = new Date(event.end.dateTime)
      text = "#{start.getHours()}:#{("00" + start.getMinutes()).slice (-2)}-#{end.getHours()}:#{("00" + end.getMinutes()).slice (-2)}"
      text += " At #{event.location}" if event.location
      text += "\n"
    text += "Invited by #{event.organizer.displayName}"
    text += "\n#{event.description}" if event.description
    text += "\n with #{attendees.slice(0, -2)}" if attendees
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
    robot.emit 'google:authenticate', msg, (err, oauth) ->
      console.error "google:authenticate returned #{JSON.stringify(err)}" if err?
      AddUserToReminderList user
      confirmReminders { user: msg.message.user.name }

  robot.respond /(stop sending me meeting reminders)/i, (msg) ->
    console.info "-> robot.reponse /stop sending me meeting reminders/ from #{msg.message.user.name}"
    removeUserFromReminderList msg.message.user.name
    msg.send "Alright, #{msg.message.user.name}. I won't send you reminders anymore."

  robot.respond /(who's getting reminders\?)/i, (msg) ->
    console.info "-> robot.reponse /who's getting reminders\?/ from #{msg.message.user.name}"
    if users.length
      msg.send "I'm currently sending reminders to #{users.toString().replace /,/, ", "}."
    else
      msg.send "I'm not currently sending reminders to anyone. :disappointed:"

  # Log and send respond if there's an error
  robot.error (err, res) ->
    robot.logger.error "Found an error >_< : #{JSON.stringify(err)}"
    res.send "Arg! I'm affraid there was an error in my code T_T" if res?

  #
  # automated check loop functions
  #

  # Send reminder if :
  # Event starts within 0 to 60 seconds of now + remind_me mins
  # has startTime = event is not all day long
  # not creator.self = someone else created the event
  CheckWetherEventsNeedReminderNow = (events, user)->
    for e in events
      start = new Date(e.start.dateTime)
      low_diff = Math.floor((calendar_args.timeMin.getTime() - start.getTime())/1000)
      high_diff = Math.floor((calendar_args.timeMax.getTime() - start.getTime())/1000)

      if e.start.dateTime and e.attendees and low_diff == 0 and high_diff == 60 and e.status == "confirmed"
        console.log "Notify: #{JSON.stringify(e)}"
        sendReminder robot, user, e

  findEventUpcomingEvents = (user) ->
    # reconstituing this for hubot-slack-google-auth
    msg =
      message:
        user:
          name: user

    robot.emit 'google:authenticate', msg, (err, oauth) ->
      console.log "google:authenticate error: #{JSON.stringify(err)}" if err
      calendar_args.auth = oauth

      google.calendar('v3').events.list calendar_args, (err, response) ->
        if err
          console.log "Query to API returned #{JSON.stringify(err)}"
          if err.code == 500
            messageUser user, "Looks like there's a problem with Google Calendar right now :shy:. I wasnt able to read your events."

          else if err.code == 401 # invalid credentials
            removeUserFromReminderList user
            messageUser user, "Oups... Looks like I lost your token and I didn't succeed in getting a replacement :cry:. Please say 'plop' and i'll renew it for you."
          return

        if response.items and response.items.length > 0
          CheckWetherEventsNeedReminderNow response.items, user

  automate = ->
    console.log "---- #{(new Date()).toISOString()}. users: #{users.toString().replace /,/, ', '}"
    if users.length > 0
      for user in users
        console.log "-- #{user}"
        calendar_args.timeMin = nowPlusMinutes(remind_me)
        calendar_args.timeMax = nowPlusMinutes(remind_me+1)
        findEventUpcomingEvents user

  getUserListFromFile()
  setTimeout automate, 3000
  setInterval automate, 60000 # every minute :
