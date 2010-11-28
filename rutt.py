#!/usr/bin/env python

import os
import curses
import curses.wrapper
import sys
import sqlite3
import feedparser
import time

class Database(object):
    def __init__(self):
        self.conn = sqlite3.connect('config/rutt.db')
        self.c = self.conn.cursor()

        self.create_tables()

        self.conn.commit()

    def close(self):
        self.c.close()

    def create_tables(self):
        self.c.execute('''create table if not exists feeds (
                          id integer PRIMARY KEY,
                          title text,
                          url text,
                          interval integer default 3600,
                          created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          UNIQUE(url))''')

        self.c.execute('''create table if not exists items (
                          id integer PRIMARY KEY,
                          feed_id integer,
                          title text,
                          url text,
                          description text,
                          read int default 0,
                          created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          UNIQUE(url),
                          FOREIGN KEY(feed_id) REFERENCES feeds(id))''')

    def add_feed(self, url):
        url_feed = feedparser.parse(url)
        title =  url_feed.feed.title

        self.c.execute('''insert or ignore into feeds (title, url) values (?, ?)''', (title, url))
        self.conn.commit()


    def get_feeds(self):
        self.c.execute('''select id, title, url, strftime('%s', updated_at), interval from feeds''')
        rows = self.c.fetchall()

        for row in rows:
            (feed_id, title, url, updated_at, interval) = row

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 0''', (feed_id,))
            (new_items,) = self.c.fetchone()

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 1''', (feed_id,))
            (read_items,) = self.c.fetchone()

            yield {
                'feed_id': feed_id,
                'title': title,
                'url': url,
                'new': new_items,
                'read': read_items,
                'updated_at': updated_at,
                'interval': interval
                }

    def update_feeds(self):
        items = []

        for item in self.get_feeds():

            # Yuck. Must be a better way to do this...
            if (int(time.strftime('%s', time.gmtime())) - int(item['updated_at'])) > int(item['interval']):
                break


            url_feed = feedparser.parse(item['url'])

            for entry in url_feed.entries:
                print entry.title
                print entry.link

                self.c.execute('''insert or ignore into items (feed_id, url, title, description) values (?, ?, ?, ?)''', (item['feed_id'], entry.link, entry.title, ''))

        self.conn.commit()

    def get_items(self, feed_id):
        self.c.execute('''select id, title, url, read, updated_at from items where feed_id = ? order by id desc''', (feed_id))
        rows = self.c.fetchall()

        for row in rows:
            (item_id, title, url, read, updated_at) = row

            yield {
                'item_id': item_id,
                'title': title,
                'url': url,
                'read': (read == 1),
                'updated_at': updated_at,
                }

    def get_item(self, item_id):
        self.c.execute('''select id, title, url from items where id = ?''', (item_id,))
        (item_id, title, url,) = self.c.fetchone()

        return {
            'item_id': item_id,
            'title': title,
            'url': url,
            }

    def mark_item_as_read(self, item_id):
        self.c.execute('''update items set read = 1, updated_at = datetime('now') where id = ?''', (item_id,))
        self.conn.commit()

class Screen(object):
    def __init__(self, stdscr):
        self.stdscr = stdscr

        self.min_y = 1
        self.max_y = curses.LINES

        self.cur_y = 1
        self.cur_x = 0

    def display_menu(self):
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, " rutt a:Add feed R:Refresh q:Quit\n", curses.A_REVERSE)

    def move_pointer(self, pos):
        self.stdscr.addstr(self.cur_y, 0, " ")

        self.cur_y += pos
        self.stdscr.addstr(self.cur_y, 0, ">", curses.A_REVERSE)


class FeedScreen(Screen):
    def __init__(self, stdscr):
        self.feeds = {}
        super(FeedScreen, self).__init__(stdscr)

    def display_feeds(self):
        global config

        self.cur_y = self.min_y

        for item in config.get_feeds():
            self.stdscr.addstr(self.cur_y, 0, "  %d/%d\t\t%s\n" % (item['new'],
                                                                   item['new'] + item['read'],
                                                                   item['title'],))
            self.feeds[self.cur_y] = item['feed_id']
            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()


    def loop(self):
        self.display_menu()
        self.display_feeds()
        self.move_pointer(0)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in 'Aa':
                    pass
                elif chr(c) in 'Rr':
                    pass
                elif chr(c) == ' ':
                    item_screen = ItemScreen(self.stdscr, str(self.feeds[self.cur_y]))
                    item_screen.loop()

                    self.stdscr.clear()

                    self.display_menu()
                    self.display_feeds()
                    self.move_pointer(self.min_y)
            else:
                if c == curses.KEY_UP:
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.move_pointer(1)

class ItemScreen(Screen):
    def __init__(self, stdscr, feed_id):
        self.feed_id = feed_id
        self.items = {}

        super(ItemScreen, self).__init__(stdscr)

    def display_items(self):
        global config

        self.cur_y = self.min_y

        for item in config.get_items(self.feed_id):
            self.stdscr.addstr(self.cur_y, 0, "  %s\t%s\n" % ('N' if not item['read'] else ' ', item['title']))

            self.items[self.cur_y] = item['item_id']
            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()

    def loop(self):
        self.display_menu()
        self.display_items()
        self.move_pointer(0)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) == ' ':
                    content_screen = ContentScreen(self.stdscr, self.items[self.cur_y])
                    content_screen.loop()

                    self.stdscr.clear()

                    self.display_menu()
                    self.display_items()
                    self.move_pointer(0)
            else:
                if c == curses.KEY_UP:
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.move_pointer(1)



class ContentScreen(Screen):
    def __init__(self, stdscr, item_id):
        self.item_id = item_id
        super(ContentScreen, self).__init__(stdscr)

    def get_content(self):
        global config

        self.item = config.get_item(self.item_id)
        config.mark_item_as_read(self.item_id)

        render_cmd = "elinks -dump -force-html %s" % self.item['url']
        self.content = os.popen(render_cmd).read().split("\n")
        self.content.reverse()

    def display_content(self):
        self.stdscr.addstr("%s\n" % self.item['title'])
        self.stdscr.addstr("%s\n\n" % self.item['url'])

        cur_line = 1
        while cur_line < (curses.LINES - 5):
            if len(self.content) > 0:
                self.stdscr.addstr("  %s\n" % self.content.pop())
            else:
                self.stdscr.addstr("\n")

            cur_line += 1

    def loop(self):
        self.get_content()

        while True:
            self.stdscr.clear()
            self.display_menu()

            self.display_content()
            self.stdscr.refresh()

            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in ' ':
                    continue
            else:
                if c == curses.KEY_UP:
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.move_pointer(1)



config = None
def open_config():
    global config

    config = Database()

    # add_url("http://www.planetpostgresql.org/atom.xml")
    # config.add_feed("http://feeds2.feedburner.com/al3x")
    # config.add_feed("http://www.allthingsdistributed.com/atom.xml")
    # config.add_feed("http://antirez.com/rss")

    # config.update_feeds()

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


def main():
    open_config()

    # Start the thing.
    start_screen()


main()


