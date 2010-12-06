#!/usr/bin/env python

import argparse
import calendar
import curses
import curses.wrapper
import datetime
import feedparser
import os
import sqlalchemy
import sqlite3
import string
import sys
import time
import webbrowser

from elixir import *

def printable(input):
    return filter(lambda x: x in string.printable, input)

class Feed(Entity):
    id = Field(Integer, primary_key=True)
    items = OneToMany('FeedItem')

    title = Field(String(255))
    url = Field(String(255), unique=True)
    update_interval = Field(Integer, default=3600)

    created_at = Field(DateTime, default=datetime.datetime.now)
    updated_at = Field(DateTime, default=datetime.datetime.now)

    def __init__(self, url):
        """
        Given a url add this feed to the database.
        """

        rss = feedparser.parse(url)

        self.title = rss.feed.title
        self.url = url

    def refresh(self):
        rss = feedparser.parse(self.url)

        for item in rss.entries:
            try:
                feed_item = FeedItem(self, item)
                session.commit()
            except:
                session.rollback()

    def unread(self):
        return len([1 for item in self.items if item.is_read == False])

class FeedItem(Entity):
    id = Field(Integer, primary_key=True)
    feed = ManyToOne('Feed')

    title = Field(String(255))
    url = Field(String(255), unique=True)

    description = Field(Text)

    is_read = Field(Boolean, default=False)
    like_this = Field(Boolean, default=False)

    published_at = Field(DateTime, default=datetime.datetime.now)

    created_at = Field(DateTime, default=datetime.datetime.now)
    updated_at = Field(DateTime, default=datetime.datetime.now)

    def __init__(self, feed, item):
        """
        Create a new item for a feed.
        """
        self.feed = feed

        self.title = item.title
        self.url = item.link

        if item.has_key('published'):
            self.published_at = datetime.datetime(*item.published_parsed[:6])
        elif item.has_key('updated'):
            self.published_at = datetime.datetime(*item.updated_parsed[:6])
        elif item.has_key('created'):
            self.published_at = datetime.datetime(*item.published_parsed[:6])

    def mark_as_read(self):
        """
        Mark the current item as read.
        """
        self.is_read = True
        session.commit()



class Screen(object):
    def __init__(self, stdscr):
        self.stdscr = stdscr

        self.min_y = 1
        self.max_y = curses.LINES

        self.cur_y = 1
        self.cur_x = 0

    def display_menu(self):
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, " rutt %s\n" % self.menu, curses.A_REVERSE)

    def move_pointer(self, pos):
        self.stdscr.addstr(self.cur_y, 0, " ")

        self.cur_y += pos
        self.stdscr.addstr(self.cur_y, 0, ">", curses.A_REVERSE)


class FeedScreen(Screen):
    def __init__(self, stdscr):
        self.feeds = {}
        self.menu = "n:Next Page p:Prev Page a:Add feed R:Refresh q:Quit"
        super(FeedScreen, self).__init__(stdscr)

    def display_feeds(self):
        self.cur_y = self.min_y

        for feed in Feed.query.limit(10):
            self.stdscr.addstr(self.cur_y, 0, "  %d/%d\t\t%s\n" % (feed.unread(), len(feed.items), printable(feed.title),))
            self.feeds[self.cur_y] = feed

            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()

    def window(self, start_limit=None, end_limit=None):
        self.stdscr.clear()

        if start_limit or end_limit:
            self.limit = (start_limit, end_limit)

        self.display_menu()
        self.display_feeds()
        self.move_pointer(0)

    def loop(self):
        self.window(0, curses.LINES - 2)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in 'Aa':
                    pass
                elif chr(c) in 'Rr':
                    pass
                elif chr(c) in 'Pp':
                    self.window(self.limit[0] - curses.LINES - 2, self.limit[0])
                elif chr(c) in 'Nn':
                    self.window(self.limit[1], self.limit[1] + curses.LINES - 2)
                elif chr(c) == ' ':
                    item_screen = ItemScreen(self.stdscr, self.feeds[self.cur_y])
                    item_screen.loop()

                    self.window()
            else:
                if c == curses.KEY_UP:
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.move_pointer(1)

class ItemScreen(Screen):
    def __init__(self, stdscr, feed):
        self.feed = feed
        self.items = {}
        self.menu = ""

        super(ItemScreen, self).__init__(stdscr)

    def display_items(self):
        self.cur_y = self.min_y

        for item in self.feed.items:
            self.stdscr.addstr(self.cur_y, 0, "  %s\t%s\t%s\n" % ('N' if not item.is_read else ' ', item.published_at, printable(item.title),))

            self.items[self.cur_y] = item
            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()

    def window(self, start_limit=None, end_limit=None):
        self.stdscr.clear()

        if start_limit or end_limit:
            self.limit = (start_limit, end_limit)

        self.display_menu()
        self.display_items()
        self.move_pointer(0)

    def loop(self):
        self.window()

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'IiQq':
                    break
                elif chr(c) in 'Pp':
                    self.window(self.limit[0] - curses.LINES - 2, self.limit[0])

                elif chr(c) in 'Nn':
                    self.window(self.limit[1], self.limit[1] + curses.LINES - 2)
                elif chr(c) == ' ':
                    content_screen = ContentScreen(self.stdscr, self.items[self.cur_y])
                    content_screen.loop()

                    self.window()
            else:
                if c == curses.KEY_UP:
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.move_pointer(1)



class ContentScreen(Screen):
    def __init__(self, stdscr, item):
        self.item = item
        self.menu = ""

        super(ContentScreen, self).__init__(stdscr)

    def get_content(self):


        render_cmd = "elinks -dump -force-html %s" % self.item.url
        self.content = os.popen(render_cmd).read().split("\n")

    def move_pointer(self, pos):
        if self.cur_line + pos < 0:
            return

        self.stdscr.addstr(1, 2, "%s (%s)\n" % (self.item.title, self.item.url), curses.A_BOLD)

        self.cur_line = self.cur_line + pos

        lines = self.content[self.cur_line:self.cur_line + curses.LINES - 5]
        cur_y = 2
        for line in lines:
            self.stdscr.addstr(cur_y, 2, "%s\n" % line)
            cur_y += 1

        self.stdscr.refresh()

    def window(self, pointer_pos):
        self.stdscr.clear()
        self.display_menu()
        self.move_pointer(pointer_pos)

    def loop(self):
        self.cur_line = 0
        self.get_content()
        self.window(0)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'IiQq':
                    self.item.mark_as_read()
                    break
                elif chr(c) in 'Bb':
                    webbrowser.open_new_tab(self.item['url'])
                elif chr(c) in ' ':
                    self.window(10)
            else:
                if c == curses.KEY_UP:
                    self.window(-1)
                elif c == curses.KEY_DOWN:
                    self.window(1)

def start_screen():
    stdscr = curses.initscr()

    curses.start_color()
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.init_pair(2, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)

    curses.noecho()
    curses.cbreak()
    stdscr.keypad(1)

    stdscr.clear()

    feed_screen = FeedScreen(stdscr)
    feed_screen.loop()

    # Die!
    stdscr.keypad(0)
    curses.echo()
    curses.nocbreak()
    curses.endwin()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="rutt - Mutt like RSS/Atom reader")
    parser.add_argument('-a', '--add', nargs='+', help="Add a new feed.", metavar="url")
    parser.add_argument('-r', '--reload', action='store_true', help="Update feeds.")
    parser.add_argument('-l', '--list-feeds', action='store_true', help="List the feeds")
    args = parser.parse_args()

    metadata.bind = "sqlite:///rutt.db"
    metadata.bind.echo = False

    # Create the models.
    setup_all()
    create_all()

    if args.add is not None:
        for url in args.add:
            try:
                feed = Feed(url)
                session.commit()
            except sqlalchemy.exc.IntegrityError:
                session.rollback()
            except:
                print "Failed to add %s" % url

        sys.exit()

    if args.list_feeds is True:
        for feed in Feed.query.all():
            print feed.url

            for item in feed.items:
                print "|-> %s" % item.url
        sys.exit()

    if args.reload is True:
        for feed in Feed.query.all():
            feed.refresh()

        sys.exit()

    start_screen()
