_ = require('underscore')
db = require('../db')
epi = require('epi-week')

remindEveryone = (recipients) ->
  { week, year } = epi()
  db.view('kujua-base', 'clinic_by_phone', (err, data) ->
    throw err if err
    recipients = _.pluck(data.rows, 'value')
    _.each(recipients, (recipient) ->
      db.view('kujua-sentinel', 'cdc_reminders', key: recipient, limit: 1, (err, data) ->
        reminder = data.rows?[0]?.value
        phone = recipient?.contact?.phone
        task = {
          week: week
          year: year
          messages: [ to: phone, message: "This is a reminder to submit your report for week #{week} of #{year}. Thank you!" ]
          type: 'prompt'
          state: 'pending'
        }
        if phone
          if reminder
            existing_task = _.find(reminder.tasks, (task) ->
              week is task.week and year is task.year and task.type is 'prompt'
            )
            unless existing_task
              reminder.tasks.push(task)
              db.saveDoc(reminder, (err, result) ->
                console.error(err) if err
              )
          else
            db.saveDoc(
              recipient: recipient
              tasks: [ task ]
              type: 'cdc_reminder'
            , (err, result) ->
              console.error(err) if err
            )
      )
    )
  )


remindNonResponders = ->
  last_week = new Date()
  last_week.setDate(last_week.getDate() - 1)
  { week, year } = epi(last_week) # reminder is for the week just gone
  db.view('kujua-sentinel', 'cdc_reminders', (err, data) ->
    { rows } = data
    _.each(rows, (row) ->
      clinic = row.key
      phone = clinic?.contact?.phone
      reminder = row.value
      existing_task = _.find(reminder.tasks, (task) ->
        week is task.week and year is task.year and task.type is 'nonresponder_prompt'
      )
      if phone and not existing_task
        db.view('kujua-sentinel', 'cdc_received_reports', key: [ clinic, year, week ], limit: 1, (err, data) ->
          reported = data.rows.length is 1
          unless reported
            reminder.tasks.push(
              {
                week: week
                year: year
                messages: [ to: phone, message: "You have not yet submitted your report for week #{week} of #{year}. Please do so as soon as possible. Thanks!" ]
                type: 'nonresponder_prompt'
                state: 'pending'
              }
            )
            db.saveDoc(reminder, (err) ->
              console.error(err) if err
            )
        )
    )
  )

module.exports = ->
  day = new Date().getDay()
  if day is 3 # Friday
    remindEveryone()
  else if day is 0 # Sunday
    remindNonResponders()