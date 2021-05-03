## About

This research examines the use of threat minimizing and threat maximizing language on twitter with relation to COVID-19

classifier: Contains files and data to train the Electra classifier and label tweets
* reconciled_labels.csv contains tweets labeled by three coders for threat minimizing language
* electra_classifier.ipynb is a notebook for training the classifier, as well as sweeping hyperparameters via W&B
* classify_tweets.ipynb uses the trained classifier to label covid related tweets

collection_logs: Contains scripts for parsing collection logs to identify banned users.

ideology: Contains a script for estimating user ideology on a left-right spectrum

twitter_api: scripts used for querying the twitter API to collect tweets. Requires a credential file with API keys to run

database: scripts for creating the user database
* ID pull.py pulls followers from the list of political elites in elites.csv
* stratified\_sample.py generates a stratified random sample of users form ID pull.py based on state\_pop\_data.csv
* sqlite pull.R, a generic R script for accessing the SQLite data bases
* create\_user\_db.R creates the final database of users and user meta data
