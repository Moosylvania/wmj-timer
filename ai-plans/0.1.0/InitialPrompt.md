# Workamajig Quick Timer
I am wanting to build a MacOS Status Bar app that our agency can use to help log time and start a timer when working on projects for time tracking.  The system we use to track time is Workamajig.

## Workamajig API
Currently Workamajig has a REST api that we can use to submit our time sheets.  Documentation is at https://app11.workamajig.com/platinum/?aid=common.apidocs

You have to be logged in to view this but it is currently available in my current browser window.

### Workamajig API Auth
Authentication will require three things:
* The Company API Token - currently saved in @.env WMJ_COMPANY_TOKEN
* The User's API Token - currently saved in @.env WMJ_USER_TOKEN
* The Company's Workamajig URL - currently saved in @.env WMJ_URL

## Application Details
This application should live as a MacOS Status Bar app with an icon of a timer or the workamajig logo.  User's will need to be able to configure all the information for API Auth providing their own API Tokens and Company Workamajig URL.

### Quick Log
Quick log should allow users to quickly browse through a list of projects that they have access to - pulled from the api, select the task that they are working on (tasks are sub items of what can be completed on a project) and then type in the number of hours worked.  This can be a decimal and must be with in quarter hour increments - eg. 0.25 up to 8.  When they click submit it should then submit this time to the user's timesheet for the current day.

### Start Timer
The user should have the ability to start a timer.  When starting a timer, the user must select the Project and Task that they are logging time on.  After the timer is started, a counter is displaying when you hover over/click on the status bar icon.  The user then has the ability to press stop.  Once the timer is stopped, the user can click 'Resume' or 'Submit Time' or 'Discard'. If the user selects Resume, the timer continues forward.  If the user selects 'Submit Time' this should then log to the user's timesheet via the api but the time must be rounded to the closes quarter hour. If the user click's discard, the timer and job info is discarded and the app is back to default state.

When the timer is working a user should also be able to submit a Quick Log so the interface needs to be able to support that.  You can only have one timer running at a time.

## Best Practices
Please follow best practices for building a MacOS Status Bar App.  This will not be distributed via the App Store but user's will be able to download from our GitHub Repo.
We will need to build out a proper README.md for the project as well as documentation on the app.  README.md should explain how the build and do development of the app and link to a user documentation folder that contains Markdown files on how to use the app.