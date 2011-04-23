# Rutt

## Description

Rutt is the Mutt of news reader. The fastest way to read news feeds.

## Configuration

Set options by running `rutt -s key value`. Below I describe some keys

### Instapaper

You need to get an Instapaper OAuth consumer key.
[Apply here](http://www.instapaper.com/main/request_oauth_consumer_token).
Marco will send you a key. Currently this does require that you have
an [Instapaper subscription](http://www.instapaper.com/subscription).

Set the following config keys once you receive your API credential.

    instapaper.consumer-key
    instapaper.consumer-secret
    instapaper.username
    instapaper.password

## Dependencies

- elinks: Needed for the text based browsing.

## Install

    gem install rutt
