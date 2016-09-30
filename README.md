# hubot-gcal-meeting-reminder

A hubot script that sends you reminders to Slack of the upcoming meetings you have on GoogleCalendar.


## Installation

In [hubot](https://hubot.github.com/) project folder, run:

```
npm install hubot-gcal-meeting-reminder --save
```

Then add **hubot-gcal-meeting-reminder** to your `external-scripts.json`:

```json
[
  "hubot-gcal-meeting-reminder"
]
```


We also use the [hubot-slack-google-auth](https://github.com/Skookum/hubot-slack-google-auth) to handle authentification to Google via Slack which requires a little bit of setup so be sure to add it to your hubot configuration:

```
npm install hubot-slack-google-auth --save
```


## Notes on using Heroku to run hubot

If you are running your hubot instance on Heroku, you might want to add the [hubot-redis-brain]() package to your hubot instance and enable the `Redis To Go` addon to Heroku ressources.

Heroku's instance is restarted automatically everyday or so and it will erase your memory each time, long with the list of users who enabled reminders. A bot with amnesia is only that useful...


## more info
See [`src/gcal-meeting-reminder.coffee`](src/gcal-meeting-reminder.coffee) for full documentation.
