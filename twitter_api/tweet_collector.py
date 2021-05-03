# tweet collector class for pulling data from the rest API and writing to a SQLite database
import logging
import tweepy

# initialize logger and set level
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
# format of the logger
formatter = logging.Formatter('%(levelname)s:%(name)s:%(message)s')
# add a file handler that specifies how and where to save the logs
file_handler = logging.FileHandler('tweets.log')
file_handler.setFormatter(formatter)
# add the handler to the logger
logger.addHandler(file_handler)

class TweetCollector(object):
    '''
    Class to connect to twitter rest API and collect tweets from users
    '''
    def __init__(self, credentials):
        auth = tweepy.OAuthHandler(credentials['consumer_key'], 
                                   credentials['consumer_secret'])
        auth.set_access_token(credentials['access_token'],
                              credentials['access_token_secret'])
        self.api = tweepy.API(auth, wait_on_rate_limit=True,
                              wait_on_rate_limit_notify=True)


    def _get_batch(self, user, max_id=None, since_id=None, count=None):
        '''
        Grabs one batch of tweets from a user's timeline
        Called by grab_timeline
        '''
        tweets = self.api.user_timeline(id=user,  
                                        max_id=max_id, 
                                        since_id=since_id,
                                        count=count,
                                        tweet_mode='extended')
        n = len(tweets)
        logger.debug(f'Got batch of size {n}.')
        return tweets
    
    def grab_timeline(self, user, since_id=None, max_id=None,
                      batch_size=200):
        '''
        Grabs as much as we can get from a user's timeline
        '''
        
        logger.info(f"Grabbing tweets from user: {user}.")

        # create an out list that will hold multiple batches if necessary
        out = []
        # pull first batch
        batch = self._get_batch(user=user, max_id=max_id, 
                                since_id=since_id, count=batch_size)
        out.extend(batch)
        
        # return out if there are no tweets
        if len(out) == 0:
            logger.warning(f"Got 0 tweets in 1 batches from user {user}")
            return out
        
        # gets the id of the second oldest tweet
        # twitter api starts with the most
        first_id = out[-1].id - 1
        n_batches = 0

        # Keep pulling batches until there are no more tweets
        if len(out) >= 100: # this is prone to errors.
            while len(batch) > 0:
                logger.debug(f'Retrieving additional batch. First id: '
                                  f'{first_id}')
                batch = self._get_batch(user=user, max_id=first_id, 
                                        since_id=since_id, count=batch_size)
                out.extend(batch)
                first_id = out[-1].id - 1
                n_batches += 1
            
        n = len(out)
        last = out[0]._json['created_at']
        first = out[-1]._json['created_at']
        logger.info(f"Got {n} tweets in {n_batches+1} batches from user {user}.")
        logger.debug(f"Oldest tweet created at: {first}.")
        logger.debug(f"Latest tweet created at: {last}.")
        return out
    