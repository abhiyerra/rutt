#!/usr/bin/env python

import os
import curses
import curses.wrapper
import sys
import sqlite3
import feedparser
import time
import argparse
import sys

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
                          prioritize int default 0,
                          entry_published NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          UNIQUE(url),
                          FOREIGN KEY(feed_id) REFERENCES feeds(id))''')

    def add_feed(self, url):
        url_feed = feedparser.parse(url)
        title =  url_feed.feed.title

        self.c.execute('''insert or ignore into feeds (title, url) values (?, ?)''', (title, url))
        self.conn.commit()


    def get_feeds(self, limit):
        self.c.execute('''select id, title, url, strftime('%s', updated_at), interval from feeds limit ?, ?''', limit)
        rows = self.c.fetchall()

        for row in rows:
            (feed_id, title, url, updated_at, interval) = row

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 0''', (feed_id,))
            (new_items,) = self.c.fetchone()

            self.c.execute('''select count(*) as read_items from items where feed_id = ? and read = 1''', (feed_id,))
            (read_items,) = self.c.fetchone()

            yield {
                'feed_id': feed_id,
                'title': title.encode('ascii','ignore'),
                'url': url,
                'new': new_items,
                'read': read_items,
                'updated_at': updated_at,
                'interval': interval
                }

    def update_feeds(self):
        items = []

        for item in self.get_feeds(limit=(0, -1)):
            # Yuck. Must be a better way to do this...
            #if (int(time.strftime('%s', time.gmtime())) - int(item['updated_at'])) > int(item['interval']):
            #    break

            url_feed = feedparser.parse(item['url'])

            for entry in url_feed.entries:
                print entry.title
                print entry.link
                created_at = None
                if entry.has_key('updated'):
                    created_at = entry.updated
                elif entry.has_key('published'):
                    created_at = entry.published
                elif entry.has_key('created'):
                    created_at = entry.created

                self.c.execute('''insert or ignore into items (feed_id, url, title, description, entry_published) values (?, ?, ?, ?, ?)''', (item['feed_id'], entry.link, entry.title, '', created_at,))

        self.conn.commit()

    def get_items(self, feed_id, limit):
        self.c.execute('''select id, title, url, read, entry_published, updated_at from items where feed_id = ? order by entry_published desc limit ?, ?''', (feed_id, limit[0], limit[1],))
        rows = self.c.fetchall()

        for row in rows:
            (item_id, title, url, read, entry_published, updated_at) = row

            yield {
                'item_id': item_id,
                'title': title.encode('ascii','ignore'),
                'url': url,
                'read': (read == 1),
                'published': entry_published,
                }

    def get_item(self, item_id):
        self.c.execute('''select id, title, url, entry_published from items where id = ?''', (item_id,))
        (item_id, title, url, published) = self.c.fetchone()

        return {
            'item_id': item_id,
            'title': title,
            'url': url,
            'published': published,
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
        self.stdscr.addstr(0, 0, " rutt n:Next Page p:Prev Page a:Add feed R:Refresh q:Quit\n", curses.A_REVERSE)

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

        for item in config.get_feeds(limit=self.limit):
            self.stdscr.addstr(self.cur_y, 0, "  %d/%d\t\t%s\n" % (item['new'],
                                                                   item['new'] + item['read'],
                                                                   item['title'],))
            self.feeds[self.cur_y] = item['feed_id']

            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()


    def loop(self):
        self.limit = (0, curses.LINES - 2)
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
                elif chr(c) in 'Pp':
                    self.limit = (self.limit[0] - curses.LINES - 2, self.limit[0])
                    self.stdscr.clear()
                    self.display_menu()
                    self.display_feeds()
                    self.move_pointer(0)
                elif chr(c) in 'Nn':
                    self.limit = (self.limit[1], self.limit[1] + curses.LINES - 2)
                    self.stdscr.clear()
                    self.display_menu()
                    self.display_feeds()
                    self.move_pointer(0)
                elif chr(c) == ' ':
                    item_screen = ItemScreen(self.stdscr, self.feeds[self.cur_y])
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

        for item in config.get_items(self.feed_id, limit=self.limit):
            self.stdscr.addstr(self.cur_y, 0, "  %s\t%s\t%s\n" % ('N' if not item['read'] else ' ', item['published'][0:16].replace('T', ' '), item['title']))

            self.items[self.cur_y] = item['item_id']
            self.cur_y += 1

        self.cur_y = self.min_y
        self.stdscr.refresh()

    def loop(self):
        self.limit = (0, curses.LINES - 2)
        self.display_menu()
        self.display_items()
        self.move_pointer(0)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in 'Pp':
                    self.limit = (self.limit[0] - curses.LINES - 2, self.limit[0])
                    self.stdscr.clear()
                    self.display_menu()
                    self.display_items()
                    self.move_pointer(0)
                elif chr(c) in 'Nn':
                    self.limit = (self.limit[1], self.limit[1] + curses.LINES - 2)
                    self.stdscr.clear()
                    self.display_menu()
                    self.display_items()
                    self.move_pointer(0)
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

    def move_pointer(self, pos):
        if self.cur_line + pos < 0:
            return

        self.stdscr.addstr(1, 2, "%s (%s)\n" % (self.item['title'], self.item['url']), curses.A_BOLD)

        self.cur_line = self.cur_line + pos

        lines = self.content[self.cur_line:self.cur_line + curses.LINES - 5]
        cur_y = 2
        for line in lines:
            self.stdscr.addstr(cur_y, 2, "%s\n" % line)
            cur_y += 1

        self.stdscr.refresh()

    def loop(self):
        self.cur_line = 0
        self.get_content()

        self.stdscr.clear()
        self.display_menu()
        self.move_pointer(0)

        while True:
            c = self.stdscr.getch()
            if 0 < c < 256:
                if chr(c) in 'Qq':
                    break
                elif chr(c) in ' ':
                    self.stdscr.clear()
                    self.display_menu()
                    self.move_pointer(10)
            else:
                if c == curses.KEY_UP:
                    self.stdscr.clear()
                    self.display_menu()
                    self.move_pointer(-1)
                elif c == curses.KEY_DOWN:
                    self.stdscr.clear()
                    self.display_menu()
                    self.move_pointer(1)

config = None

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
    args = parser.parse_args()

    config = Database()

    if args.add is not None:
        for url in args.add:
            try:
                config.add_feed(url)
            except:
                print "Failed to add %s" % url

        sys.exit()

    if args.reload is True:
        config.update_feeds()
        sys.exit()

    start_screen()
