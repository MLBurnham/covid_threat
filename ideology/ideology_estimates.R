library(ggplot2)
library(Matrix)
library(reshape2)
library(devtools)
library(rlang)
library(rjson)
library(tweetscores)

# import friends
friends <- fromJSON(file = 'friends/master_friends.json')
handles <- names(friends)

# frist batch of users
friends4 <- friends[20000:30000]
handles4 <- names(friends1)

# initialize empty df
df <- data.frame(ID=NA, mean=NA, sd=NA, 'i2.5'=NA, 'i25'=NA, 'i50'=NA, 'i75'=NA, 'i97.5'=NA, Rhat=NA, neff=NA, mean=NA, sd=NA, 'sd2.5'=NA, 'sd25'=NA, 'sd50'=NA, 'sd75'=NA, 'sd97.5'=NA, sdRhat=NA, sdneff=NA)

# for each interest group account, estimate ideology
for(handle in handles4){
    row <- tryCatch(
        expr = {
            results <- estimateIdeology(user = handle, friends = friends[[handle]])
            results <- c(handle, summary(results)[2,], summary(results)[1,])
        },
        error = function(e){
            # If the account follows no elites, try to use method 2 of ideology estimation
            results <- tryCatch(
                expr = {
                    results <- round(estimateIdeology2(user = handle, friends = friends[[handle]]), digits = 2) # round to second decimal place
                    results <- c(handle, results,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                },
                # If method two fails then append a row of zeros
                error = function(e){
                    results <- c(handle, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                }
            )
        }
    )
    # bind results to the df
    df <- rbind(df, row)
}

write.csv(df, 'ideology scores4.csv');