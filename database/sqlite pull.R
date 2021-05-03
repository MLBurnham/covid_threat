library(RSQLite)
setwd("C:/Users/mikeb/OneDrive - The Pennsylvania State University/SoDA 501")

# connect to the data base. The conn object is your connection
conn <- dbConnect(SQLite(), "tweets.db")

# A SQL database can contain multiple tables.
# list the tables in the data base
dbListTables(conn)

# To pull data pass your connection and the SQL code as a string to the
# dbGetQuery function. The asterisk is a wild card for "any".

#### Examples
# Pull all user meta data from the database
users <- dbGetQuery(conn, "SELECT * FROM users")
head(users)

# Pull all tweets. This is 10.6 gigs in size, may take a while
# or crash your computer if you run out of RAM
tweets <- dbGetQuery(conn, "SELECT * FROM tweets")

# pull the first 100 rows from the tweets table
tweets <- dbGetQuery(conn, "SELECT * FROM tweets LIMIT 100")

# Pull the tweet_id and date for the first 100 tweets that aren't retweets
tweets <- dbGetQuery(conn, "SELECT tweet_id, date FROM tweets WHERE retweet = 0 LIMIT 100")

# When you're done you must close your connection to the data base.
# Failure to do so can corrupt the data base
dbDisconnect(conn)
