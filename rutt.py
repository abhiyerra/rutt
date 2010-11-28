#!/usr/bin/env python

import os
import curses
import sys
import sqlite3
import feedparser

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
                          interval integer,
                          UNIQUE(url))''')

        self.c.execute('''create table if not exists items (
                          id integer PRIMARY KEY,
                          feed_id integer,
                          title text,
                          url text,
                          description text,
                          read int default 0,
                          UNIQUE(url),
                          FOREIGN KEY(feed_id) REFERENCES feeds(id))''')

    def add_feed(self, url):
        url_feed = feedparser.parse(url)
        title =  url_feed.feed.title

        self.c.execute('''insert into feeds (title, url) values (?, ?)''', (title, url))
        self.conn.commit()


    def get_feeds(self):
        self.c.execute('''select id, title, url from feeds''')
        rows = self.c.fetchall()

        for row in rows:
            (feed_id, title, url) = row

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 0''', (feed_id,))
            (new_items,) = self.c.fetchone()

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 1''', (feed_id,))
            (read_items,) = self.c.fetchone()

            yield {
                'feed_id': feed_id,
                'title': title,
                'url': url,
                'new': new_items,
                'read': read_items
                }

    def update_feeds(self):
        items = []

        for item in self.get_feeds():
            url_feed = feedparser.parse(item['url'])

            for entry in url_feed.entries:
                print entry.title
                print entry.link

                self.c.execute('''insert or replace into items (feed_id, url, title, description) values (?, ?, ?, ?)''', (item['feed_id'], entry.link, entry.title, ''))

        self.conn.commit()

    def get_items(self, feed_id):
        self.c.execute('''select id, title, url, read from items where feed_id = ? order by id desc''', (feed_id))
        rows = self.c.fetchall()

        for row in rows:
            (item_id, title, url, read) = row

            yield {
                'item_id': item_id,
                'title': title,
                'url': url,
                'read': (read == 1),
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
        self.c.execute('''update items set read = 1 where id = ?''', (item_id,))
        self.conn.commit()

class Screen(object):
    def __init__(self, stdscr):
        self.stdscr = stdscr

        self.mix_y = 1
        self.max_y = curses.LINES

        self.cur_y = 1
        self.cur_x = 0

    def display_menu(self):
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "rsscurses a:Add feed R:Refresh q:Quit\n", curses.A_REVERSE)


class FeedScreen(Screen):

    def display_feeds(self):
        global config

        for item in config.get_feeds():
            self.stdscr.addstr("%d\t%d/%d\t%s\n" % (item['feed_id'], item['new'], item['new'] + item['read'], item['title']))

        self.stdscr.addstr("-> ")
        self.stdscr.refresh()

        curses.echo()

    def go_up(self):
        pass

    def go_down(self):
        pass

    def loop(self):
        while True:
            self.display_menu()
            self.display_feeds()

            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in 'Aa':
                    pass
                elif chr(c) in 'Rr':
                    pass
                elif chr(c) in 'Jj':
                    self.go_up()
                elif chr(c) in 'Kk':
                    self.go_down()
                else:
                    item_screen = ItemScreen(self.stdscr, chr(c))
                    item_screen.loop()
            else:
                pass

class ItemScreen(Screen):
    def __init__(self, stdscr, feed_id):
        self.feed_id = feed_id

        super(ItemScreen, self).__init__(stdscr)

    def display_items(self):
        global config

        for item in config.get_items(self.feed_id):
            self.stdscr.addstr("%d\t%s\t%s\n" % (item['item_id'], 'N' if item['read'] else ' ', item['title']))

        self.stdscr.addstr("-> ")
        self.stdscr.refresh()

        curses.echo()

    def loop(self):
        while True:
            self.display_menu()
            self.display_items()

            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in 'Jj':
                    go_up()
                elif chr(c) in 'Kk':
                    go_down()
                else:
                    content_screen = ContentScreen(self.stdscr, chr(c))
                    content_screen.loop()

class ContentScreen(Screen):
    def __init__(self, stdscr, item_id):
        self.item_id = item_id
        super(ContentScreen, self).__init__(stdscr)

    def get_content(self):
        global config

        self.item = config.get_item(self.item_id)
        config.mark_item_as_read(self.item_id)

        render_cmd = "lynx -dump -force_html %s" % self.item['url']
        self.content = os.popen(render_cmd).read().split("\n")
        self.content.reverse()

    def display_content(self):
        self.stdscr.addstr("%s\n" % self.item['title'])
        self.stdscr.addstr("%s\n\n" % self.item['url'])

        cur_line = 1
        while cur_line < (curses.LINES - 5):
            if len(self.content) > 0:
                self.stdscr.addstr("%s\n" % self.content.pop())
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
                    pass


config = None
def open_config():
    global config

    config = Database()

    # add_url("http://www.planetpostgresql.org/atom.xml")
    config.add_feed("http://feeds2.feedburner.com/al3x")
    config.add_feed("http://www.allthingsdistributed.com/atom.xml")
    config.add_feed("http://antirez.com/rss")

    config.update_feeds()

def start_screen():
    stdscr = curses.initscr()

    curses.start_color()
    curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLUE)

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


