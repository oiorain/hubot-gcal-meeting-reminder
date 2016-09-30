# hubot-gcal-meeting-reminder

A hubot script that sends you reminders to Slack of the upcoming meetings you have on GoogleCalendar.

## Use

This package adds 3 commands to hubot:

- `send me meeting reminders` :  the bot enable reminders for you

- `stop sending me meeting reminders` : the bot disable reminders for you

- `who's getting reminders?` : the bot informs you of the list of users who are currently getting reminders.

the commands are optimized to be used as direct message to your bot on Slack.

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

#### Auth
We rely the [hubot-slack-google-auth](https://github.com/Skookum/hubot-slack-google-auth) to handle authentification to Google via Slack. To install it:

```
npm install hubot-slack-google-auth --save
```
There's a couple of vars to setup on this plugin's side as explained in the 'Configuration' paragraph of their README.


## Notes on using Heroku to run hubot

If you are running your hubot instance on Heroku, you might want to add the [hubot-redis-brain]() package to your hubot instance and enable the `Redis To Go` addon to Heroku ressources.

Heroku's instance is restarted automatically everyday or so and it will erase your memory each time, long with the list of users who enabled reminders. A bot with amnesia is only that useful...


## more info
See [`src/gcal-meeting-reminder.coffee`](src/gcal-meeting-reminder.coffee) for full documentation.
