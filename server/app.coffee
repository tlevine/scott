fs = require 'fs'

restify = require 'restify'
# http://mcavage.github.com/node-restify/

sqlite3 = require 'sqlite3'
# https://github.com/developmentseed/node-sqlite3/wiki/API

node_static = require 'node-static'
# https://github.com/cloudhead/node-static

bunyan = require 'bunyan'
# https://github.com/trentm/node-bunyan

csv = require 'csv'
# http://www.adaltas.com/projects/node-csv/to.html

SETTINGS = require './settings'
ACCOUNTS = require '../private/accounts'

console.log SETTINGS
console.log ACCOUNTS

# ORM alternative
# Each column definition is [name, regex, type, default]
SCHEMA = [
  # Automatically taken from the listings page
  ["projectDescription", /^.*$/, 'TEXT NOT NULL', ''],
  ["applicant", /^.*$/, 'TEXT NOT NULL', ''],
  ["projectManagerPhone", /^.*$/, 'TEXT NOT NULL', ''],
  ["projectManagerEmail", /^.*$/, 'TEXT NOT NULL', ''],
  ["projectManagerName", /^.*$/, 'TEXT NOT NULL', ''],
  ["publicNoticeDate", /^[0-9]{4}-[01][0-9]-[0-3][0-9]$/, 'TEXT NOT NULL', '0000-00-00'],
  ["expirationDate", /^[0-9]{4}-[01][0-9]-[0-3][0-9]$/, 'TEXT NOT NULL', '0000-00-00'],
  ["publicNoticeUrl", /^.*$/, 'TEXT NOT NULL', '' ], # On the Army Corps site
  ["drawingsUrl", /^.*$/, 'TEXT NOT NULL', '' ],     # On the Army Corps site
  ["parish", /^(|acadia|allen|ascension|assumption|avoyelles|beauregard|bienville|bossier|caddo|calcasieu|caldwell|cameron|catahoula|claiborne|concordia|de soto|east baton rouge|east carroll|east feliciana|evangeline|franklin|grant|iberia|iberville|jackson|jefferson|jefferson davis|lafayette|lafourche|la salle|lincoln|livingston|madison|morehouse|natchitoches|orleans|ouachita|plaquemines|pointe coupee|rapides|red river|richland|sabine|saint bernard|saint charles|saint helena|saint james|saint john the baptist|saint landry|saint martin|saint mary|saint tammany|tangipahoa|tensas|terrebonne|union|vermilion|vernon|washington|webster|west baton rouge|west carroll|west feliciana|winn)$/, 'TEXT NOT NULL', '']

  # Automatically taken from the public notice
  ["CUP", /^.*$/, 'TEXT NOT NULL', ''],
  ["WQC", /^.*$/, 'TEXT NOT NULL', ''],
  ["HUC", /^.*$/, 'TEXT NOT NULL', ''],
  ["AI", /^.*$/, 'TEXT NOT NULL', ''],
  ["locationOfWork", /^.*$/, 'TEXT NOT NULL', ''],
  ["characterOfWork", /^.*$/, 'TEXT NOT NULL', ''],

  # Manually taken from the public notice
  ["longitude", /^-?[0-9.]*$/, 'FLOAT', ''],
  ["latitude", /^-?[0-9.]*$/, 'FLOAT', '']
  ["acreage", /^[0-9.]*$/, 'FLOAT', ''],

  # Notes
  ["type", /^(impact|mitigation|restoration|other)$/, 'TEXT NOT NULL', ''],
  ["notes", /^.*$/, 'TEXT NOT NULL', ''],
  ["status", /^[1-5]$/, 'TEXT NOT NULL', '1'],
  ["flagged", /^[01]$/, 'TEXT NOT NULL', '0'],
  ["reminderDate", /^(|[0-9]{4}-[01][0-9]-[0-3][0-9])$/, 'TEXT NOT NULL', '0000-00-00']
]

#
# Helper functions
# ===========================================================

# Check whether a username and password combination corresponds to an account.
isUser = (username, password) ->
  username != undefined and password != undefined and password == ACCOUNTS[username]

# Check that an edit is allowed
isAuthorized = (req, res) ->
  # Must be authenticatied
  return req.authorization.basic and (isUser req.authorization.basic.username, req.authorization.basic.password)

notValid = (req, res) ->
  for key in SCHEMA

    # Validation (key[1] is always a regular expression.)
    if req.body[key[0]] != undefined and not ('' + req.body[key[0]]).match key[1]
      return "#{key[0]} must match #{key[1]}"

  return false

# Set up the SQLite database based on the SCHEMA
db = new sqlite3.Database SETTINGS.dbfile
table = '''
CREATE TABLE IF NOT EXISTS application (
  permitApplicationNumber TEXT NOT NULL,
  UNIQUE(permitApplicationNumber)
);'''
db.run table, (err) ->
  if (err)
    console.log err
  else
    SCHEMA.map (row) ->
      db.run "ALTER TABLE application ADD COLUMN \"#{row[0]}\" \"#{row[2]}\" DEFAULT \"#{row[3]}\";", (err) ->
        if (err && !(('' + err).match 'duplicate'))
          # Log if there's an error I care about.
          console.log err

#
# Go
# ===========================================================

# Serve the API
server = restify.createServer()

server.use (restify.bodyParser { mapParams: false })
#server.use restify.gzipResponse()

server.use (restify.authorizationParser())

if SETTINGS.log
  server.on 'after', restify.auditLogger
    log: bunyan.createLogger
      name: 'scott'
      streams: [{
        level: 'trace',
        path: SETTINGS.logfile
      }]

#
# Web API endpoints
# ===========================================================

# Check whether the password is correct
server.post '/login', (req, res, next) ->

  # Authenticate
  if not (isAuthorized req, res)
    return next(new restify.NotAuthorizedError 'Incorrect username or password')
  notValidMsg = notValid req, res
  if notValidMsg
    return next(new restify.InvalidContentError notValidMsg)

  res.send 204
  next()


# Create an application
server.post '/applications/:permitApplicationNumber', (req, res, next) ->

  # Authenticate
  if not (isAuthorized req, res)
    return next(new restify.NotAuthorizedError 'Incorrect username or password')
  notValidMsg = notValid req, res
  if notValidMsg
    return next(new restify.InvalidContentError notValidMsg)

  # All keys must exist
  for key in SCHEMA
    if req.body[key[0]] == undefined
      return next(new restify.MissingParameterError "You need to pass the #{key[0]}.")

  keys = 'permitApplicationNumber,' + (SCHEMA.map (key)-> key[0]).join ','
  questionMarks = '?,' + (SCHEMA.map (key) -> '?').join ','
  sql = "INSERT INTO application (#{keys}) VALUES (#{questionMarks});"
  values = [req.body.permitApplicationNumber].concat (SCHEMA.map (key)-> req.body[key[0]])

  # Run the query
  db.get "SELECT count(*) AS 'c' FROM application WHERE permitApplicationNumber = ?", req.body.permitApplicationNumber, (err, row) ->
    if row.c == 1
      next(new restify.InvalidContentError "There is already a permit application with number #{req.body.permitApplicationNumber}")

    db.run sql, values, (err) ->
      if err
        next(new restify.InvalidContentError err)
      else
        # On success, write to the log file
        logline = new Date() + ' ' + req.authorization.basic.username + ' ' + JSON.stringify(req.body) + '\n'
        fs.writeFile(SETTINGS.humanlogprefix + req.params.permitApplicationNumber + '.log', logline)

        res.send 204
        next()

# Edit an application
server.patch '/applications/:permitApplicationNumber', (req, res, next) ->

  # Authenticate
  if not isAuthorized req, res
    return next(new restify.NotAuthorizedError 'Incorrect username or password')
  notValidMsg = notValid req, res
  if notValidMsg
    return next(new restify.InvalidContentError notValidMsg)

  # Lines of SQL
  sqlExprs = ("#{key[0]} = ?" for key in SCHEMA when req.body[key[0]] != undefined)

  # Text for a transaction
  sql = "UPDATE application SET #{sqlExprs.join ','} WHERE permitApplicationNumber = ?;"

  # Escaped values for the SQL
  values = (SCHEMA.map ((key) ->
    if req.body[key[0]] == undefined
      []
    else
      [req.body[key[0]]]
  )).reduce((a, b) -> a.concat b).concat([req.params.permitApplicationNumber])

  # Run the query
  db.run sql, values, (err) ->
    if err
      next(new restify.InvalidContentError err)
    else
      # On success, write to the log file
      logline = new Date() + ' ' + req.authorization.basic.username + ' ' + JSON.stringify(req.body) + '\n'
      fs.appendFile(SETTINGS.humanlogprefix + req.params.permitApplicationNumber + '.log', logline)

      res.send 204
      next()

# View an application
server.get '/applications/:permitApplicationNumber', (req, res, next) ->
  sql = "SELECT * FROM application WHERE permitApplicationNumber = ? LIMIT 1;"
  db.get sql, req.params.permitApplicationNumber, (err, row) ->
    if row
      res.send row
      next()
    else
      next(new restify.ResourceNotFoundError 'There is no permit with this number.')

# View an application's update history
server.get '/applications/:permitApplicationNumber/history', (req, res, next) ->
  fs.readFile SETTINGS.humanlogprefix + req.params.permitApplicationNumber + '.log', 'utf8', (err, data) ->
    if (err)
      next(new restify.InternalError err)
    else
      res.setHeader 'content-type', 'text/plain'
      res.send data
      next()

# List the applications
server.get '/applications', (req, res, next) ->
  sql = "SELECT permitApplicationNumber, projectDescription, type, acreage, expirationDate, flagged, reminderDate, latitude, longitude, status FROM application;"
  db.all sql, (err, rows) ->
    if (err)
      next(new restify.InvalidContentError err)
    else
      res.send rows
      next()

#
# Export
# ===========================================================

# List the applications as JSON
server.get '/applications.json', (req, res, next) ->
  sql = "SELECT * FROM application;"
  db.all sql, (err, rows) ->
    if (err)
      next(new restify.InvalidContentError err)
    else
      res.send rows
      next()

# List the applications as csv
server.get '/applications.csv', (req, res, next) ->
  csv_columns = SCHEMA.map ((row) -> row[0])
  sql = "SELECT * FROM application;"
  db.all sql, (err, rows) ->
    if (err)
      next(new restify.InvalidContentError err)
    else
      listRows = rows.map (row) ->
        csv_columns.reduce (a, b) ->
          if a == 'permitApplicationNumber'
            [row[a], row[b]]
          else
            a.concat [row[b]]
      csv().from(listRows).to (csvString) ->
        res.setHeader 'content-type', 'text/csv'
        res.send csv_columns.join(',') + '\n' + csvString
        next()

# Applications as SQLite database
server.get '/applications.db', (req, res, next) ->
  fs.readFile SETTINGS.dbfile, (err, data) ->
    if (err)
      next(new restify.InvalidContentError err)
    else
      res.setHeader 'content-type', 'application/x-sqlite3'
      res.send data
      next()


# Get private stuff
secrets = new node_static.Server '../private', { cache: SETTINGS.cache }
server.get /secrets\/.*$/, (req, res, next) ->
  secrets.serve req, res, next

#
# Serve the client
# ===========================================================

file = new node_static.Server '../client', { cache: SETTINGS.cache }
server.get /^.*$/, (a, b, c) ->
  file.serve a, b, c
server.listen SETTINGS.port

#
# Make it a module.
# ===========================================================
module.exports = server
