# This script takes a stratified random sample from the followers
# table based on state populations. The sample is saved in
# the 'stratified' table of the database

import sqlite3
import re
import pandas as pd
from random import sample

def state_sample(state, user_list, n):
    """
    Get a random sample of n users from a state
    Pass a list of users queried from the follower table in the DB
    """
    pop = [user for user in user_list if re.search(f', {state}$', user[2])]
    pop_size = len(pop)
    print(f'Taking a sample of {n} from a population of {pop_size} users in {state}')
    return sample(pop, n)

# import state population table from wikipedia
url ="https://en.wikipedia.org/wiki/List_of_states_and_territories_of_the_United_States_by_population"
df = pd.read_html(url)[0]

# drop columns
df = df.loc[:,['State', 'Percent of the total U.S. population, 2019[note 2]']]
df.columns = ['State', 'Population Percent']

# drop territories and sums
df = df.iloc[0:52,:]

# drop puerto rico
df = df.drop(30)

# add two letter abbreviations
df = df.sort_values(by = "State", ascending = True)
states = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", 
          "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", 
          "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", 
          "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", 
          "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]

df["Abbreviation"] = states

# define function to convert strings to floats
def convert_perc(string):
    return float(string.strip('%'))/100

# convert to percentages
perc = [round(convert_perc(num), ndigits=5) for num in df['Population Percent']]

# get the sample size for each state
sampsize = [int(50000*p) for p in perc]

# add to the df
df['Sample'] = sampsize
#reset index
df.reset_index(inplace=True)

# create the table
conn = sqlite3.connect('followers') #replace :memory: with followers.db
# create cursor
c = conn.cursor()

# create table
c.execute("""CREATE TABLE stratified (
            id integer,
            name text,
            location text,
            lang text,
            protected text,
            followers integer,
            friends integer,
            statuses integer,
            last_status int
            )""")

# commit the current transaction. Make sure to commit changes
conn.commit()

for row in range(len(df)):
    state = df['Abbreviation'][row]
    ss = df['Sample'][row]
    # get a random sample for the state from the active user list
    ul = state_sample(state, active_users, ss)
    # write to the db
    with conn:
        c.executemany("INSERT INTO stratified VALUES(?,?,?,?,?,?,?,?,?)", ul)    
conn.close()