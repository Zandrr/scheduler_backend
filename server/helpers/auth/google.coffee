googleapis  = require 'googleapis'
config      = require 'config'
User        = require '../../models/user'

oauth2 = googleapis.oauth2('v2')
calendar = googleapis.calendar('v3')

googleAuth =

  authenticate: (authCode, clientId, redirect_uri, callback) ->
    oauth2Client = buildAuthClient clientId, redirect_uri
    getAuthToken authCode, oauth2Client, (err, tokens) ->
      oauth2Client.setCredentials(tokens)
      if callback
        callback err, oauth2Client, tokens

  getUserInfo: (oauth2Client, callback) ->
    oauth2.userinfo.get {
      auth: oauth2Client
    }, (err, googleUser) ->
      if err
        console.log "Googleapis User Info Error:", err
      if callback
        callback err, googleUser

  getCalendarEventsList: (oauth2Client, callback) ->
    calendar.events.list {
      calendarId: 'primary'
      auth: oauth2Client
    }, (err, events)->
      if err
        console.log "Googleapis Calendar Events Error:", err
      if callback
        callback err, events

  getCalendarsFromUsers: (userList, callback) ->
    busyFreePromiseList = []
    for user in userList
      getStoredAuthClient user, (oauth2Client) ->
        busyFreePromise = getCalendarFreeBusy(oauth2Client)
        busyFreePromiseList.push busyFreePromise

    Promise.all(busyFreePromiseList).then (eventsList) ->
      callback(eventsList)

  getAuthClient: (user, callback) ->
    return getStoredAuthClient user, (oauth2Client) ->
      if callback
        callback oauth2Client

# Private Methods
getStoredAuthClient = (user, callback) ->
  clientId = config.googleAuthConfig.clientId
  redirectUri = config.googleAuthConfig.redirectUri
  oauth2Client = buildAuthClient clientId, redirectUri
  oauth2Client.setCredentials user.auth

  # Need to refresh access token
  if user.auth.expiry_date < (new Date).getTime()
    console.log("Refreshing Access Token")
    tokenPromise = refreshAccessToken(oauth2Client)
    tokenPromise.then (tokens)->
      console.log(user.id)
      User.methods.updateAuth user.id, tokens
      oauth2Client.setCredentials tokens
      if callback
        callback(oauth2Client)

  else
    if callback
      callback(oauth2Client)

getAuthToken = (authCode, oauth2Client, callback)->
  oauth2Client.getToken authCode, (err, tokens)->
    if err
      console.log "Googleapis Token Error:", err
    if callback
      return callback err, tokens

refreshAccessToken = (oauth2Client) ->
  tokensPromise = new Promise (resolve, reject) ->
    oauth2Client.refreshAccessToken (err, tokens)->
      if err
        console.log "Refresh Access Token Error:", err
        reject(err)
      else
        resolve(tokens)
  return tokensPromise

buildAuthClient = (clientId, redirectUri)->
  secret = config.googleAuthConfig.clientSecret
  OAuth2 = googleapis.auth.OAuth2
  oauth2Client = new OAuth2 clientId, secret, redirectUri
  return oauth2Client

getCalendarIds = (oauth2Client, callback) ->
  calendar.calendarList.list {
    auth: oauth2Client
    minAccessRole: 'freeBusyReader'
  }, (err, calendarIds) ->
    if err
      console.log "Get Calendar Ids Error:", err
    if callback
      callback(err, calendarIds)

getEventsCalendar = (calendarId, oauth2Client)->
  return new Promise (resolve, reject)->
    calendar.events.list {
      calendarId: calendarId || 'primary'
      auth: oauth2Client
    }, (err, events) ->
      if err
        console.log "Googleapis Get Users Calendars Error", err
        reject(err)
      else
        console.log "resolving"
        resolve(events)

getCalendarFreeBusy = (oauth2Client) ->
  today = new Date()
  weekFromToday = new Date(today.getTime() + 7 * 24 * 60 * 60 * 1000)
  return new Promise (resolve, reject) ->
    getCalendarIds oauth2Client, (err, calendarList) ->
      if err
        reject err
      calendarIds = ({id: cal.id} for cal in calendarList.items)
      calendar.freebusy.query {
        resource:
          timeMin: today.toISOString()
          timeMax: weekFromToday.toISOString()
          items: calendarIds
        auth: oauth2Client
      }, (err, busyFree)->
        if err
          console.log "Googleapis Calendar Events Error:", err
          reject err
        else
          resolve busyFree

module.exports = googleAuth