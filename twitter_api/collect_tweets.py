import logging
from tweet_collector import TweetCollector
import sqlite3
import tweepy
import time
import pickle
import pandas as pd
from datetime import datetime

def save_obj(obj, name ):
    with open(name, 'wb') as f:
        pickle.dump(obj, f, pickle.HIGHEST_PROTOCOL)

from credentials.credentials import credentials 

# initialize logger and set level
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# format of the logger
formatter = logging.Formatter('%(asctime)s:%(name)s:%(message)s')

# add a file handler that specifies how and where to save the logs
file_handler = logging.FileHandler('collection.log')
file_handler.setFormatter(formatter)

# add the handler to the logger
logger.addHandler(file_handler)

# initialize tweet collector
col = TweetCollector(credentials)

# connect to the database
conn = sqlite3.connect('tweets.db')
c = conn.cursor()

# pull the user list and the most recent tweet from the DB
c.execute("""SELECT user_id, max(tweet_id)
          FROM tweets
          GROUP BY user_id
          """)
ul = c.fetchall()

ids = {user[0]:() for user in ul}

# set start time
start_time = time.time()
# create a list of id's we failed to pull and count successes
failed = []
success = 0

# create a list of users to retry at the end of the data pull in case
# there is a bad connection
retry = []

# get tweets for each user and write to db
logger.info(f'Beginning collection.')
for user in ul:
    try:
        # grab the timeline, add data to a list, write data to the database
        tl = col.grab_timeline(user = user[0], since_id = user[1])
        text_list = []
        rt_list = []
        for tweet in tl:
            # Check if the tweet is a retweet. If so, return retweet text.
            # If not, return fill text. Create a binary indicator for if it
            # is a retweet
            try:
                text_list.append(tweet.retweeted_status.full_text)
                rt_list.append(1)
            except:
                text_list.append(tweet.full_text)
                rt_list.append(0)
        
        
        tl = [(t.id,
               t.created_at.strftime('%s'),
               text_list[tl.index(t)], # get text based on the index number
               user[0],
               rt_list[tl.index(t)]) for t in tl if t.lang == 'en'] 
        with conn:
            c.executemany("INSERT INTO tweets VALUES(?,?,?,?,?)", tl)
        # Add number of tweets to a dictionary
        ids[user[0]] = len(tl)
        success += 1
    except tweepy.TweepError:
        logger.exception(f'User {user} is protected')
        failed.append(user)
        ids[user[0]] = 0
        pass
    except (ConnectionError):
        logger.exception(f'Bad connection on user {user}, trying later ')
        retry.append(user)
    except Exception as e:
        logger.exception(f'Failed to collect tweets for {user}')
        failed.append(user)
        ids[user[0]] = 0
        pass

# retry pulling missed tweets if there was a bad connection
if len(retry) > 0:
    n_retry = len(retry)
    logger.info(f'Retrying data pull for {n} users')
    for user in retry:
        try:
            # grab the timeline, add data to a list, write data to the database
            tl = col.grab_timeline(user = user[0], since_id = user[1])
            text_list = []
            rt_list = []
            for tweet in tl:
                # Check if the tweet is a retweet. If so, return retweet text.
                # If not, return fill text. Create a binary indicator for if it
                # is a retweet
                try:
                    text_list.append(tweet.retweeted_status.full_text)
                    rt_list.append(1)
                except:
                    text_list.append(tweet.full_text)
                    rt_list.append(0)
        
        
            tl = [(t.id,
               t.created_at.strftime('%s'),
               text_list[tl.index(t)], # get text based on the index number
               user[0],
               rt_list[tl.index(t)]) for t in tl if t.lang == 'en'] 
            with conn:
                c.executemany("INSERT INTO tweets VALUES(?,?,?,?,?)", tl)
            # Add number of tweets to a dictionary
            ids[user[0]] = len(tl)
            success += 1
        except tweepy.TweepError:
            logger.exception(f'User {user} is protected')
            failed.append(user)
            ids[user[0]] = 0
            pass
        except Exception as e:
            logger.exception(f'Failed to collect tweets for {user}')
            failed.append(user)
            ids[user[0]] = 0
            pass
    
    
#close connection to DB
conn.close()

# log the run time
runtime = (time.time()-start_time)/3600
failcount = len(failed)
logger.info(f'Run time:{runtime}. Collected tweets for {success} users. Failed for {failcount} users.')

# save tweet count ID to a csv
colname = datetime.today().strftime('%Y-%m-%d')
tweet_count = pd.DataFrame.from_dict(ids, orient='index', 
                                     columns = [colname], 
                                     dtype = 'int')
tweet_count.index.name = 'User'

# import existing count df, join latest count
count_df = pd.read_csv('tweet_count.csv', index_col='User')
count_df = count_df.join(tweet_count)

# export count results
count_df.to_csv('tweet_count.csv')