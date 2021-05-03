import tweepy
import pandas as pd
import logging
import math
import pickle
from credentials import credentials

# instantiate logger
logger = logging.basicConfig(level = logging.INFO, format = "%(levelname)s:%(message)s")

# authentication and api
auth = tweepy.OAuthHandler(credentials['consumer_key'], credentials['consumer_secret'])
auth.set_access_token(credentials['access_token'], credentials['access_token_secret'])
api = tweepy.API(auth, wait_on_rate_limit = True, wait_on_rate_limit_notify = True)

#functions for saving and loading pickled objects
def save_obj(obj, name ):
    with open(name + '.pkl', 'wb') as f:
        pickle.dump(obj, f, pickle.HIGHEST_PROTOCOL)
    
# load function for the dictionary
def load_obj(name):
    with open(name + '.pkl', 'rb') as f:
        return pickle.load(f)
    
elites_df = pd.read_csv('Elites/follower_pull.csv')

for i in range(535,len(elites_df)):
    # define the username, id, and number of followers to pull for a user
    username = elites_df['screen_name'][i]
    userid = elites_df['id'][i]
    pull_num = elites_df['pull'][i]
    # initialize an empty list of followers
    followers = []
    
    try:
        # pull followers for the user and append to the followers list
        for user in tweepy.Cursor(api.followers_ids, user_id = userid, count = 5000).items(pull_num):
            followers.append(user)
        logging.info(f'pulled {pull_num} followers from {username}')
    
    except Exception as e:
        # print location of the error if there is one
        logging.warning(f'failed to pull followers for {username}')
        print(e)
    
    # define a new dictionary entry for the user and their followers
    follower_ids[username] = followers
    # pickle the data after each name completed
    save_obj(follower_ids, 'follower_ids')