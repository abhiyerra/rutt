# Rutt

## Description

Rutt is the Mutt of news reader. It attempts to be the fastest way
to read news feeds.

Currently rutt is still in heavy development and it is a bit
unstable although the main features are largely implemented.
It still needs a bit of polishing before it can be considered
stable.

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

- elinks

## Download & Repository

Rutt is still in heavy development so please
check out the [repository](https://github.com/abhiyerra/rutt) to use it.

 - https://github.com/abhiyerra/rutt

Install via gem:

    gem install rutt
