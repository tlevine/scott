var fs = require('fs')

var $ = require('jquery')
  , _ = require('lodash')
  , Backbone = require('backbone')
  , SessionModel = require('./models/session')
  , sessionTemplate = fs.readFileSync('../templates/header/session.html')

var SessionView = Backbone.View.extend({
  el: '#session',
  sessionModel: new SessionModel(),
  render: function () {
    this.sessionModel.fetch()
    $(this.el).html(_.template(sessionTemplate, {session: this.sessionModel}))
  },
  login: function(e) {
    e.preventDefault()
    var username = $(e.currentTarget).children('input[name=username]').val()
    var password = $(e.currentTarget).children('input[name=password]').val()
    this.sessionModel.logIn(username, password, function() {
      window.location.reload()
    })
    return false
  },
  logout: function(e) {
    e.preventDefault()
    this.sessionModel.logOut()
    window.location.reload()
    return false;
  },
  events: {
    'submit form': 'login',
    'click #logout': 'logout'
  }
})

module.exports = SessionView;
